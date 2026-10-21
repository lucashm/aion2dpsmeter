//! Turns A2Tools' combat aggregates into the compact state the overlay
//! draws: ranked players, the focused player's skills, the target's HP, the
//! fight timer and ping.

use std::collections::HashMap;
use std::sync::Arc;

use a2tools::combat::data_storage::DataStorage;
use a2tools::combat::dps_calculator::DpsCalculator;
use a2tools::combat::ping_tracker::PingTracker;
use a2tools::entity::dps_data::DpsData;
use a2tools::entity::summon_resolver;
use serde::Serialize;

use crate::dispatch::CaptureStatus;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlayerRow {
    pub id: i32,
    pub name: String,
    /// English class name, empty when unknown.
    pub job: String,
    /// Stable class key (GLADIATOR, CLERIC, ...) for colours and icons.
    pub job_key: String,
    pub dps: f64,
    pub damage: f64,
    pub share: f64,
    pub crit_rate: f64,
    pub is_local: bool,
    /// From the party roster; 0 for players outside your party.
    pub combat_power: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SkillRow {
    pub code: i32,
    pub name: String,
    pub damage: i64,
    pub hits: i32,
    pub share: f64,
    pub dps: f64,
    pub crit_rate: f64,
    pub back_rate: f64,
    pub is_dot: bool,
    /// Icon URL on the game's CDN; None for basic attacks.
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Target {
    pub id: i32,
    pub name: String,
    pub is_boss: bool,
    pub max_hp: i64,
    /// -1 when the game has not sent a live HP reading.
    pub current_hp: i64,
    pub damage_taken: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct OverlayState {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub capture: CaptureStatus,
    pub ping_ms: Option<i32>,
    pub target_mode: String,
    pub target: Option<Target>,
    pub battle_time_ms: i64,
    pub players: Vec<PlayerRow>,
    /// Whose skills `skills` lists: the focused player, else you.
    pub skills_of: Option<i32>,
    pub skills: Vec<SkillRow>,
    /// "elyos" or "asmodian", from your server; None until the game says.
    pub faction: Option<&'static str>,
    /// The character you're playing; None until the game says.
    pub character: Option<String>,
}

pub struct Meter {
    pub calc: DpsCalculator,
    storage: Arc<DataStorage>,
    ping: Arc<PingTracker>,
    pub focus: Option<i32>,
    details_gen: i64,
    details_focus: Option<i32>,
    details_target: i32,
    crit_by_actor: HashMap<i32, f64>,
    skills: Vec<SkillRow>,
}

impl Meter {
    pub fn new(calc: DpsCalculator, storage: Arc<DataStorage>, ping: Arc<PingTracker>) -> Self {
        Self {
            calc,
            storage,
            ping,
            focus: None,
            details_gen: -1,
            details_focus: None,
            details_target: 0,
            crit_by_actor: HashMap::new(),
            skills: Vec::new(),
        }
    }

    pub fn state(&mut self, capture: CaptureStatus) -> OverlayState {
        let dps: DpsData = self.calc.get_dps();
        let local = dps.local_player_id.map(|id| id as i32);
        let skills_of = self.focus.filter(|id| dps.map.contains_key(id)).or(local);
        let seconds = (dps.battle_time as f64 / 1000.0).max(1.0);

        // Per-skill details are heavier than the totals: redone only when
        // there was new damage, or the focus or target changed.
        let generation = self.storage.damage_generation();
        if generation != self.details_gen
            || skills_of != self.details_focus
            || dps.target_id != self.details_target
        {
            self.details_gen = generation;
            self.details_focus = skills_of;
            self.details_target = dps.target_id;
            self.refresh_details(&dps, skills_of, seconds);
        }

        let mut players: Vec<PlayerRow> = dps
            .map
            .iter()
            .filter(|(_, p)| p.amount > 0.0)
            .map(|(&id, p)| PlayerRow {
                id,
                name: if p.nickname.is_empty() {
                    format!("#{id}")
                } else {
                    p.nickname.clone()
                },
                job: job_names(&p.job).1.to_string(),
                job_key: job_names(&p.job).0.to_string(),
                dps: p.dps,
                damage: p.amount,
                share: p.damage_contribution,
                crit_rate: self.crit_by_actor.get(&id).copied().unwrap_or(0.0),
                is_local: Some(id) == local,
                // Yours as the game last stated it, which needs no party roster.
                combat_power: match crate::own_cp::get() {
                    cp if cp > 0 && Some(id) == local => cp,
                    _ => p.combat_power,
                },
            })
            .collect();
        players.sort_by(|a, b| b.damage.total_cmp(&a.damage).then(a.id.cmp(&b.id)));

        let target = (dps.target_id != 0).then(|| Target {
            id: dps.target_id,
            name: dps.target_name.clone(),
            is_boss: dps.target_is_boss,
            max_hp: dps.target_max_hp,
            current_hp: dps.target_current_hp,
            damage_taken: dps.target_total_damage,
        });

        OverlayState {
            kind: "state",
            capture,
            ping_ms: self.ping.current_ping_ms(),
            target_mode: dps.target_mode.clone(),
            target,
            battle_time_ms: dps.battle_time,
            players,
            skills_of,
            skills: self.skills.clone(),
            faction: faction_of(self.storage.fight_server_id()),
            character: self.storage.local_character_name(),
        }
    }

    fn refresh_details(&mut self, dps: &DpsData, skills_of: Option<i32>, seconds: f64) {
        let targets: Vec<i32> = if dps.detail_target_ids.is_empty() {
            (dps.target_id != 0)
                .then_some(dps.target_id)
                .into_iter()
                .collect()
        } else {
            dps.detail_target_ids.clone()
        };
        let summons = self.storage.get_summon_data();
        let mut hits: HashMap<i32, (i64, i64)> = HashMap::new();
        let mut skills: HashMap<(i32, bool), SkillRow> = HashMap::new();
        for &t in &targets {
            let details = self.calc.get_hover_details(t, None);
            for s in &details.skills {
                let owner = summon_resolver::resolve(s.actor_id, &summons);
                if !s.is_dot {
                    let e = hits.entry(owner).or_default();
                    e.0 += s.crit as i64;
                    e.1 += s.time as i64;
                }
                if Some(owner) == skills_of {
                    let row = skills
                        .entry((s.code, s.is_dot))
                        .or_insert_with(|| SkillRow {
                            code: s.code,
                            name: s.name.clone(),
                            damage: 0,
                            hits: 0,
                            share: 0.0,
                            dps: 0.0,
                            crit_rate: 0.0,
                            back_rate: 0.0,
                            is_dot: s.is_dot,
                            icon: crate::icons::icon_url(s.code),
                        });
                    row.damage += s.dmg as i64;
                    row.hits += s.time;
                    // Rates are summed as counts here and divided below.
                    row.crit_rate += s.crit as f64;
                    row.back_rate += s.back as f64;
                }
            }
        }
        self.crit_by_actor = hits
            .into_iter()
            .map(|(id, (crit, total))| {
                (
                    id,
                    if total > 0 {
                        crit as f64 / total as f64
                    } else {
                        0.0
                    },
                )
            })
            .collect();
        let total: i64 = skills.values().map(|s| s.damage).sum();
        let mut rows: Vec<SkillRow> = skills
            .into_values()
            .map(|mut s| {
                let n = s.hits.max(1) as f64;
                s.crit_rate = if s.is_dot { 0.0 } else { s.crit_rate / n };
                s.back_rate = if s.is_dot { 0.0 } else { s.back_rate / n };
                s.share = if total > 0 {
                    s.damage as f64 / total as f64
                } else {
                    0.0
                };
                s.dps = s.damage as f64 / seconds;
                s
            })
            .collect();
        rows.sort_by(|a, b| b.damage.cmp(&a.damage).then(a.code.cmp(&b.code)));
        self.skills = rows;
    }
}

/// A2Tools names classes in Korean; the overlay wants a key and English.
pub fn job_names(job: &str) -> (&'static str, &'static str) {
    match job {
        "검성" | "Gladiator" => ("GLADIATOR", "Gladiator"),
        "수호성" | "Templar" => ("TEMPLAR", "Templar"),
        "궁성" | "Ranger" => ("RANGER", "Ranger"),
        "살성" | "Assassin" => ("ASSASSIN", "Assassin"),
        "마도성" | "Sorcerer" => ("SORCERER", "Sorcerer"),
        "치유성" | "Cleric" => ("CLERIC", "Cleric"),
        "정령성" | "Spiritmaster" | "Elementalist" => ("ELEMENTALIST", "Spiritmaster"),
        "호법성" | "Chanter" => ("CHANTER", "Chanter"),
        "권성" | "Brawler" | "Fighter" => ("FIGHTER", "Brawler"),
        _ => ("", ""),
    }
}

/// A server's faction: its id is 1xxx for Elyos, 2xxx for Asmodian.
pub fn faction_of(server_id: u16) -> Option<&'static str> {
    match server_id {
        1000..=1999 => Some("elyos"),
        2000..=2999 => Some("asmodian"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::faction_of;

    #[test]
    fn a_server_id_names_its_faction() {
        assert_eq!(faction_of(1304), Some("elyos"));
        assert_eq!(faction_of(2014), Some("asmodian"));
        assert_eq!(faction_of(0), None);
    }
}
