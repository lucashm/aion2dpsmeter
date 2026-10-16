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
            let damage: i64 = r
                .details
                .skills
                .iter()
                .filter(|s| s.actor_id == a.actor_id)
                .map(|s| s.dmg as i64)
                .sum();
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
