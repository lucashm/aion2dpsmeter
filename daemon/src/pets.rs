//! Pet souls: each pet's level and soul points, and the pet being farmed, for
//! the overlay's pets panel and farm widget.
//!
//! The frames are the ones A2Tools' Pet Soul Tracker plugin decodes
//! (github.com/taengu/A2Tools-Plugins, GPL-3.0):
//!
//! ```text
//! 00 90  pet list, at login and on each teleport: skip 4, <count varint> x (pet u32, skip 4, level u32),
//!                                    <count varint> x (pet u32, points u32),
//!        then each genus's insight (see `insights`)
//! 0D 90  souls gained:       <count u8> x (pet u32, amount u32), several pets at once in one pickup
//! 14 90  level up:           skip 2, pet u32, level u32
//! ```
//!
//! A pet collection is shared by every character on a server, so counts are
//! saved per server and survive the daemon starting after login.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::path::PathBuf;

use a2tools::capture::stream_processor::read_varint;
use serde::{Deserialize, Serialize};

/// Souls a pet needs to go from level N to N + 1; level 3 is the top.
pub const NEEDED: [u32; 3] = [5, 25, 75];
/// A pet list this recent belongs to the server the game just named.
const LIST_FRESH_MS: i64 = 10_000;
/// Most pets the farm widget lists, the last farmed first.
const MAX_FARMING: usize = 5;
/// A pet without a soul this long is no longer being farmed: its next soul
/// starts its count and rate over (the overlay hides it after as long).
const FARMING_IDLE_MS: i64 = 5 * 60 * 1000;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Collection {
    pub levels: BTreeMap<u32, u32>,
    pub points: BTreeMap<u32, u32>,
    /// Pets the meter levelled from their souls, which the game hasn't
    /// confirmed yet (with a level-up or the next pet list).
    #[serde(default)]
    pub estimated: BTreeSet<u32>,
    /// Genus insight by genus ("cogni", ...), from the pet list.
    #[serde(default)]
    pub genus: BTreeMap<String, Insight>,
}

/// A genus's insight: its level and the EXP gained into that level.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
pub struct Insight {
    pub level: u32,
    pub exp: u64,
}

/// The genuses by the id the game gives them, in its own order.
const GENUSES: [(u8, &str); 5] = [
    (2, "cogni"),
    (3, "fera"),
    (4, "natura"),
    (5, "varian"),
    (6, "special"),
];

/// A pet whose souls are being picked up.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Farming {
    pub pet: u32,
    pub started_ms: i64,
    pub last_ms: i64,
    /// Souls picked up since `started_ms`.
    pub gained: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PetsMessage<'a> {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub server: u16,
    pub levels: &'a BTreeMap<u32, u32>,
    pub points: &'a BTreeMap<u32, u32>,
    pub estimated: &'a BTreeSet<u32>,
    pub genus: &'a BTreeMap<String, Insight>,
    pub farming: &'a [Farming],
}

#[derive(Default, Serialize, Deserialize)]
struct Saved {
    last: u16,
    servers: HashMap<u16, Collection>,
}

#[derive(Default)]
pub struct Pets {
    pub now: Collection,
    /// The last farmed first.
    pub farming: Vec<Farming>,
    pub server: u16,
    list_ms: i64,
    saved: Saved,
    path: Option<PathBuf>,
    /// Changed since the overlay was last sent it.
    pub changed: bool,
    unsaved: bool,
}

fn u32_at(b: &[u8], pos: &mut usize) -> Option<u32> {
    let v = u32::from_le_bytes(b.get(*pos..*pos + 4)?.try_into().ok()?);
    *pos += 4;
    Some(v)
}

fn count_at(b: &[u8], pos: &mut usize) -> Option<usize> {
    let v = read_varint(b, *pos);
    if v.length <= 0 || v.value < 0 {
        return None;
    }
    *pos += v.length as usize;
    Some(v.value as usize)
}

fn pet_list(b: &[u8]) -> Option<Collection> {
    let mut pos = 4;
    let mut c = Collection::default();
    for _ in 0..count_at(b, &mut pos)? {
        let pet = u32_at(b, &mut pos)?;
        pos += 4;
        c.levels.insert(pet, u32_at(b, &mut pos)?);
    }
    for _ in 0..count_at(b, &mut pos)? {
        let pet = u32_at(b, &mut pos)?;
        c.points.insert(pet, u32_at(b, &mut pos)?);
    }
    c.genus = insights(&b[pos..]);
    Some(c)
}

/// The genus insight blocks after the pet list's two lists: each starts with
/// the genus's id twice, then its level (u32) and EXP into the level (u64).
/// What lies between them (the analysed slots) varies in length, so each is
/// found by its start, in order, taking only a level a board can have.
fn insights(b: &[u8]) -> BTreeMap<String, Insight> {
    let mut out = BTreeMap::new();
    let mut pos = 0;
    for (id, key) in GENUSES {
        while let Some(block) = b.get(pos..pos + 14) {
            pos += 1;
            if block[0] != id || block[1] != id {
                continue;
            }
            let level = u32::from_le_bytes(block[2..6].try_into().unwrap());
            let exp = u64::from_le_bytes(block[6..14].try_into().unwrap());
            if (1..=10).contains(&level) && exp < 1_000_000 {
                out.insert(key.to_string(), Insight { level, exp });
                pos += 13;
                break;
            }
        }
    }
    out
}

fn pair_at(b: &[u8], skip: usize) -> Option<(u32, u32)> {
    let mut pos = skip;
    Some((u32_at(b, &mut pos)?, u32_at(b, &mut pos)?))
}

impl Pets {
    /// Counts saved at `path`, from the server last played.
    pub fn load(path: PathBuf) -> Self {
        let saved: Saved = fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        Self {
            now: saved.servers.get(&saved.last).cloned().unwrap_or_default(),
            server: saved.last,
            saved,
            path: Some(path),
            changed: true,
            ..Self::default()
        }
    }

    /// One game frame: `<length varint> <type, 2 bytes> <body>`.
    pub fn frame(&mut self, packet: &[u8], now_ms: i64) {
        let at = read_varint(packet, 0).length;
        if at <= 0 {
            return;
        }
        let at = at as usize;
        let (Some(opcode), Some(body)) = (packet.get(at..at + 2), packet.get(at + 2..)) else {
            return;
        };
        tracing::trace!(target: "aion2_meterd::frames", "{:02X} {:02X}, {} bytes", opcode[0], opcode[1], body.len());
        // For finding new fields: RUST_LOG=aion2_meterd::dump=trace.
        tracing::trace!(target: "aion2_meterd::dump", "{:02X} {:02X} {}", opcode[0], opcode[1], body.iter().map(|b| format!("{b:02X}")).collect::<Vec<_>>().join(" "));
        match opcode {
            [0x00, 0x90] => {
                let Some(list) = pet_list(body) else { return };
                tracing::info!("Pet list: {} pets", list.levels.len());
                self.now = list;
                self.list_ms = now_ms;
            }
            [0x0D, 0x90] => {
                let count = body.first().copied().unwrap_or(0) as usize;
                let souls: Option<Vec<_>> = (0..count).map(|i| pair_at(body, 1 + 8 * i)).collect();
                let Some(souls) = souls else { return };
                for (pet, amount) in souls {
                    let was_full = self.level(pet) >= NEEDED.len() as u32;
                    *self.now.points.entry(pet).or_default() += amount;
                    self.level_up(pet);
                    self.farmed(pet, amount, was_full, now_ms);
                }
            }
            [0x14, 0x90] => {
                let Some((pet, level)) = pair_at(body, 2) else {
                    return;
                };
                // Already levelled from its souls: the extra picked up past the level stays.
                if self.level(pet) < level {
                    self.now.levels.insert(pet, level);
                    self.now.points.insert(pet, 0);
                }
                self.now.estimated.remove(&pet);
            }
            _ => return,
        }
        self.changed = true;
        self.unsaved = true;
    }

    /// A soul for `pet`: it goes to the top of the farmed list, unless it
    /// was already full before it.
    fn farmed(&mut self, pet: u32, amount: u32, was_full: bool, now_ms: i64) {
        let at = self.farming.iter().position(|f| f.pet == pet);
        let mut f = match at {
            Some(i) => self.farming.remove(i),
            None if was_full => return,
            None => Farming {
                pet,
                started_ms: now_ms,
                last_ms: now_ms,
                gained: 0,
            },
        };
        if now_ms - f.last_ms > FARMING_IDLE_MS {
            f.started_ms = now_ms;
            f.gained = 0;
        }
        f.gained += amount;
        f.last_ms = now_ms;
        self.farming.insert(0, f);
        self.farming.truncate(MAX_FARMING);
    }

    fn level(&self, pet: u32) -> u32 {
        self.now.levels.get(&pet).copied().unwrap_or(0)
    }

    /// The game doesn't send a level-up for every level, so full points level
    /// the pet themselves, the extra carrying over.
    fn level_up(&mut self, pet: u32) {
        let mut level = self.level(pet);
        let points = self.now.points.entry(pet).or_default();
        while let Some(&need) = NEEDED.get(level as usize) {
            if *points < need {
                break;
            }
            *points -= need;
            level += 1;
            self.now.estimated.insert(pet);
        }
        self.now.levels.insert(pet, level);
    }

    /// The server the game says you're on (0 until it says). A pet list just
    /// read is that server's; otherwise its saved counts come back.
    pub fn set_server(&mut self, server: u16, now_ms: i64) {
        if server == 0 || server == self.server {
            return;
        }
        if now_ms - self.list_ms > LIST_FRESH_MS {
            self.now = self.saved.servers.get(&server).cloned().unwrap_or_default();
            self.farming.clear();
        }
        self.server = server;
        self.changed = true;
        self.unsaved = true;
    }

    /// Write the counts to disk, if they changed and the server is known.
    pub fn save(&mut self) {
        if !self.unsaved || self.server == 0 {
            return;
        }
        self.unsaved = false;
        self.saved.last = self.server;
        self.saved.servers.insert(self.server, self.now.clone());
        let Some(path) = &self.path else { return };
        let write = || -> anyhow::Result<()> {
            if let Some(dir) = path.parent() {
                fs::create_dir_all(dir)?;
            }
            let tmp = path.with_extension("json.tmp");
            fs::write(&tmp, serde_json::to_vec(&self.saved)?)?;
            fs::rename(&tmp, path)?;
            Ok(())
        };
        if let Err(e) = write() {
            tracing::warn!("Saving pet souls to {}: {e:#}", path.display());
        }
    }

    pub fn message(&self) -> PetsMessage<'_> {
        PetsMessage {
            kind: "pets",
            server: self.server,
            levels: &self.now.levels,
            points: &self.now.points,
            estimated: &self.now.estimated,
            genus: &self.now.genus,
            farming: &self.farming,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A frame: a one-byte length varint, the type, the body.
    fn frame(opcode: [u8; 2], body: &[u8]) -> Vec<u8> {
        let mut f = vec![(body.len() + 3) as u8];
        f.extend(opcode);
        f.extend(body);
        f
    }

    fn soul(pet: u32, amount: u32) -> Vec<u8> {
        let mut b = vec![1];
        b.extend(pet.to_le_bytes());
        b.extend(amount.to_le_bytes());
        frame([0x0D, 0x90], &b)
    }

    #[test]
    fn the_login_list_reads() {
        let mut b = vec![0; 4];
        b.push(2);
        for (pet, level) in [(1002u32, 1u32), (1003, 3)] {
            b.extend(pet.to_le_bytes());
            b.extend([9; 4]);
            b.extend(level.to_le_bytes());
        }
        b.push(1);
        b.extend(1002u32.to_le_bytes());
        b.extend(7u32.to_le_bytes());
        let mut p = Pets::default();
        p.frame(&frame([0x00, 0x90], &b), 0);
        assert_eq!(p.now.levels, BTreeMap::from([(1002, 1), (1003, 3)]));
        assert_eq!(p.now.points, BTreeMap::from([(1002, 7)]));
        // Cut short: ignored, the counts stay.
        p.frame(&frame([0x00, 0x90], &b[..b.len() - 2]), 0);
        assert_eq!(p.now.points, BTreeMap::from([(1002, 7)]));
    }

    #[test]
    fn genus_insight_follows_the_lists() {
        // From a real pet list: a list of six, Cogni's block, slots, then Fera's;
        // "02 02 8D 01" inside the slots is not a block (its level is too high).
        let tail = "06 01 30 06 00 00 02 4A 04 00 00 03 8E 07 00 00 04 7A 06 00 00 05 74 05 00 00 06 45 19 00 00 \
                    00 05 02 02 05 00 00 00 C6 11 00 00 00 00 00 00 03 01 05 00 02 C1 00 1E 00 00 00 00 00 00 00 \
                    FB 01 02 C7 00 0C 00 00 00 00 00 00 00 02 02 8D 01 0C 00 00 00 00 00 00 00 \
                    03 03 06 00 00 00 88 13 00 00 00 00 00 00 03 01 06 00";
        let mut b = vec![0; 4];
        b.extend([0, 0]);
        b.extend(
            tail.split_whitespace()
                .map(|x| u8::from_str_radix(x, 16).unwrap()),
        );
        let c = pet_list(&b).unwrap();
        assert_eq!(
            c.genus["cogni"],
            Insight {
                level: 5,
                exp: 4550
            }
        );
        assert_eq!(
            c.genus["fera"],
            Insight {
                level: 6,
                exp: 5000
            }
        );
        assert!(!c.genus.contains_key("natura"));
    }

    #[test]
    fn souls_level_a_pet_and_carry_over() {
        let mut p = Pets::default();
        p.now.points.insert(1002, 4);
        p.frame(&soul(1002, 3), 1_000);
        assert_eq!((p.level(1002), p.now.points[&1002]), (1, 2));
        p.frame(&soul(1002, 200), 2_000);
        assert_eq!((p.level(1002), p.now.points[&1002]), (3, 102));
    }

    #[test]
    fn one_pickup_can_carry_several_pets() {
        // From a capture (2026-10-18): Pet 1126 +1 and pet 1137 +9 in one frame.
        let b = [2, 0x66, 4, 0, 0, 1, 0, 0, 0, 0x71, 4, 0, 0, 9, 0, 0, 0];
        let mut p = Pets::default();
        p.frame(&frame([0x0D, 0x90], &b), 1_000);
        assert_eq!(p.now.points, BTreeMap::from([(1126, 1), (1137, 4)]));
        assert_eq!(p.level(1137), 1);
    }

    #[test]
    fn a_level_up_after_souls_keeps_the_extra() {
        let mut p = Pets::default();
        p.now.points.insert(1002, 4);
        p.frame(&soul(1002, 3), 1_000);
        let mut b = vec![0, 0];
        b.extend(1002u32.to_le_bytes());
        b.extend(1u32.to_le_bytes());
        p.frame(&frame([0x14, 0x90], &b), 1_000);
        assert_eq!((p.level(1002), p.now.points[&1002]), (1, 2));
    }

    #[test]
    fn a_level_from_souls_is_estimated_until_the_game_says() {
        let mut p = Pets::default();
        p.now.points.insert(1002, 4);
        p.frame(&soul(1002, 1), 1_000);
        assert!(p.now.estimated.contains(&1002));
        let mut b = vec![0, 0];
        b.extend(1002u32.to_le_bytes());
        b.extend(1u32.to_le_bytes());
        p.frame(&frame([0x14, 0x90], &b), 2_000);
        assert!(p.now.estimated.is_empty());
    }

    #[test]
    fn a_level_up_frame_sets_the_level() {
        let mut p = Pets::default();
        p.now.points.insert(1004, 20);
        let mut b = vec![0, 0];
        b.extend(1004u32.to_le_bytes());
        b.extend(2u32.to_le_bytes());
        p.frame(&frame([0x14, 0x90], &b), 0);
        assert_eq!((p.level(1004), p.now.points[&1004]), (2, 0));
    }

    #[test]
    fn farming_lists_the_last_five_pets() {
        let mut p = Pets::default();
        p.frame(&soul(1002, 1), 1_000);
        p.frame(&soul(1002, 2), 5_000);
        assert_eq!(
            p.farming,
            vec![Farming {
                pet: 1002,
                started_ms: 1_000,
                last_ms: 5_000,
                gained: 3
            }]
        );
        for pet in 1003..1008 {
            p.frame(&soul(pet, 1), 9_000);
        }
        let pets = |p: &Pets| p.farming.iter().map(|f| f.pet).collect::<Vec<_>>();
        assert_eq!(pets(&p), [1007, 1006, 1005, 1004, 1003]);
        // Farmed again: back on top, its count still going.
        p.frame(&soul(1004, 1), 10_000);
        assert_eq!(pets(&p)[0], 1004);
        assert_eq!(p.farming[0].gained, 2);
        // After a long break its count and rate start over.
        p.frame(&soul(1004, 1), 10_000 + FARMING_IDLE_MS + 1);
        assert_eq!(
            (p.farming[0].gained, p.farming[0].started_ms),
            (1, 10_000 + FARMING_IDLE_MS + 1)
        );
        // An already full pet's soul lists nothing.
        p.now.levels.insert(1009, 3);
        p.frame(&soul(1009, 1), 20_000);
        assert!(!pets(&p).contains(&1009));
    }

    #[test]
    fn counts_are_kept_per_server() {
        let mut p = Pets::default();
        p.set_server(1001, 0);
        p.frame(&soul(1002, 1), 100_000);
        p.save();
        p.set_server(2001, 200_000);
        assert!(p.now.points.is_empty());
        p.set_server(1001, 300_000);
        assert_eq!(p.now.points[&1002], 1);
    }
}
