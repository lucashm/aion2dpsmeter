//! Hidden cubes: an alert when one comes in range (the server sends it from
//! about 100 m), when someone starts opening it and when it's opened.
//!
//! The frames, as found by aion2-cube-radar (github.com/dr89mh/aion2-cube-radar,
//! GPL-3.0, docs/FINDINGS.md); x y z are f32 world units (cm):
//!
//! ```text
//! 34 36  object in range:  id varint, kind u16, template u32, x y z, ...
//! 35 36  object gone:      id varint, reason u8 (04 opened, 01 out of range)
//! 38 36  opening started:  object varint, actor varint, 01
//! 3A 36  opening done:     object varint, actor varint, count u32, item u32 (a cube: its key)
//! 21 36  map load:         u32, map u32, u32, u32, x y z (yours)
//! 23 36  teleport:         6 bytes, x y z (yours)
//! 2A 38  buff record:      entity varint, ..., entity varint again, 01 00, x y z (that entity's)
//! 2B 38  buff record:      caster varint, ..., caster varint, u8, u32, 02, x y z (the caster's)
//! 11 56  your bag, at login: entries of <instance u64> <item u32> <count u64> ... (found in our own capture)
//! ```
//!
//! Every cube seen is saved with its game position, per map, in
//! ~/.local/share/aion2-meter/cube-spots.json: cubes spawn on a fixed pool of
//! spots, so over time that file maps the pool where you play.
//!
//! The server never sends your own movement back, so your position comes
//! from those few frames: often in a fight, now and then while just walking.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::path::PathBuf;

use a2tools::capture::stream_processor::read_varint;

/// Cube templates seen in captures: Verteron's two and Altgard's (from Cube
/// Watch, unconfirmed). Others are learned when one is opened with a key.
const TEMPLATES: [u32; 3] = [1_200_039, 1_200_041, 1_301_199];
/// The item a cube's opening ends with: the Hidden Cube Key (Bound) spent.
const KEY_ITEM: u32 = 630_900_003;
/// Both keys that open a cube: bound and tradeable.
const KEYS: [u32; 2] = [KEY_ITEM, 610_900_001];
/// Bag frames this close together are one bag, sent in parts.
const BAG_BURST_MS: i64 = 2_000;
/// Cubes this close (world units, on the ground) are on the same spot.
const SAME_SPOT: f32 = 200.0;
/// One cube is announced once in this long, though it may leave range and come back.
const REALERT_MS: i64 = 3 * 60 * 1000;
/// Your position is good for a distance this long after it was sent.
const FIX_FRESH_MS: i64 = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    Near,
    Opening,
    Opened,
    /// Your position came in while it's in range: a new distance.
    Distance,
    /// Out of range, or you left the map.
    Left,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CubeEvent {
    pub event: Event,
    pub id: i32,
    /// Who opened it (an entity id), when the game said.
    pub actor: Option<i32>,
    /// Metres from you on the ground, when your position is fresh.
    pub distance: Option<u32>,
    /// Where it is, for one in range: the map's id and the world x y.
    pub at: Option<(u32, f32, f32)>,
}

struct Object {
    template: u32,
    pos: [f32; 3],
    opened: bool,
    /// The distance last sent for it, in metres.
    told: Option<u32>,
}

#[derive(Default)]
pub struct Cubes {
    learned: HashSet<u32>,
    /// Every object in range, cube or not: an unknown cube shows itself when opened.
    objects: HashMap<i32, Object>,
    alerted: HashMap<i32, i64>,
    /// Your last position (x, y) and when it came.
    me: Option<(f32, f32, i64)>,
    /// Your entity id, from A2Tools; your position records carry it.
    pub self_id: Option<i64>,
    /// Your Hidden Cube Keys: from the bag sent at login, less the ones you
    /// use. None until a bag is seen.
    pub keys: Option<u32>,
    bag_ms: i64,
    /// The map you're on (the game's id, 1110 = Altgard), from the last map load.
    map: Option<u32>,
    /// Cube spots seen, by map: x y z in world units.
    pub spots: BTreeMap<u32, Vec<[f32; 3]>>,
    /// Spots added since the overlay was last sent them.
    pub spots_changed: bool,
    unsaved: bool,
    path: Option<PathBuf>,
    pub events: Vec<CubeEvent>,
}

fn varint_at(b: &[u8], pos: &mut usize) -> Option<i32> {
    let v = read_varint(b, *pos);
    if v.length <= 0 {
        return None;
    }
    *pos += v.length as usize;
    Some(v.value)
}

fn u32_at(b: &[u8], pos: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(pos..pos + 4)?.try_into().ok()?))
}

/// The x y z at `pos`, if they look like world coordinates.
fn xyz_at(b: &[u8], pos: usize) -> Option<[f32; 3]> {
    let f = |p| Some(f32::from_le_bytes(b.get(p..p + 4)?.try_into().ok()?));
    let v = [f(pos)?, f(pos + 4)?, f(pos + 8)?];
    v.iter()
        .all(|v| v.is_finite() && v.abs() < 1e7)
        .then_some(v)
}

fn xy_at(b: &[u8], pos: usize) -> Option<(f32, f32)> {
    xyz_at(b, pos).map(|v| (v[0], v[1]))
}

impl Cubes {
    /// With the cube spots saved at `path`.
    pub fn load(path: PathBuf) -> Self {
        let spots = fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        Self {
            spots,
            path: Some(path),
            ..Self::default()
        }
    }

    /// Write the cube spots to disk, if any were added.
    pub fn save(&mut self) {
        let Some(path) = self.path.clone().filter(|_| self.unsaved) else {
            return;
        };
        self.unsaved = false;
        // Another meter (a recorder) may have saved spots since: keep them too.
        let on_disk: BTreeMap<u32, Vec<[f32; 3]>> = fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        for (map, theirs) in on_disk {
            let ours = self.spots.entry(map).or_default();
            for s in theirs {
                if ours
                    .iter()
                    .all(|o| (o[0] - s[0]).hypot(o[1] - s[1]) > SAME_SPOT)
                {
                    ours.push(s);
                    self.spots_changed = true;
                }
            }
        }
        let write = || -> anyhow::Result<()> {
            if let Some(dir) = path.parent() {
                fs::create_dir_all(dir)?;
            }
            let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
            fs::write(&tmp, serde_json::to_vec(&self.spots)?)?;
            fs::rename(&tmp, &path)?;
            Ok(())
        };
        if let Err(e) = write() {
            tracing::warn!("Saving cube spots to {}: {e:#}", path.display());
        }
    }

    /// A cube seen at `pos`: a new spot unless one is saved there already.
    fn spot(&mut self, pos: [f32; 3]) {
        let Some(map) = self.map else { return };
        let spots = self.spots.entry(map).or_default();
        if spots
            .iter()
            .all(|s| (s[0] - pos[0]).hypot(s[1] - pos[1]) > SAME_SPOT)
        {
            spots.push(pos);
            self.unsaved = true;
            self.spots_changed = true;
            tracing::info!("New cube spot on map {map}: {} saved there", spots.len());
        }
    }

    fn is_cube(&self, template: u32) -> bool {
        TEMPLATES.contains(&template) || self.learned.contains(&template)
    }

    /// One game frame: `<length varint> <type, 2 bytes> <body>`.
    pub fn frame(&mut self, packet: &[u8], now_ms: i64) {
        let at = read_varint(packet, 0).length;
        if at <= 0 {
            return;
        }
        let at = at as usize;
        let (Some(opcode), Some(b)) = (packet.get(at..at + 2), packet.get(at + 2..)) else {
            return;
        };
        match opcode {
            [0x34, 0x36] => self.spawn(b, now_ms),
            [0x35, 0x36] => self.removed(b),
            [0x38, 0x36] => self.opening(b, false),
            [0x3A, 0x36] => self.opening(b, true),
            [0x21, 0x36] => {
                // A load sends what's in range again.
                let live: Vec<i32> = self
                    .objects
                    .iter()
                    .filter(|(_, o)| !o.opened && self.is_cube(o.template))
                    .map(|(&id, _)| id)
                    .collect();
                self.left(live);
                self.objects.clear();
                self.map = u32_at(b, 4);
                self.fix(xy_at(b, 16), now_ms);
            }
            [0x23, 0x36] => self.fix(xy_at(b, 6), now_ms),
            [0x11, 0x56] => self.bag(b, now_ms),
            [0x2A, 0x38] | [0x2B, 0x38] => {
                let mut pos = 0;
                let Some(id) = varint_at(b, &mut pos) else {
                    return;
                };
                if self.self_id != Some(i64::from(id)) || b.len() < 12 + 2 + pos {
                    return;
                }
                let me = &b[..pos];
                let xyz = b.len() - 12;
                // 2A: <id> 01 00 x y z; 2B: <id> u8 u32 02 x y z.
                let tail = if opcode[0] == 0x2A {
                    b[xyz - 2..xyz] == [1, 0] && b[xyz - 2 - pos..xyz - 2] == *me
                } else {
                    xyz >= 6 + pos && b[xyz - 1] == 2 && b[xyz - 6 - pos..xyz - 6] == *me
                };
                if tail {
                    self.fix(xy_at(b, xyz), now_ms);
                }
            }
            _ => {}
        }
    }

    /// Keys in a bag frame: each key's item id, then its count (u64).
    fn bag(&mut self, b: &[u8], now_ms: i64) {
        let mut found = None;
        for i in 0..b.len().saturating_sub(12) {
            if u32_at(b, i).is_some_and(|item| KEYS.contains(&item)) {
                let count = u64::from_le_bytes(b[i + 4..i + 12].try_into().unwrap());
                // An item id can turn up by chance; a real count is small.
                if count < 100_000 {
                    *found.get_or_insert(0) += count as u32;
                }
            }
        }
        // No keys listed may be a partial update rather than an empty bag:
        // leave the count, so a cube is never hidden by mistake.
        let Some(found) = found else { return };
        let keys = match self.keys {
            Some(k) if now_ms - self.bag_ms <= BAG_BURST_MS => k + found,
            _ => found,
        };
        self.bag_ms = now_ms;
        tracing::info!("Hidden cube keys: {keys}");
        self.keys = Some(keys);
    }

    fn fix(&mut self, xy: Option<(f32, f32)>, now_ms: i64) {
        let Some((x, y)) = xy else { return };
        self.me = Some((x, y, now_ms));
        // The cubes in range, nearer or farther now.
        for (&id, o) in &mut self.objects {
            if o.opened || !(TEMPLATES.contains(&o.template) || self.learned.contains(&o.template))
            {
                continue;
            }
            let d = ((o.pos[0] - x).hypot(o.pos[1] - y) / 100.0).round() as u32;
            if o.told != Some(d) {
                o.told = Some(d);
                self.events.push(CubeEvent {
                    event: Event::Distance,
                    id,
                    actor: None,
                    distance: Some(d),
                    at: None,
                });
            }
        }
    }

    /// The cubes in range go: out of range, or a map load.
    fn left(&mut self, ids: Vec<i32>) {
        for id in ids {
            self.events.push(CubeEvent {
                event: Event::Left,
                id,
                actor: None,
                distance: None,
                at: None,
            });
        }
    }

    fn spawn(&mut self, b: &[u8], now_ms: i64) {
        let mut pos = 0;
        let Some(id) = varint_at(b, &mut pos) else {
            return;
        };
        let (Some(template), Some(at)) = (u32_at(b, pos + 2), xyz_at(b, pos + 6)) else {
            return;
        };
        let [x, y, _] = at;
        self.objects.insert(
            id,
            Object {
                template,
                pos: at,
                opened: false,
                told: None,
            },
        );
        if self.is_cube(template) {
            self.spot(at);
        }
        if !self.is_cube(template)
            || self
                .alerted
                .get(&id)
                .is_some_and(|t| now_ms - t < REALERT_MS)
        {
            return;
        }
        self.alerted.retain(|_, t| now_ms - *t < REALERT_MS);
        self.alerted.insert(id, now_ms);
        let distance = self
            .me
            .filter(|m| now_ms - m.2 <= FIX_FRESH_MS)
            .map(|(mx, my, _)| ((x - mx).hypot(y - my) / 100.0).round() as u32);
        if let Some(o) = self.objects.get_mut(&id) {
            o.told = distance;
        }
        self.events.push(CubeEvent {
            event: Event::Near,
            id,
            actor: None,
            distance,
            at: self.map.map(|m| (m, x, y)),
        });
    }

    fn opening(&mut self, b: &[u8], done: bool) {
        let mut pos = 0;
        let (Some(id), Some(actor)) = (varint_at(b, &mut pos), varint_at(b, &mut pos)) else {
            return;
        };
        let key = done && u32_at(b, pos + 4) == Some(KEY_ITEM);
        if key && self.self_id == Some(i64::from(actor)) {
            let used = u32_at(b, pos).unwrap_or(1);
            self.keys = self.keys.map(|k| k.saturating_sub(used));
            match self.keys {
                Some(k) => tracing::info!("Hidden cube key used: {k} left"),
                None => tracing::info!(
                    "Hidden cube key used (your count is read at login; this meter started after it)"
                ),
            }
        }
        let Some(obj) = self.objects.get_mut(&id) else {
            return;
        };
        let learned =
            key && !TEMPLATES.contains(&obj.template) && self.learned.insert(obj.template);
        let at = obj.pos;
        if learned {
            tracing::info!(
                "Learned a hidden cube template: {} (please report it)",
                obj.template
            );
        }
        if !TEMPLATES.contains(&obj.template) && !self.learned.contains(&obj.template) {
            return;
        }
        obj.opened |= done;
        let event = if done { Event::Opened } else { Event::Opening };
        self.events.push(CubeEvent {
            event,
            id,
            actor: Some(actor),
            distance: None,
            at: None,
        });
        if learned {
            self.spot(at);
        }
    }

    fn removed(&mut self, b: &[u8]) {
        let mut pos = 0;
        let Some(id) = varint_at(b, &mut pos) else {
            return;
        };
        let Some(obj) = self.objects.remove(&id) else {
            return;
        };
        if !obj.opened && self.is_cube(obj.template) && b.get(pos) == Some(&1) {
            self.left(vec![id]);
        }
        // Opened without us seeing who did it.
        if b.get(pos) == Some(&4) && !obj.opened && self.is_cube(obj.template) {
            self.events.push(CubeEvent {
                event: Event::Opened,
                id,
                actor: None,
                distance: None,
                at: None,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(opcode: [u8; 2], body: &[u8]) -> Vec<u8> {
        let mut f = vec![(body.len() + 3) as u8];
        f.extend(opcode);
        f.extend(body);
        f
    }
    fn hex(s: &str) -> Vec<u8> {
        s.split_whitespace()
            .map(|b| u8::from_str_radix(b, 16).unwrap())
            .collect()
    }
    fn xyz(x: f32, y: f32, z: f32) -> Vec<u8> {
        [x, y, z].iter().flat_map(|v| v.to_le_bytes()).collect()
    }
    // A Verteron cube from a real capture (aion2-cube-radar's FINDINGS B5/B6): id 65509 at (-50205, 126283).
    const SPAWN: &str = "e5 ff 03 04 00 a7 4f 12 00 00 1d 44 c7 80 a5 f6 47 00 64 71 46 00 00 00 00 00 00 00 00 01 01 01 aa e4 a5 34 a1 01 00 00";
    const ME: i32 = 9180; // dc 47

    #[test]
    fn a_cube_in_range_and_its_opening() {
        let mut c = Cubes {
            self_id: Some(ME.into()),
            ..Default::default()
        };
        // You, 50 m away, from a buff record: dc 47 ... dc 47 01 00 x y z.
        let mut buff = hex("dc 47 01 11 90 03 e8 03 00 00 dc 47 01 00");
        buff.extend(xyz(-50205.0 + 3000.0, 126283.0 + 4000.0, 15000.0));
        c.frame(&frame([0x2A, 0x38], &buff), 1_000);
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 2_000);
        c.frame(&frame([0x38, 0x36], &hex("e5 ff 03 dc 47 01")), 3_000);
        c.frame(
            &frame([0x3A, 0x36], &hex("e5 ff 03 dc 47 01 00 00 00 23 c5 9a 25")),
            7_000,
        );
        c.frame(&frame([0x35, 0x36], &hex("e5 ff 03 04 03 00")), 7_100);
        let e = |event, actor, distance| CubeEvent {
            event,
            id: 65509,
            actor,
            distance,
            at: None,
        };
        assert_eq!(
            c.events,
            vec![
                e(Event::Near, None, Some(50)),
                e(Event::Opening, Some(ME), None),
                e(Event::Opened, Some(ME), None)
            ]
        );
    }

    #[test]
    fn a_cube_is_announced_once_and_other_objects_never() {
        let mut c = Cubes::default();
        let mut other = hex(SPAWN);
        other[5..9].copy_from_slice(&1_590_001u32.to_le_bytes());
        other[..3].copy_from_slice(&[0x81, 0x80, 0x00]); // id 1, still 3 bytes
        c.frame(&frame([0x34, 0x36], &other), 0);
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 1_000);
        c.frame(&frame([0x35, 0x36], &hex("e5 ff 03 01")), 2_000);
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 60_000);
        let kinds: Vec<Event> = c.events.iter().map(|e| e.event).collect();
        // Announced once; going out of range says so.
        assert_eq!(kinds, vec![Event::Near, Event::Left]);
        // No position yet: no distance.
        assert_eq!(c.events[0].distance, None);
        // Opened out of sight of its opening.
        c.frame(&frame([0x35, 0x36], &hex("e5 ff 03 04 03 00")), 61_000);
        assert_eq!(c.events[2].event, Event::Opened);
        assert_eq!(c.events[2].actor, None);
    }

    #[test]
    fn the_distance_follows_you_while_it_is_in_range() {
        let mut c = Cubes {
            self_id: Some(ME.into()),
            ..Default::default()
        };
        let buff = |dx: f32| {
            let mut b = hex("dc 47 01 11 90 03 e8 03 00 00 dc 47 01 00");
            b.extend(xyz(-50205.0 + dx, 126283.0, 15000.0));
            frame([0x2A, 0x38], &b)
        };
        c.frame(&buff(4000.0), 1_000);
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 2_000);
        c.frame(&buff(4000.0), 3_000); // same place: nothing new
        c.frame(&buff(1500.0), 4_000);
        c.frame(&frame([0x21, 0x36], &[0; 32]), 5_000); // a map load: it's gone
        let got: Vec<(Event, Option<u32>)> =
            c.events.iter().map(|e| (e.event, e.distance)).collect();
        assert_eq!(
            got,
            vec![
                (Event::Near, Some(40)),
                (Event::Distance, Some(15)),
                (Event::Left, None)
            ]
        );
    }

    #[test]
    fn an_unknown_cube_is_learned_from_its_key() {
        let mut c = Cubes::default();
        let mut spawn = hex(SPAWN);
        spawn[5..9].copy_from_slice(&1_301_500u32.to_le_bytes());
        c.frame(&frame([0x34, 0x36], &spawn), 0);
        assert!(c.events.is_empty());
        c.frame(
            &frame([0x3A, 0x36], &hex("e5 ff 03 dc 47 01 00 00 00 23 c5 9a 25")),
            1_000,
        );
        assert_eq!(c.events[0].event, Event::Opened);
        c.frame(&frame([0x21, 0x36], &[0; 32]), 2_000);
        let mut again = spawn.clone();
        again[..3].copy_from_slice(&[0x82, 0x80, 0x00]);
        c.frame(&frame([0x34, 0x36], &again), 3_000);
        assert_eq!(c.events[1].event, Event::Near);
    }

    #[test]
    fn keys_come_from_the_bag_and_go_when_used() {
        let mut c = Cubes {
            self_id: Some(ME.into()),
            ..Default::default()
        };
        assert_eq!(c.keys, None);
        // Real bytes around the key in a login bag (2026-10-18, 41 keys).
        let bag = hex(
            "00 00 b5 01 00 37 33 70 37 49 6f 00 00 00 00 00 00 01 08 00 00 00 00 00 00 00 00 00 00 00 00 00 1b ec 0f 00 00 d6 00 00 23 c5 9a 25 29 00 00 00 00 00 00 00 01 22 00 00 00 00 00 00 00 00 00 00 00 00 00 9c b9 0b 00 00 7f 01 00 b4 14 99 1f 15",
        );
        c.frame(&frame([0x11, 0x56], &bag), 10_000);
        assert_eq!(c.keys, Some(41));
        // A second part of the same bag adds; a later bag starts over.
        c.frame(&frame([0x11, 0x56], &bag), 10_500);
        assert_eq!(c.keys, Some(82));
        c.frame(&frame([0x11, 0x56], &bag), 20_000);
        assert_eq!(c.keys, Some(41));
        // Opening a cube with a key spends one.
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 21_000);
        c.frame(
            &frame([0x3A, 0x36], &hex("e5 ff 03 dc 47 01 00 00 00 23 c5 9a 25")),
            22_000,
        );
        assert_eq!(c.keys, Some(40));
        // A bag frame without keys may be a partial update: the count stays.
        c.frame(&frame([0x11, 0x56], &[0; 40]), 30_000);
        assert_eq!(c.keys, Some(40));
    }

    #[test]
    fn cube_spots_are_saved_per_map_once_each() {
        let path = std::env::temp_dir().join(format!("cube-spots-{}.json", std::process::id()));
        let mut c = Cubes::load(path.clone());
        // No map load yet: the map is unknown, nothing saved.
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 0);
        assert!(c.spots.is_empty());
        // Altgard (1110 = 56 04 00 00), then the same cube twice and one 1 m away: one spot.
        let mut load = hex("01 00 00 00 56 04 00 00 00 00 00 00 00 00 00 00");
        load.extend(xyz(0.0, 0.0, 0.0));
        c.frame(&frame([0x21, 0x36], &load), 1_000);
        c.frame(&frame([0x34, 0x36], &hex(SPAWN)), 2_000);
        let mut near = hex(SPAWN);
        near[0] = 0x86; // another id, 3 bytes still
        near[9..13].copy_from_slice(&(-50105.0f32).to_le_bytes());
        c.frame(&frame([0x34, 0x36], &near), 3_000);
        assert_eq!(c.spots[&1110].len(), 1);
        c.save();
        assert_eq!(
            Cubes::load(path.clone()).spots[&1110],
            vec![[-50205.0, 126283.0, 15449.0]]
        );
        // A second meter saving its own spot keeps the first one's.
        let mut other = Cubes::load(PathBuf::from("/nonexistent"));
        other.path = Some(path.clone());
        other.map = Some(1110);
        other.spot([1000.0, 2000.0, 3.0]);
        other.save();
        assert_eq!(Cubes::load(path.clone()).spots[&1110].len(), 2);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn your_position_comes_from_teleports_and_your_own_records() {
        let mut c = Cubes {
            self_id: Some(ME.into()),
            ..Default::default()
        };
        let mut tp = vec![0; 6];
        tp.extend(xyz(100.0, 200.0, 300.0));
        c.frame(&frame([0x23, 0x36], &tp), 5);
        assert_eq!(c.me, Some((100.0, 200.0, 5)));
        // Someone else's buff record: not you.
        let mut other = hex("01 05 06 01 01 00");
        other.extend(xyz(1.0, 2.0, 3.0));
        c.frame(&frame([0x2A, 0x38], &other), 6);
        assert_eq!(c.me, Some((100.0, 200.0, 5)));
        // 2B: <id> ... <id> u8 u32 02 x y z.
        let mut b = hex("dc 47 13 84 03 00 dc 47 01 17 1d d2 00 02");
        b.extend(xyz(12944.0, -81731.0, 869.0));
        c.frame(&frame([0x2B, 0x38], &b), 7);
        assert_eq!(c.me, Some((12944.0, -81731.0, 7)));
    }
}
