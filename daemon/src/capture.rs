//! libpcap capture: live from an interface, or replayed from a pcap file.
//!
//! Each TCP segment is decoded down to its payload and handed to the
//! reassembler. Nothing here knows about the game.

use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::mpsc::SyncSender;

use anyhow::{Context, Result};
use pcap::{Capture, Linktype};
use tracing::{info, warn};

/// One TCP segment as it came off the wire.
#[derive(Debug, Clone)]
pub struct Segment {
    pub src: (IpAddr, u16),
    pub dst: (IpAddr, u16),
    pub seq: u32,
    pub ack: u32,
    pub syn: bool,
    pub fin_or_rst: bool,
    pub payload: Vec<u8>,
    pub captured_at_ms: i64,
}

pub enum Source {
    Live { iface: String },
    File { path: PathBuf, realtime: bool },
}

/// Opens the source and pushes segments into `tx` until it ends (file) or
/// fails (live). `record` saves every captured frame to a pcap file as well.
pub fn run(source: Source, record: Option<PathBuf>, tx: SyncSender<Segment>) -> Result<()> {
    match source {
        Source::Live { iface } => {
            let cap = Capture::from_device(iface.as_str())
                .with_context(|| format!("no capture device {iface}"))?
                .snaplen(65_535)
                .immediate_mode(true)
                .buffer_size(32 << 20)
                .open()
                .with_context(|| {
                    format!("cannot capture on {iface} (does the binary have cap_net_raw? see scripts/install.sh)")
                })?;
            let mut cap = cap;
            // The game talks on its own port (13328 so far); web traffic
            // (Steam downloads above all) never reaches the parser.
            cap.filter("tcp and not port 80 and not port 443", true)?;
            info!("Capturing on {iface} ({:?})", cap.get_datalink());
            pump(cap, record, tx, false)
        }
        Source::File { path, realtime } => {
            let cap = Capture::from_file(&path).with_context(|| format!("cannot open {}", path.display()))?;
            info!("Replaying {}", path.display());
            pump(cap, record, tx, realtime)
        }
    }
}

fn pump<T: pcap::Activated + ?Sized>(
    mut cap: Capture<T>,
    record: Option<PathBuf>,
    tx: SyncSender<Segment>,
    realtime: bool,
) -> Result<()> {
    let link = cap.get_datalink();
    let mut saver = match record {
        Some(path) => {
            info!("Recording raw frames to {}", path.display());
            Some(cap.savefile(&path)?)
        }
        None => None,
    };
    let mut first: Option<(i64, std::time::Instant)> = None;
    loop {
        let packet = match cap.next_packet() {
            Ok(p) => p,
            Err(pcap::Error::TimeoutExpired) => continue,
            Err(pcap::Error::NoMorePackets) => return Ok(()),
            Err(e) => return Err(e.into()),
        };
        if let Some(s) = saver.as_mut() {
            s.write(&packet);
        }
        let ts = packet.header.ts;
        let ms = ts.tv_sec as i64 * 1000 + ts.tv_usec as i64 / 1000;
        if realtime {
            let (t0, wall0) = *first.get_or_insert((ms, std::time::Instant::now()));
            let due = std::time::Duration::from_millis((ms - t0).max(0) as u64);
            if let Some(wait) = due.checked_sub(wall0.elapsed()) {
                std::thread::sleep(wait);
            }
        }
        if let Some(seg) = decode(link, packet.data, ms) {
            if tx.send(seg).is_err() {
                return Ok(());
            }
        }
    }
}

/// Link layer -> IP -> TCP. Returns None for anything that is not TCP.
fn decode(link: Linktype, frame: &[u8], captured_at_ms: i64) -> Option<Segment> {
    let ip = match link {
        Linktype::ETHERNET => {
            let mut off = 12;
            let mut ethertype = u16::from_be_bytes(frame.get(off..off + 2)?.try_into().ok()?);
            // 802.1Q / QinQ tags
            while ethertype == 0x8100 || ethertype == 0x88A8 {
                off += 4;
                ethertype = u16::from_be_bytes(frame.get(off..off + 2)?.try_into().ok()?);
            }
            frame.get(off + 2..)?
        }
        Linktype::LINUX_SLL => frame.get(16..)?,
        Linktype::LINUX_SLL2 => frame.get(20..)?,
        Linktype::NULL | Linktype::LOOP => frame.get(4..)?,
        Linktype::RAW | Linktype(12) | Linktype(14) => frame,
        other => {
            static WARNED: std::sync::Once = std::sync::Once::new();
            WARNED.call_once(|| warn!("Unsupported link type {other:?}"));
            return None;
        }
    };
    let (src_ip, dst_ip, tcp) = match ip.first()? >> 4 {
        4 => {
            let ihl = ((ip[0] & 0x0F) as usize) * 4;
            if *ip.get(9)? != 6 {
                return None;
            }
            let total = u16::from_be_bytes([*ip.get(2)?, *ip.get(3)?]) as usize;
            // Fragments other than the first carry no TCP header.
            let frag = u16::from_be_bytes([ip[6], ip[7]]) & 0x1FFF;
            if frag != 0 {
                return None;
            }
            let src: [u8; 4] = ip.get(12..16)?.try_into().ok()?;
            let dst: [u8; 4] = ip.get(16..20)?.try_into().ok()?;
            // `total` can be 0 with TSO/GRO; trust the captured length then.
            let end = if total >= ihl && total <= ip.len() { total } else { ip.len() };
            (IpAddr::from(src), IpAddr::from(dst), ip.get(ihl..end)?)
        }
        6 => {
            if *ip.get(6)? != 6 {
                return None; // extension headers: not worth it for this game
            }
            let src: [u8; 16] = ip.get(8..24)?.try_into().ok()?;
            let dst: [u8; 16] = ip.get(24..40)?.try_into().ok()?;
            let plen = u16::from_be_bytes([ip[4], ip[5]]) as usize;
            let end = if plen > 0 && 40 + plen <= ip.len() { 40 + plen } else { ip.len() };
            (IpAddr::from(src), IpAddr::from(dst), ip.get(40..end)?)
        }
        _ => return None,
    };
    let data_off = ((*tcp.get(12)? >> 4) as usize) * 4;
    let flags = *tcp.get(13)?;
    Some(Segment {
        src: (src_ip, u16::from_be_bytes([tcp[0], tcp[1]])),
        dst: (dst_ip, u16::from_be_bytes([tcp[2], tcp[3]])),
        seq: u32::from_be_bytes(tcp.get(4..8)?.try_into().ok()?),
        ack: u32::from_be_bytes(tcp.get(8..12)?.try_into().ok()?),
        syn: flags & 0x02 != 0,
        fin_or_rst: flags & 0x05 != 0,
        payload: tcp.get(data_off..)?.to_vec(),
        captured_at_ms,
    })
}

/// The interface that carries the default IPv4 route, from /proc/net/route.
pub fn default_route_iface() -> Option<String> {
    let routes = std::fs::read_to_string("/proc/net/route").ok()?;
    routes
        .lines()
        .skip(1)
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            // Destination 00000000 = default; lowest metric wins.
            (f.len() > 6 && f[1] == "00000000").then(|| (f[6].parse::<u32>().unwrap_or(u32::MAX), f[0].to_string()))
        })
        .min()
        .map(|(_, iface)| iface)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_an_ethernet_ipv4_tcp_frame() {
        let mut f = vec![0u8; 14];
        f[12] = 0x08; // IPv4
        let mut ip = vec![0x45, 0, 0, 0, 0, 0, 0x40, 0, 64, 6, 0, 0, 193, 202, 112, 172, 192, 168, 1, 14];
        let tcp = [0x34, 0x10, 0x84, 0x26, 0, 0, 0, 1, 0, 0, 0, 2, 0x50, 0x18, 0, 0, 0, 0, 0, 0];
        let total = (ip.len() + tcp.len() + 3) as u16;
        ip[2..4].copy_from_slice(&total.to_be_bytes());
        f.extend(ip);
        f.extend(tcp);
        f.extend([0x06, 0x03, 0x36]);
        let s = decode(Linktype::ETHERNET, &f, 0).unwrap();
        assert_eq!(s.src.1, 13328);
        assert_eq!(s.dst.1, 33830);
        assert_eq!((s.seq, s.ack), (1, 2));
        assert_eq!(s.payload, vec![0x06, 0x03, 0x36]);
        assert_eq!(s.src.0, IpAddr::from([193, 202, 112, 172]));
    }
}
