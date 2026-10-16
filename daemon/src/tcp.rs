//! Per-direction TCP reassembly: drops retransmissions, trims overlaps and
//! puts out-of-order segments back in order, so the game's framer sees each
//! byte of the stream once, in order. A hole that never fills (a segment the
//! capture missed) is skipped after a short wait; the parser resynchronises on
//! the next frame.

use std::collections::{BTreeMap, HashMap};
use std::net::IpAddr;

use crate::capture::Segment;

/// How long a hole may hold back later data before it is given up on.
const GAP_TIMEOUT_MS: i64 = 400;
/// Buffered out-of-order bytes per direction before a hole is given up on.
const MAX_PENDING_BYTES: usize = 1 << 20;
/// Flows silent this long are forgotten.
const IDLE_FLOW_MS: i64 = 300_000;

pub type Endpoint = (IpAddr, u16);

/// In-order bytes from one direction of one connection.
#[derive(Debug)]
pub struct Chunk {
    pub src: Endpoint,
    pub dst: Endpoint,
    pub data: Vec<u8>,
    pub captured_at_ms: i64,
    pub seq: u32,
    pub ack: u32,
    /// Bytes were lost right before this chunk.
    pub after_gap: bool,
}

#[derive(Default)]
struct Direction {
    next_seq: Option<u32>,
    /// Keyed by offset from `next_seq` at insert time is unstable, so by raw
    /// seq; comparisons use wrapping distance from `next_seq`.
    pending: BTreeMap<u32, (Vec<u8>, i64, u32)>,
    pending_bytes: usize,
    gap_since_ms: Option<i64>,
    last_seen_ms: i64,
}

#[derive(Default)]
pub struct Reassembler {
    flows: HashMap<(Endpoint, Endpoint), Direction>,
    last_gc_ms: i64,
}

fn dist(from: u32, to: u32) -> i32 {
    to.wrapping_sub(from) as i32
}

impl Reassembler {
    pub fn push(&mut self, seg: Segment, out: &mut Vec<Chunk>) {
        let now = seg.captured_at_ms;
        if now - self.last_gc_ms > 30_000 {
            self.flows.retain(|_, d| now - d.last_seen_ms < IDLE_FLOW_MS);
            self.last_gc_ms = now;
        }
        let key = (seg.src, seg.dst);
        if seg.syn {
            // A new connection on a reused 4-tuple starts over.
            let mut d = Direction::default();
            d.next_seq = Some(seg.seq.wrapping_add(1));
            d.last_seen_ms = now;
            self.flows.insert(key, d);
            return;
        }
        if seg.fin_or_rst && seg.payload.is_empty() {
            self.flows.remove(&key);
            return;
        }
        if seg.payload.is_empty() {
            return;
        }
        let d = self.flows.entry(key).or_default();
        d.last_seen_ms = now;

        let Some(next) = d.next_seq else {
            // Joined mid-stream: take this segment as the start.
            d.next_seq = Some(seg.seq.wrapping_add(seg.payload.len() as u32));
            out.push(chunk(&seg, seg.payload.clone(), seg.seq, false));
            return;
        };

        let off = dist(next, seg.seq);
        if off <= 0 {
            // Retransmission or overlap: keep only what is new.
            let skip = (-off) as usize;
            if skip < seg.payload.len() {
                let data = seg.payload[skip..].to_vec();
                d.next_seq = Some(next.wrapping_add(data.len() as u32));
                out.push(chunk(&seg, data, next, false));
                drain(d, key, now, out, false);
            }
        } else {
            // Ahead of a hole.
            if !d.pending.contains_key(&seg.seq) {
                d.pending_bytes += seg.payload.len();
                d.pending.insert(seg.seq, (seg.payload.clone(), now, seg.ack));
            }
            let started = *d.gap_since_ms.get_or_insert(now);
            if now - started > GAP_TIMEOUT_MS || d.pending_bytes > MAX_PENDING_BYTES {
                skip_hole(d, key, now, out);
            }
        }
    }

    /// Gives up on holes nothing has arrived after: a quiet stream would
    /// otherwise hold its last data back forever. `None` (end of a replay)
    /// skips every hole.
    pub fn flush(&mut self, now: Option<i64>, out: &mut Vec<Chunk>) {
        for (&key, d) in &mut self.flows {
            match now {
                Some(now) => {
                    if d.gap_since_ms.is_some_and(|t| now - t > GAP_TIMEOUT_MS) {
                        skip_hole(d, key, now, out);
                    }
                }
                None => {
                    while !d.pending.is_empty() {
                        skip_hole(d, key, d.last_seen_ms, out);
                    }
                }
            }
        }
    }
}

/// Gives up on the hole: jumps to the earliest buffered segment.
fn skip_hole(d: &mut Direction, key: (Endpoint, Endpoint), now: i64, out: &mut Vec<Chunk>) {
    let next = d.next_seq.expect("a hole has a position");
    let earliest = d.pending.keys().copied().min_by_key(|s| dist(next, *s)).expect("pending is not empty");
    d.next_seq = Some(earliest);
    drain(d, key, now, out, true);
}

/// Emits buffered segments that now continue the stream.
fn drain(d: &mut Direction, (src, dst): (Endpoint, Endpoint), now: i64, out: &mut Vec<Chunk>, mut after_gap: bool) {
    loop {
        let next = d.next_seq.expect("set before draining");
        let Some(&s) = d.pending.keys().find(|s| dist(next, **s) <= 0) else { break };
        let (data, at, ack) = d.pending.remove(&s).expect("key just found");
        d.pending_bytes -= data.len();
        let skip = (-dist(next, s)) as usize;
        if skip < data.len() {
            let data = data[skip..].to_vec();
            d.next_seq = Some(next.wrapping_add(data.len() as u32));
            out.push(Chunk {
                src,
                dst,
                data,
                captured_at_ms: at,
                seq: next,
                ack,
                after_gap,
            });
            after_gap = false;
        }
    }
    if d.pending.is_empty() {
        d.gap_since_ms = None;
    } else {
        d.gap_since_ms = Some(now);
    }
}

fn chunk(seg: &Segment, data: Vec<u8>, seq: u32, after_gap: bool) -> Chunk {
    Chunk {
        src: seg.src,
        dst: seg.dst,
        data,
        captured_at_ms: seg.captured_at_ms,
        seq,
        ack: seg.ack,
        after_gap,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seg(seq: u32, data: &[u8], at: i64) -> Segment {
        Segment {
            src: (IpAddr::from([1, 1, 1, 1]), 13328),
            dst: (IpAddr::from([2, 2, 2, 2]), 5000),
            seq,
            ack: 0,
            syn: false,
            fin_or_rst: false,
            payload: data.to_vec(),
            captured_at_ms: at,
        }
    }

    fn feed(r: &mut Reassembler, s: Segment) -> Vec<u8> {
        let mut out = Vec::new();
        r.push(s, &mut out);
        out.into_iter().flat_map(|c| c.data).collect()
    }

    #[test]
    fn reorders_dedupes_and_trims() {
        let mut r = Reassembler::default();
        assert_eq!(feed(&mut r, seg(100, b"abc", 0)), b"abc");
        assert_eq!(feed(&mut r, seg(106, b"ghi", 1)), b"", "held behind the hole");
        assert_eq!(feed(&mut r, seg(103, b"def", 2)), b"defghi");
        assert_eq!(feed(&mut r, seg(103, b"def", 3)), b"", "retransmission");
        assert_eq!(feed(&mut r, seg(107, b"hijk", 4)), b"jk", "overlap trimmed");
    }

    #[test]
    fn handles_sequence_wraparound() {
        let mut r = Reassembler::default();
        assert_eq!(feed(&mut r, seg(u32::MAX - 1, b"ab", 0)), b"ab");
        assert_eq!(feed(&mut r, seg(0, b"cd", 1)), b"cd");
    }

    #[test]
    fn a_quiet_stream_releases_data_held_behind_a_hole() {
        let mut r = Reassembler::default();
        feed(&mut r, seg(0, b"aa", 0));
        assert_eq!(feed(&mut r, seg(10, b"xx", 10)), b"");
        let mut out = Vec::new();
        r.flush(Some(10 + GAP_TIMEOUT_MS / 2), &mut out);
        assert!(out.is_empty(), "not yet");
        r.flush(Some(10 + GAP_TIMEOUT_MS + 1), &mut out);
        assert_eq!(out.into_iter().flat_map(|c| c.data).collect::<Vec<_>>(), b"xx");
        // End of a replay: every hole goes.
        feed(&mut r, seg(20, b"yy", 20));
        feed(&mut r, seg(30, b"zz", 20));
        let mut out = Vec::new();
        r.flush(None, &mut out);
        assert_eq!(out.into_iter().flat_map(|c| c.data).collect::<Vec<_>>(), b"yyzz");
    }

    #[test]
    fn gives_up_on_a_hole_after_the_timeout() {
        let mut r = Reassembler::default();
        feed(&mut r, seg(0, b"aa", 0));
        assert_eq!(feed(&mut r, seg(10, b"xx", 10)), b"");
        let mut out = Vec::new();
        r.push(seg(12, b"yy", 10 + GAP_TIMEOUT_MS + 1), &mut out);
        assert!(out[0].after_gap);
        assert_eq!(out.into_iter().flat_map(|c| c.data).collect::<Vec<_>>(), b"xxyy");
    }
}
