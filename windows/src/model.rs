//! The existing daemon wire format. Unknown fields/events remain compatible.
use serde::Deserialize;

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Capture {
    pub game_running: bool,
    pub locked: bool,
    pub error: Option<String>,
}

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Player {
    pub id: i32,
    pub name: String,
    pub job: String,
    pub dps: f64,
    pub damage: f64,
    pub share: f64,
    pub crit_rate: f64,
    pub is_local: bool,
}

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Skill {
    pub actor_id: i32,
    pub name: String,
    pub damage: f64,
    pub hits: i32,
    pub dps: f64,
    pub crit_rate: f64,
    pub back_rate: f64,
    pub is_dot: bool,
}

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Target {
    pub name: String,
    pub max_hp: i64,
    pub current_hp: i64,
}

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct State {
    pub capture: Capture,
    pub ping_ms: Option<i32>,
    pub battle_time_ms: i64,
    pub target_mode: String,
    pub target: Option<Target>,
    pub players: Vec<Player>,
    pub skills: Vec<Skill>,
}

#[derive(Clone, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Fight {
    pub id: String,
    pub boss_name: String,
    pub duration_ms: i64,
    pub killed: bool,
    pub players: Vec<Player>,
}

pub fn number(n: f64) -> String {
    if n.abs() >= 1_000_000.0 {
        format!("{:.2}m", n / 1_000_000.0)
    } else if n.abs() >= 1_000.0 {
        format!("{:.1}k", n / 1_000.0)
    } else {
        format!("{n:.0}")
    }
}

/// Saved fights carry hit counts; live skills carry precomputed rates.
pub fn read_fight(value: &serde_json::Value) -> Option<(Fight, Vec<Skill>)> {
    let mut fight: Fight = serde_json::from_value(value["summary"].clone()).ok()?;
    let seconds = (fight.duration_ms as f64 / 1000.0).max(1.0);
    let total: f64 = fight.players.iter().map(|p| p.damage).sum();
    for player in &mut fight.players {
        player.share = if total > 0.0 {
            player.damage / total * 100.0
        } else {
            0.0
        };
    }
    let skills = value["skills"]
        .as_array()?
        .iter()
        .filter_map(|value| {
            let mut skill: Skill = serde_json::from_value(value.clone()).ok()?;
            skill.dps = skill.damage / seconds;
            if !skill.is_dot && skill.hits > 0 {
                skill.crit_rate = value["crit"].as_f64().unwrap_or(0.0) / f64::from(skill.hits);
                skill.back_rate = value["back"].as_f64().unwrap_or(0.0) / f64::from(skill.hits);
            } else {
                skill.crit_rate = 0.0;
                skill.back_rate = 0.0;
            }
            Some(skill)
        })
        .collect();
    Some((fight, skills))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reads_existing_camel_case_state_and_extra_fields() {
        let state: State = serde_json::from_value(serde_json::json!({
            "type":"state", "capture":{"gameRunning":true,"locked":true,"error":null},
            "battleTimeMs":1500,"pingMs":48,"targetMode":"boss",
            "players":[{"id":7,"name":"Test","damage":9876,"dps":6584,"isLocal":true,"jobKey":"CLERIC"}],
            "skills":[{"name":"Hit","damage":9876,"critRate":0.5}], "faction":"elyos"
        })).unwrap();
        assert!(state.capture.game_running && state.capture.locked);
        assert_eq!(state.battle_time_ms, 1500);
        assert_eq!(state.players[0].id, 7);
        assert!(state.players[0].is_local);
        assert_eq!(state.skills[0].crit_rate, 0.5);
    }

    #[test]
    fn saved_fight_uses_duration_and_hit_counts_for_rates() {
        let (fight, skills) = read_fight(&serde_json::json!({
            "summary":{"id":"test", "durationMs":2000,"players":[{"id":1,"damage":750},{"id":2,"damage":250}]},
            "skills":[{"actorId":1,"name":"Hit","damage":750,"hits":4,"crit":2,"back":1}]
        })).unwrap();
        assert_eq!(fight.players[0].share, 75.0);
        assert_eq!(skills[0].dps, 375.0);
        assert_eq!(skills[0].crit_rate, 0.5);
        assert_eq!(skills[0].back_rate, 0.25);
    }

    #[test]
    fn saved_dot_rates_match_the_live_meter() {
        let (_, skills) = read_fight(&serde_json::json!({
            "summary":{"id":"dot", "durationMs":2000, "players":[]},
            "skills":[{"actorId":1,"name":"DoT","damage":100,"hits":4,"crit":4,"back":2,"isDot":true}]
        })).unwrap();
        assert!(skills[0].is_dot);
        assert_eq!(skills[0].dps, 50.0);
        assert_eq!(skills[0].crit_rate, 0.0);
        assert_eq!(skills[0].back_rate, 0.0);
    }
}
