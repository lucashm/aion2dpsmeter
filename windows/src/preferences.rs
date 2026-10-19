use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct Preferences {
    pub iface: String,
    pub auto_start: bool,
    pub overlay_visible: bool,
    pub opacity: u8,
    pub scale: u16,
    pub widgets: Vec<Widget>,
    pub pet_phase: u8,
    pub pinned_pets: Vec<String>,
    pub notify_shugo: bool,
    pub notify_invasion: bool,
    pub event_lead: u8,
    pub sound: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Widget {
    pub id: String,
    pub enabled: bool,
    pub x: f32,
    pub y: f32,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            iface: String::new(),
            auto_start: true,
            overlay_visible: false,
            opacity: 90,
            scale: 100,
            widgets: [
                ("meter", 0.02, 0.35),
                ("boss", 0.35, 0.05),
                ("ping", 0.82, 0.85),
                ("alert", 0.65, 0.18),
            ]
            .map(|(id, x, y)| Widget {
                id: id.into(),
                enabled: true,
                x,
                y,
            })
            .into(),
            pet_phase: 3,
            pinned_pets: Vec::new(),
            notify_shugo: true,
            notify_invasion: true,
            event_lead: 3,
            sound: true,
        }
    }
}

impl Preferences {
    pub fn validate(&self) -> Result<(), String> {
        if !(30..=100).contains(&self.opacity)
            || !(75..=150).contains(&self.scale)
            || !(1..=3).contains(&self.pet_phase)
            || ![1, 3, 5, 10].contains(&self.event_lead)
            || self.widgets.len() != 4
            || self.pinned_pets.len() > 500
            || self.iface.len() > 1024
        {
            return Err("Invalid companion preferences".into());
        }
        for id in ["meter", "boss", "ping", "alert"] {
            let widgets: Vec<_> = self.widgets.iter().filter(|w| w.id == id).collect();
            if widgets.len() != 1
                || !widgets[0].x.is_finite()
                || !widgets[0].y.is_finite()
                || !(0.0..=1.0).contains(&widgets[0].x)
                || !(0.0..=1.0).contains(&widgets[0].y)
            {
                return Err("Invalid overlay layout".into());
            }
        }
        Ok(())
    }

    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read(path) {
            Ok(bytes) => {
                let prefs: Self = serde_json::from_slice(&bytes)
                    .map_err(|e| format!("Cannot read preferences: {e}"))?;
                prefs.validate()?;
                Ok(prefs)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(e.to_string()),
        }
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        self.validate()?;
        let bytes = serde_json::to_vec_pretty(self).map_err(|e| e.to_string())?;
        let temp = path.with_extension("json.tmp");
        std::fs::write(&temp, bytes)
            .and_then(|_| std::fs::rename(&temp, path))
            .map_err(|e| format!("Cannot save preferences: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn layout_cannot_hide_outside_normalized_bounds_or_duplicate_widgets() {
        let mut p = Preferences::default();
        assert!(p.validate().is_ok());
        p.widgets[0].x = f32::NAN;
        assert!(p.validate().is_err());
        p.widgets[0].x = 0.5;
        p.widgets[1].id = "meter".into();
        assert!(p.validate().is_err());
    }
    #[test]
    fn click_through_is_never_persisted() {
        let value = serde_json::to_value(Preferences::default()).unwrap();
        assert!(value.get("locked").is_none());
        assert!(value.get("clickThrough").is_none());
    }
}
