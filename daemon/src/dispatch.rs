//! Routes reassembled TCP data to A2Tools' parser: picks the game's
//! connection out of everything captured, and feeds its server-to-client
//! bytes to a `StreamProcessor` per connection.
//!
//! Adapted from A2Tools' `combat::capture_dispatcher` (GPL-3.0), which lives
//! behind its Tauri feature. Differences on Linux: the game's own sockets are
//! known from /proc (see `game`), so foreign connections never reach the
//! signature lock, and a connection the game closed releases the lock at once
//! instead of after two minutes of silence.

use std::collections::{HashMap, HashSet};
use std::net::IpAddr;
use std::sync::Arc;

use a2tools::capture::captured_payload::CapturedPayload;
use a2tools::capture::stream_assembler::StreamAssembler;
use a2tools::capture::stream_processor::StreamProcessor;
use a2tools::combat::data_storage::DataStorage;
use a2tools::combat::ping_tracker::PingTracker;
use a2tools::i18n::lookup::{NpcLookup, SkillLookup};
use tracing::info;

use crate::game::GameState;
use crate::tcp::Chunk;

/// The per-record terminator of the game's frames; `0E 00 36` since the June
/// 2026 update, `06 00 36` before.
const COMBAT_SIGNATURES: [&[u8]; 2] = [&[0x0E, 0x00, 0x36], &[0x06, 0x00, 0x36]];
/// Signature-bearing chunks a flow must produce within the window to lock.
const SIGNATURE_LOCK_THRESHOLD: u32 = 12;
const SIGNATURE_WINDOW_MS: i64 = 3_000;
/// Locked, but nothing parsed for this long: let go of the lock.
const STALE_CONNECTION_MS: i64 = 120_000;

/// A connection, by its two ports (client, server).
type ConnKey = (u16, u16);

#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptureStatus {
    pub game_running: bool,
    pub locked: bool,
    /// Why capture is not running, for the overlay to show.
    pub error: Option<String>,
}

pub struct Dispatcher {
    storage: Arc<DataStorage>,
    skills: Arc<SkillLookup>,
    npcs: Arc<NpcLookup>,
    ping: Arc<PingTracker>,
    dot_skill_ids: HashSet<i32>,
    streams: HashMap<ConnKey, (StreamAssembler, StreamProcessor)>,
    sig_hits: HashMap<ConnKey, (u32, i64)>,
    seen: HashSet<ConnKey>,
    tls: HashSet<ConnKey>,
    /// The locked game connection: (client port, server port).
    locked: Option<ConnKey>,
    last_host: Option<IpAddr>,
    /// Replaying a file: the parser's clock follows the capture's.
    pub replay: bool,
    /// Capture time of the last chunk that parsed (kept out of `status`, which
    /// the overlay is only re-sent when it changes).
    pub last_parsed_ms: i64,
    pub status: CaptureStatus,
}

impl Dispatcher {
    pub fn new(
        storage: Arc<DataStorage>,
        skills: Arc<SkillLookup>,
        npcs: Arc<NpcLookup>,
        ping: Arc<PingTracker>,
        dot_skill_ids: HashSet<i32>,
    ) -> Self {
        Self {
            storage,
            skills,
            npcs,
            ping,
            dot_skill_ids,
            streams: HashMap::new(),
            sig_hits: HashMap::new(),
            seen: HashSet::new(),
            tls: HashSet::new(),
            locked: None,
            last_host: None,
            replay: false,
            last_parsed_ms: 0,
            status: CaptureStatus::default(),
        }
    }

    /// The client port of a connection the dispatcher would like the game
    /// state refreshed for: neither side is known to belong to the game.
    pub fn is_foreign(game: &GameState, chunk: &Chunk) -> bool {
        !game.local_ports.is_empty()
            && !game.local_ports.contains(&chunk.src.1)
            && !game.local_ports.contains(&chunk.dst.1)
    }

    pub fn on_game_state(&mut self, game: &GameState) {
        let was = self.status.game_running;
        self.status.game_running = game.running();
        if was && !game.running() {
            info!("Game exited");
            self.unlock();
        }
        if !game.local_ports.is_empty() {
            // A port the game let go of may come back as a new connection:
            // forget what was decided about the old one (TLS or not).
            self.seen.retain(|k| game.local_ports.contains(&k.0));
            self.tls.retain(|k| game.local_ports.contains(&k.0));
        }
        if let Some((client, _)) = self.locked {
            if !game.local_ports.is_empty() && !game.local_ports.contains(&client) {
                info!("Game closed its connection on port {client}; looking for the next one");
                self.unlock();
            }
        }
    }

    pub fn tick(&mut self, now_ms: i64) {
        if self.locked.is_some() && self.last_parsed_ms > 0 && now_ms - self.last_parsed_ms > STALE_CONNECTION_MS {
            info!("Nothing parsed for {} s; releasing the lock", STALE_CONNECTION_MS / 1000);
            self.unlock();
        }
    }

    fn unlock(&mut self) {
        self.locked = None;
        self.status.locked = false;
        self.last_parsed_ms = 0;
        self.streams.clear();
        self.sig_hits.clear();
        self.ping.reset();
    }

    pub fn on_chunk(&mut self, game: &GameState, chunk: Chunk) {
        if !game.running() || Self::is_foreign(game, &chunk) {
            return;
        }
        // Which side is the game client: the side whose port the game holds;
        // without /proc ports, the lower-numbered side is taken as the server.
        let client_is_src = if !game.local_ports.is_empty() {
            game.local_ports.contains(&chunk.src.1)
        } else {
            chunk.src.1 > chunk.dst.1
        };
        let (client, server) = if client_is_src { (chunk.src, chunk.dst) } else { (chunk.dst, chunk.src) };
        let key: ConnKey = (client.1, server.1);
        let from_server = !client_is_src;

        // The game server also speaks TLS from its port on a second
        // connection: decided once, on the connection's first data.
        if self.seen.insert(key) && is_tls_record(&chunk.data) {
            info!("Connection {} <-> {} carries TLS: not the game", client.1, server.1);
            self.tls.insert(key);
        }
        if self.tls.contains(&key) {
            return;
        }

        if let Some(locked) = self.locked {
            // Locked: a new connection to the same server port is the game
            // moving to another server; anything else is ignored.
            if key.1 != locked.1 {
                return;
            }
            let payload = CapturedPayload {
                src_port: chunk.src.1,
                dst_port: chunk.dst.1,
                data: chunk.data.clone(),
                device_name: None,
                captured_at_ms: chunk.captured_at_ms,
                src_ip: v4(chunk.src.0),
                dst_ip: v4(chunk.dst.0),
                tcp_seq: chunk.seq,
                tcp_ack: chunk.ack,
            };
            self.ping.on_packet(&payload, locked.1);
            if !from_server {
                return;
            }
            if key != locked {
                // A second game connection (a reconnect, another server):
                // parsed alongside, and it takes the lock once it carries the
                // game's traffic at the game's rate.
                if self.count_signature(key, &chunk) >= SIGNATURE_LOCK_THRESHOLD {
                    info!("Game connection moved: client port {} -> {}", locked.0, key.0);
                    self.locked = Some(key);
                    self.streams.retain(|k, _| *k == key);
                    self.sig_hits.clear();
                }
                self.parse(key, &chunk, chunk.captured_at_ms);
                return;
            }
            if self.last_host != Some(server.0) {
                self.last_host = Some(server.0);
                self.storage.set_game_host(v4(server.0));
            }
            self.parse(key, &chunk, chunk.captured_at_ms);
            return;
        }

        // Unlocked: only server-to-client data carrying the game's record
        // terminator is worth a parse attempt, and a flow locks by sustaining
        // the rate the live game produces.
        if !from_server || !contains_any(&chunk.data, &COMBAT_SIGNATURES) {
            return;
        }
        let now = chunk.captured_at_ms;
        let hits = self.count_signature(key, &chunk);
        // Spawns and names parsed before the lock still identify mobs later.
        self.parse(key, &chunk, now);
        if hits >= SIGNATURE_LOCK_THRESHOLD {
            info!("Locked on the game connection {} <-> {}:{}", client.1, server.0, server.1);
            self.locked = Some(key);
            self.status.locked = true;
            self.streams.retain(|k, _| *k == key);
            self.sig_hits.clear();
        }
    }

    /// Counts a signature-bearing chunk against its connection within a window
    /// of SIGNATURE_WINDOW_MS from the window's first hit; returns the count.
    /// A slow trickle of look-alike bytes never reaches the threshold.
    fn count_signature(&mut self, key: ConnKey, chunk: &Chunk) -> u32 {
        if !contains_any(&chunk.data, &COMBAT_SIGNATURES) {
            return self.sig_hits.get(&key).map_or(0, |s| s.0);
        }
        let now = chunk.captured_at_ms;
        let slot = self.sig_hits.entry(key).or_insert((0, now));
        if now - slot.1 > SIGNATURE_WINDOW_MS {
            *slot = (0, now);
        }
        slot.0 += 1;
        slot.0
    }

    fn parse(&mut self, key: ConnKey, chunk: &Chunk, now: i64) {
        let (assembler, processor) = self.streams.entry(key).or_insert_with(|| {
            let mut p = StreamProcessor::new(self.storage.clone(), self.skills.clone(), self.npcs.clone());
            p.set_dot_skill_ids(self.dot_skill_ids.clone());
            (StreamAssembler::new(), p)
        });
        if chunk.after_gap {
            // The half frame before the hole can never complete.
            *assembler = StreamAssembler::new();
        }
        if self.replay {
            processor.set_override_timestamp(Some(now));
            a2tools::clock::set_override(Some(now));
        }
        if assembler.process_chunk(&chunk.data, processor) {
            self.last_parsed_ms = now;
        }
    }
}

fn v4(ip: IpAddr) -> Option<std::net::Ipv4Addr> {
    match ip {
        IpAddr::V4(a) => Some(a),
        IpAddr::V6(a) => a.to_ipv4_mapped(),
    }
}

fn is_tls_record(data: &[u8]) -> bool {
    if data.len() < 5 {
        return false;
    }
    let len = u16::from_be_bytes([data[3], data[4]]) as usize;
    (0x14..=0x17).contains(&data[0]) && data[1] == 0x03 && data[2] <= 0x04 && (1..=16_384 + 256).contains(&len)
}

fn contains_any(data: &[u8], needles: &[&[u8]]) -> bool {
    needles.iter().any(|n| data.windows(n.len()).any(|w| w == *n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_burst_of_signatures_counts_towards_the_lock() {
        use a2tools::combat::data_storage::DataStorage;
        let mut d = Dispatcher::new(
            Arc::new(DataStorage::new()),
            Arc::new(SkillLookup::new()),
            Arc::new(NpcLookup::new()),
            Arc::new(PingTracker::new()),
            HashSet::new(),
        );
        let ip = IpAddr::from([1, 1, 1, 1]);
        let chunk = |at| Chunk {
            src: (ip, 13328),
            dst: (ip, 5000),
            data: vec![0x0E, 0x00, 0x36],
            captured_at_ms: at,
            seq: 0,
            ack: 0,
            after_gap: false,
        };
        // One every 2.5 s, for a minute: never a burst.
        let trickle = (0..24).map(|i| d.count_signature((5000, 13328), &chunk(i * 2500))).max();
        assert!(trickle < Some(SIGNATURE_LOCK_THRESHOLD), "{trickle:?}");
        // The live game's rate: 12 within a second.
        let burst = (0..12).map(|i| d.count_signature((5001, 13328), &chunk(100_000 + i * 80))).last();
        assert_eq!(burst, Some(SIGNATURE_LOCK_THRESHOLD));
    }

    #[test]
    fn tells_tls_from_game_frames() {
        assert!(is_tls_record(&[0x17, 0x03, 0x03, 0x05, 0x7a, 0x88]));
        assert!(is_tls_record(&[0x16, 0x03, 0x03, 0x00, 0x5d]));
        assert!(!is_tls_record(&[0x34, 0x21, 0x36, 0x01, 0x00, 0x00]));
        assert!(!is_tls_record(&[0x24, 0x04, 0x38, 0xfe, 0x9e, 0x02]));
    }
}
