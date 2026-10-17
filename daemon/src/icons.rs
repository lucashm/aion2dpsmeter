//! Skill icon URLs on the game's CDN, worked out the way A2Tools' skillIcons.js does.

use std::collections::HashMap;
use std::sync::OnceLock;

const BASE_URL: &str = "https://assets.playnccdn.com/static-aion2-gamedata/resources";

/// skill_icons.json: first 4 digits of a skill code -> icon file name.
static ICON_MAP: OnceLock<HashMap<String, String>> = OnceLock::new();

pub fn load(json: &str) {
    let _ = ICON_MAP.set(serde_json::from_str(json).unwrap_or_default());
}

/// The icon for a skill code, or None for basic attacks and unknown skills.
pub fn icon_url(code: i32) -> Option<String> {
    let mut code = code.to_string();
    if code.len() < 8 {
        code = format!("{code:0<8}");
    }
    let code = &code[..8];

    // Theostones: quality digit, then the icon number in hex.
    if code.starts_with("30") {
        let n: u32 = code[5..7].parse().ok()?;
        return (n > 0).then(|| format!("{BASE_URL}/Icon_Item_Usable_Godstone_WP_r_{n:03x}.png"));
    }
    // Basic attacks: class autos (xx0000yy, yy != 00), elementalist and spirit autos.
    let prefix = &code[..2];
    if ("11"..="18").contains(&prefix) && &code[2..6] == "0000" && &code[6..] != "00"
        || code.starts_with("1000")
        || code.starts_with("1699")
    {
        return None;
    }
    if let Some(name) = ICON_MAP.get().and_then(|m| m.get(&code[..4])) {
        return Some(format!("{BASE_URL}/{name}.png"));
    }
    let class = match prefix {
        "11" => "GL",
        "12" => "TE",
        "13" => "AS",
        "14" => "RA",
        "15" => "SO",
        "16" => "EL",
        "17" => "CL",
        "18" => "CH",
        "19" => "GT",
        _ => return None,
    };
    let sub: u32 = code[2..4].parse().ok()?;
    Some(format!("{BASE_URL}/ICON_{class}_SKILL_{sub:03}.png"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_like_a2tools() {
        load(r#"{"1201": "ICON_TE_SKILL_005"}"#);
        assert_eq!(
            icon_url(12010000).unwrap(),
            format!("{BASE_URL}/ICON_TE_SKILL_005.png")
        );
        // Not in the table: built from class and sub code.
        assert_eq!(
            icon_url(12070230).unwrap(),
            format!("{BASE_URL}/ICON_TE_SKILL_007.png")
        );
        // Basic attack.
        assert_eq!(icon_url(12000001), None);
        // Theostone: icon number 10 -> hex 00a.
        assert_eq!(
            icon_url(30001100).unwrap(),
            format!("{BASE_URL}/Icon_Item_Usable_Godstone_WP_r_00a.png")
        );
        assert_eq!(icon_url(99990000), None);
    }
}
