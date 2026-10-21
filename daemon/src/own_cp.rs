//! Your own combat power, which A2Tools only takes from the party roster: a
//! player with no party, or whose roster came before the meter started, had
//! none. Two frames state it for you alone (found in our own capture,
//! 2026-10-21, against the 106.8K the character window showed):
//!
//! ```text
//! 56 36  combat power changed: now u64 (buffs move it in a fight), highest this session u64
//! 33 36  your self record (on zone loads): ..., combat power u64, highest u64, then 65 bytes
//! ```

use std::sync::atomic::{AtomicI64, Ordering};

use a2tools::capture::stream_processor::read_varint;

static OWN_CP: AtomicI64 = AtomicI64::new(0);

/// Your last stated combat power; 0 before any.
pub fn get() -> i64 {
    OWN_CP.load(Ordering::Relaxed)
}

/// One game frame: `<length varint> <type, 2 bytes> <body>`.
pub fn frame(packet: &[u8]) {
    if let Some(cp) = read(packet) {
        OWN_CP.store(cp, Ordering::Relaxed);
    }
}

fn read(packet: &[u8]) -> Option<i64> {
    let at = read_varint(packet, 0).length;
    if at <= 0 {
        return None;
    }
    let at = at as usize;
    let body = packet.get(at + 2..)?;
    let field = match packet.get(at..at + 2)? {
        [0x56, 0x36] => body.get(..8)?,
        // shortcut: the self record's layout is only known from its end, checked on three records of one character; parse it field by field if a CP ever reads wrong.
        [0x33, 0x36] => packet.get(packet.len().checked_sub(73)?..packet.len() - 65)?,
        _ => return None,
    };
    let cp = u64::from_le_bytes(field.try_into().ok()?);
    // The roster parser's bound: anything larger is not a combat power.
    (1..=100_000_000).contains(&cp).then_some(cp as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn reads_the_change_frame_and_the_self_record() {
        assert_eq!(read(&hex("16563661a101000000000042a3010000000000")), Some(106_849));
        // A self record's head, then the last 80 bytes of a real one.
        let mut record = hex("ce123336");
        record.extend(vec![0u8; 100]);
        record.extend(hex(
            "0000000000000061a101000000000042a301000000000005019a010200000325000400000500000501120102000003250004000005000003010000001f00000002000000370000000400000001000000",
        ));
        assert_eq!(read(&record), Some(106_849));
    }

    #[test]
    fn ignores_other_frames_and_nonsense() {
        assert_eq!(read(&hex("0e003624365e5ca1010000")), None);
        // A self record too short to hold the field.
        assert_eq!(read(&hex("0533360102")), None);
        // A value past the bound.
        assert_eq!(read(&hex("16563600000000000000014ca1010000000000")), None);
    }
}
