//! Saved boss fights, one JSON file per fight (A2Tools' `FightRecord`, so
//! nothing is lost), under $XDG_DATA_HOME/aion2-meter/fights.

use std::fs;
use std::path::PathBuf;

use a2tools::entity::fight_record::FightRecord;
use anyhow::Result;
use serde::Serialize;

/// What the history widget lists for one fight.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FightSummary {
    pub id: String,
    pub boss_name: String,
    pub start_time_ms: i64,
    pub duration_ms: i64,
    pub total_damage: i64,
    pub killed: bool,
    pub players: Vec<FightPlayer>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FightPlayer {
    pub id: i32,
    pub name: String,
    pub job: String,
    pub job_key: String,
    pub damage: i64,
    pub dps: f64,
    /// Over non-DoT hits.
    pub crit_rate: f64,
    pub back_rate: f64,
    pub heal: i64,
    pub damage_taken: i64,
    pub deaths: i32,
    pub gear_score: i32,
    pub combat_power: i64,
}

pub struct History {
    dir: PathBuf,
}

impl History {
    pub fn new(dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    fn path(&self, id: &str) -> Option<PathBuf> {
        // Ids come from the overlay too; keep them to a plain file name.
        let ok = !id.is_empty()
            && id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
        ok.then(|| self.dir.join(format!("{id}.json")))
    }

    /// Saves (or re-saves, when a fight went on) a fight.
    pub fn save(&self, record: &FightRecord) -> Result<()> {
        let Some(path) = self.path(&record.id) else {
            anyhow::bail!("unsafe fight id {:?}", record.id)
        };
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_vec(record)?)?;
        fs::rename(tmp, path)?;
        Ok(())
    }

    pub fn load(&self, id: &str) -> Option<FightRecord> {
        let text = fs::read(self.path(id)?).ok()?;
        serde_json::from_slice(&text).ok()
    }

    /// Newest first.
    pub fn list(&self, limit: usize) -> Vec<FightSummary> {
        let mut files: Vec<(std::time::SystemTime, PathBuf)> = fs::read_dir(&self.dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
            .collect();
        files.sort_by_key(|f| std::cmp::Reverse(f.0));
        let mut out: Vec<FightSummary> = files
            .into_iter()
            .take(limit)
            .filter_map(|(_, p)| serde_json::from_slice::<FightRecord>(&fs::read(p).ok()?).ok())
            .map(|r| summarize(&r))
            .collect();
        out.sort_by_key(|f| std::cmp::Reverse(f.start_time_ms));
        out
    }
}

pub fn summarize(r: &FightRecord) -> FightSummary {
    let seconds = (r.duration_ms as f64 / 1000.0).max(1.0);
    let mut players: Vec<FightPlayer> = r
        .actors
        .iter()
        .map(|a| {
            let skills = || r.details.skills.iter().filter(|s| s.actor_id == a.actor_id);
            let damage: i64 = skills().map(|s| s.dmg as i64).sum();
            let (mut hits, mut crit, mut back) = (0i64, 0i64, 0i64);
            for s in skills().filter(|s| !s.is_dot) {
                hits += s.time as i64;
                crit += s.crit as i64;
                back += s.back as i64;
            }
            let rate = |n: i64| {
                if hits > 0 {
                    n as f64 / hits as f64
                } else {
                    0.0
                }
            };
            FightPlayer {
                id: a.actor_id,
                name: if a.nickname.is_empty() {
                    format!("#{}", a.actor_id)
                } else {
                    a.nickname.clone()
                },
                job: crate::meter::job_names(&a.job).1.to_string(),
                job_key: crate::meter::job_names(&a.job).0.to_string(),
                damage,
                dps: damage as f64 / seconds,
                crit_rate: rate(crit),
                back_rate: rate(back),
                heal: r
                    .details
                    .heal_skills
                    .iter()
                    .filter(|s| s.actor_id == a.actor_id)
                    .map(|s| s.dmg as i64)
                    .sum(),
                damage_taken: a.damage_received,
                deaths: r
                    .details
                    .deaths
                    .iter()
                    .flatten()
                    .filter(|d| d.actor_id == a.actor_id)
                    .count() as i32,
                gear_score: a.gear_score,
                combat_power: a.combat_power,
            }
        })
        .filter(|p| p.damage > 0)
        .collect();
    players.sort_by_key(|p| std::cmp::Reverse(p.damage));
    FightSummary {
        id: r.id.clone(),
        boss_name: r.boss_name.clone(),
        start_time_ms: r.start_time_ms,
        duration_ms: r.duration_ms,
        total_damage: r.total_damage as i64,
        killed: r.details.max_hp > 0 && r.total_damage as i64 >= r.details.max_hp as i64,
        players,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn skill(
        actor: i32,
        dmg: i32,
        hits: i32,
        crit: i32,
        back: i32,
        dot: bool,
    ) -> serde_json::Value {
        serde_json::json!({"actorId": actor, "code": 1, "name": "s", "time": hits, "dmg": dmg,
            "multiHitCount": 0, "multiHitDamage": 0, "crit": crit, "parry": 0, "back": back,
            "perfect": 0, "double": 0, "regen": 0, "isDot": dot})
    }

    #[test]
    fn summary_has_each_players_rates_heals_and_deaths() {
        let record: FightRecord = serde_json::from_value(serde_json::json!({
            "id": "auto_1_2", "bossName": "Boss", "targetId": 1, "startTimeMs": 0,
            "durationMs": 10_000, "totalDamage": 1300, "jobs": [],
            "details": {"targetId": 1, "maxHp": 1000, "totalTargetDamage": 1300, "battleTime": 10_000,
                "skills": [skill(7, 1000, 10, 4, 2, false), skill(7, 200, 30, 30, 30, true), skill(8, 100, 5, 0, 5, false)],
                "healSkills": [skill(8, 300, 3, 0, 0, false), skill(8, 50, 1, 0, 0, true)],
                "deaths": [{"actorId": 7, "tsMs": 1000}, {"actorId": 7, "tsMs": 5000}]},
            "actors": [
                {"actorId": 7, "nickname": "A", "damageReceived": 900, "gearScore": 1700, "combatPower": 80000},
                {"actorId": 8, "nickname": "B"}
            ]
        }))
        .unwrap();
        let s = summarize(&record);
        assert!(s.killed);
        let a = &s.players[0];
        assert_eq!(
            (a.name.as_str(), a.damage, a.deaths, a.damage_taken, a.heal),
            ("A", 1200, 2, 900, 0)
        );
        // The DoT's hits don't count toward the rates.
        assert_eq!((a.crit_rate, a.back_rate), (0.4, 0.2));
        assert_eq!((a.gear_score, a.combat_power), (1700, 80000));
        let b = &s.players[1];
        assert_eq!((b.heal, b.deaths, b.back_rate), (350, 0, 1.0));
    }
}
