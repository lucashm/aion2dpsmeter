//! aion2-meter-tray: a system tray icon for the AION 2 meter. Left click shows
//! or hides the widgets (or starts the meter); right click has the controls. It runs
//! without any special permission and stays in the tray while the meter is
//! stopped, so the meter can be started from it.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ksni::blocking::TrayMethods;
use ksni::menu::{StandardItem, SubMenu};
use ksni::{Icon, MenuItem, ToolTip};

const UNITS: [&str; 2] = ["aion2-meterd", "aion2-meter-overlay"];
/// What the meter is doing, as far as the tray can tell.
#[derive(Debug, Clone, Default, PartialEq)]
struct Status {
    running: bool,
    autostart: bool,
    /// After a click, the services take a moment to follow; until then the
    /// poll keeps the state the click set.
    hold_until: Option<std::time::Instant>,
    /// From the daemon's socket; None while not connected.
    capture: Option<Capture>,
    /// Connected monitors, and the one the widgets are pinned to ("" = follow the game).
    monitors: Vec<String>,
    pinned: String,
    /// The overlay's "show widgets" setting.
    widgets_shown: bool,
    /// The last logged-in character's faction, "elyos" or "asmodian": picks the icon.
    faction: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
struct Capture {
    game_running: bool,
    locked: bool,
    error: Option<String>,
    ping_ms: Option<i64>,
}

impl Status {
    fn summary(&self) -> String {
        if !self.running {
            return "Meter stopped".into();
        }
        let Some(c) = &self.capture else {
            return "Starting…".into();
        };
        if let Some(e) = &c.error {
            return if e.to_lowercase().contains("cap_net_raw") {
                "No capture permission (re-run scripts/install.sh)".into()
            } else {
                format!("Capture error: {e}")
            };
        }
        if !c.game_running {
            return "Running: waiting for AION 2".into();
        }
        if !c.locked {
            return "Running: finding game traffic".into();
        }
        match c.ping_ms {
            Some(p) => format!("Capturing: {p} ms"),
            None => "Capturing".into(),
        }
    }
}

struct MeterTray {
    status: Arc<Mutex<Status>>,
    socket: Arc<Mutex<Option<UnixStream>>>,
}

impl MeterTray {
    fn status(&self) -> Status {
        self.status.lock().unwrap().clone()
    }

    fn send(&self, cmd: serde_json::Value) {
        if let Some(s) = self.socket.lock().unwrap().as_mut() {
            let _ = s.write_all(format!("{cmd}\n").as_bytes());
        }
    }
}

/// Runs a command without waiting for it, so the tray stays responsive.
fn run(program: &str, args: &[&str]) {
    let child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    // Wait on a side thread so the finished child doesn't stay a zombie.
    if let Ok(mut child) = child {
        std::thread::spawn(move || child.wait());
    }
}

fn systemctl(action: &str) {
    let mut args = vec!["--user", action];
    args.extend(UNITS);
    run("systemctl", &args);
}

fn overlay_ipc(function: &str, arg: Option<&str>) {
    let mut args = vec!["-c", "aion2-meter", "ipc", "call", "meter", function];
    args.extend(arg);
    run("qs", &args);
}

impl ksni::Tray for MeterTray {
    fn id(&self) -> String {
        "aion2-meter".into()
    }

    fn title(&self) -> String {
        "AION 2 Meter".into()
    }

    fn icon_pixmap(&self) -> Vec<Icon> {
        let status = self.status();
        let mut data = if status.faction == "asmodian" {
            ICON_ASMODIAN
        } else {
            ICON_ELYOS
        }
        .to_vec();
        if !status.running || !status.widgets_shown {
            // Stopped or widgets hidden: greyed out.
            for px in data.as_chunks_mut::<4>().0 {
                let grey =
                    ((px[1] as u32 * 30 + px[2] as u32 * 59 + px[3] as u32 * 11) / 100) as u8;
                px[0] /= 2;
                px[1..].fill(grey);
            }
        }
        vec![Icon {
            width: 64,
            height: 64,
            data,
        }]
    }

    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            title: "AION 2 Meter".into(),
            description: self.status().summary(),
            ..Default::default()
        }
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        if self.status().running {
            overlay_ipc("toggle", None);
            let mut s = self.status.lock().unwrap();
            s.widgets_shown = !s.widgets_shown;
            s.hold_until = Some(std::time::Instant::now() + Duration::from_secs(4));
        } else {
            systemctl("start");
        }
    }

    fn menu(&self) -> Vec<MenuItem<Self>> {
        let status = self.status();
        let live = status.running && status.capture.is_some();
        vec![
            StandardItem {
                label: status.summary(),
                icon_name: "dialog-information".into(),
                enabled: false,
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Customize".into(),
                icon_name: "view-grid-symbolic".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("edit", None)),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Fight history".into(),
                icon_name: "document-open-recent".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("history", None)),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Open app".into(),
                icon_name: "applications-games".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("app", None)),
                ..Default::default()
            }
            .into(),
            // A tray menu can't ask "are you sure": the submenu item is the confirmation.
            SubMenu {
                label: "Reset meter ▸".into(),
                icon_name: "edit-clear".into(),
                enabled: live,
                submenu: vec![
                    StandardItem {
                        label: "Save the fight and reset".into(),
                        icon_name: "edit-clear".into(),
                        activate: Box::new(|this: &mut Self| {
                            this.send(serde_json::json!({ "cmd": "reset" }))
                        }),
                        ..Default::default()
                    }
                    .into(),
                ],
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Restart meter".into(),
                icon_name: "view-refresh".into(),
                enabled: status.running,
                activate: Box::new(|_| systemctl("restart")),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Open fights folder".into(),
                icon_name: "folder".into(),
                activate: Box::new(|_| {
                    let dir = data_home().join("fights");
                    let _ = std::fs::create_dir_all(&dir);
                    run("xdg-open", &[&dir.to_string_lossy()]);
                }),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                // DMS draws no checkmarks: a ✓ after the label shows it is on.
                label: if status.widgets_shown {
                    "Show widgets ✓"
                } else {
                    "Show widgets"
                }
                .into(),
                icon_name: if status.widgets_shown {
                    "view-reveal-symbolic"
                } else {
                    "view-conceal-symbolic"
                }
                .into(),
                enabled: status.running,
                activate: Box::new(|this: &mut Self| {
                    overlay_ipc("toggle", None);
                    let mut s = this.status.lock().unwrap();
                    s.widgets_shown = !s.widgets_shown;
                    s.hold_until = Some(std::time::Instant::now() + Duration::from_secs(4));
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: if status.autostart {
                    "Start at login ✓"
                } else {
                    "Start at login"
                }
                .into(),
                icon_name: "system-run".into(),
                activate: Box::new(|this: &mut Self| {
                    let mut s = this.status.lock().unwrap();
                    systemctl(if s.autostart { "disable" } else { "enable" });
                    s.autostart = !s.autostart;
                    s.hold_until = Some(std::time::Instant::now() + Duration::from_secs(4));
                }),
                ..Default::default()
            }
            .into(),
            SubMenu {
                // DMS draws no submenu arrow: the label carries one.
                label: format!(
                    "Monitor: {} ▸",
                    if status.pinned.is_empty() {
                        "Follow game"
                    } else {
                        status.pinned.as_str()
                    }
                ),
                icon_name: "video-display".into(),
                enabled: status.running,
                submenu: std::iter::once(("Follow game".to_string(), String::new()))
                    .chain(status.monitors.iter().map(|m| (m.clone(), m.clone())))
                    .map(|(label, name)| {
                        let mark = if name == status.pinned {
                            "✓ "
                        } else {
                            "    "
                        };
                        StandardItem {
                            label: format!("{mark}{label}"),
                            activate: Box::new(move |this: &mut Self| {
                                // The overlay owns its settings; "follow" means unpinned.
                                overlay_ipc(
                                    "monitor",
                                    Some(if name.is_empty() { "follow" } else { &name }),
                                );
                                let mut s = this.status.lock().unwrap();
                                s.pinned = name.clone();
                                s.hold_until =
                                    Some(std::time::Instant::now() + Duration::from_secs(4));
                            }),
                            ..Default::default()
                        }
                        .into()
                    })
                    .collect(),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Quit".into(),
                icon_name: "application-exit".into(),
                // Waited for: once the tray exits, systemd ends what it started.
                activate: Box::new(|_| {
                    let mut args = vec!["--user", "stop"];
                    args.extend(UNITS);
                    let _ = Command::new("systemctl").args(&args).status();
                    std::process::exit(0)
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

fn data_home() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("aion2-meter")
}

fn socket_path() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("aion2-meter.sock")
}

/// Connected monitors by connector name (DP-2, HDMI-A-1…), which is how
/// Wayland compositors name their outputs too.
fn connected_monitors() -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir("/sys/class/drm")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            std::fs::read_to_string(e.path().join("status")).is_ok_and(|s| s.trim() == "connected")
        })
        // card1-DP-2 -> DP-2
        .filter_map(|e| Some(e.file_name().to_str()?.split_once('-')?.1.to_string()))
        .collect();
    names.sort();
    names
}

/// From the overlay's settings: the pinned monitor ("" = follow the game) and
/// whether widgets are shown.
fn overlay_settings() -> (String, bool) {
    let path = std::env::var_os("AION2_METER_CONFIG")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
                })
                .join("aion2-meter/overlay.json")
        });
    let v = std::fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .unwrap_or_default();
    (
        v["pinnedMonitor"].as_str().unwrap_or_default().to_string(),
        !v["hideWidgets"].as_bool().unwrap_or(false),
    )
}

/// The app icon per faction as 64x64 ARGB32, made by scripts/make-icons.py.
const ICON_ELYOS: &[u8; 64 * 64 * 4] = include_bytes!("../icon-elyos-64.argb");
const ICON_ASMODIAN: &[u8; 64 * 64 * 4] = include_bytes!("../icon-asmodian-64.argb");

/// Makes `faction` the icon everywhere: saved so the last logged-in character
/// keeps deciding it, and the app menu entry (whose icon notifications use
/// too) pointed at that faction's picture.
fn save_faction(faction: &str) {
    let dir = data_home();
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(dir.join("faction"), faction);
    let icon = dir.join(format!("icons/{faction}.png"));
    let Some(apps) = dir
        .parent()
        .map(|d| d.join("applications/aion2meter.desktop"))
    else {
        return;
    };
    let Ok(entry) = std::fs::read_to_string(&apps) else {
        return;
    };
    if !icon.exists() {
        return;
    }
    let updated: String = entry
        .lines()
        .map(|l| {
            if l.starts_with("Icon=") {
                format!("Icon={}\n", icon.display())
            } else {
                format!("{l}\n")
            }
        })
        .collect();
    let tmp = apps.with_extension("desktop.tmp");
    if std::fs::write(&tmp, updated).is_ok() {
        let _ = std::fs::rename(tmp, apps);
    }
}

fn is_active(args: &[&str]) -> bool {
    Command::new("systemctl")
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// Keeps a connection to the daemon and the latest capture status from it.
fn watch_socket(
    status: Arc<Mutex<Status>>,
    socket: Arc<Mutex<Option<UnixStream>>>,
    handle: ksni::blocking::Handle<MeterTray>,
) {
    loop {
        if let Ok(stream) = UnixStream::connect(socket_path()) {
            *socket.lock().unwrap() = stream.try_clone().ok();
            for line in BufReader::new(stream).lines() {
                let Ok(line) = line else { break };
                let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) else {
                    continue;
                };
                if v["type"] != "state" {
                    continue;
                }
                if let Some(f) = v["faction"]
                    .as_str()
                    .filter(|f| ["elyos", "asmodian"].contains(f))
                {
                    let mut s = status.lock().unwrap();
                    if s.faction != f {
                        s.faction = f.to_string();
                        drop(s);
                        save_faction(f);
                        handle.update(|_| {});
                    }
                }
                let c = &v["capture"];
                let capture = Capture {
                    game_running: c["gameRunning"].as_bool().unwrap_or(false),
                    locked: c["locked"].as_bool().unwrap_or(false),
                    error: c["error"].as_str().map(str::to_string),
                    ping_ms: v["pingMs"].as_i64(),
                };
                let changed = {
                    let mut s = status.lock().unwrap();
                    let changed = s.capture.as_ref() != Some(&capture);
                    s.capture = Some(capture);
                    changed
                };
                if changed {
                    handle.update(|_| {});
                }
            }
            *socket.lock().unwrap() = None;
            status.lock().unwrap().capture = None;
            handle.update(|_| {});
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

fn main() {
    let faction = std::fs::read_to_string(data_home().join("faction")).unwrap_or_default();
    let status = Arc::new(Mutex::new(Status {
        faction: faction.trim().to_string(),
        ..Default::default()
    }));
    let socket = Arc::new(Mutex::new(None));
    let tray = MeterTray {
        status: status.clone(),
        socket: socket.clone(),
    };
    let handle = match tray.spawn() {
        Ok(h) => h,
        Err(e) => {
            eprintln!("aion2-meter-tray: cannot register the tray icon: {e}");
            std::process::exit(1);
        }
    };

    {
        let (status, socket, handle) = (status.clone(), socket.clone(), handle.clone());
        std::thread::spawn(move || watch_socket(status, socket, handle));
    }

    // Service state: cheap to poll, and changes from anywhere (the app menu,
    // a terminal, the tray itself).
    loop {
        let running = is_active(&["--user", "is-active", "--quiet", UNITS[0]]);
        let autostart = is_active(&["--user", "is-enabled", "--quiet", UNITS[0]]);
        let monitors = connected_monitors();
        let (pinned, widgets_shown) = overlay_settings();
        let changed = {
            let mut s = status.lock().unwrap();
            if s.hold_until.is_some_and(|t| std::time::Instant::now() < t) {
                false
            } else {
                let changed = s.running != running
                    || s.autostart != autostart
                    || s.monitors != monitors
                    || s.pinned != pinned
                    || s.widgets_shown != widgets_shown;
                s.running = running;
                s.autostart = autostart;
                s.monitors = monitors;
                s.pinned = pinned;
                s.widgets_shown = widgets_shown;
                changed
            }
        };
        if changed {
            handle.update(|_| {});
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn saving_a_faction_repoints_the_app_menu_icon() {
        let dir = std::env::temp_dir().join(format!("aion2-tray-test-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("applications")).unwrap();
        std::fs::create_dir_all(dir.join("aion2-meter/icons")).unwrap();
        std::fs::write(dir.join("aion2-meter/icons/asmodian.png"), b"png").unwrap();
        let entry = dir.join("applications/aion2meter.desktop");
        std::fs::write(
            &entry,
            "[Desktop Entry]\nName=AION 2 Meter\nIcon=/old/elyos.png\nExec=x\n",
        )
        .unwrap();
        // SAFETY: this crate's only test that touches the environment.
        unsafe { std::env::set_var("XDG_DATA_HOME", &dir) };

        super::save_faction("asmodian");

        let icon = dir.join("aion2-meter/icons/asmodian.png");
        assert_eq!(
            std::fs::read_to_string(&entry).unwrap(),
            format!(
                "[Desktop Entry]\nName=AION 2 Meter\nIcon={}\nExec=x\n",
                icon.display()
            )
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("aion2-meter/faction")).unwrap(),
            "asmodian"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
}
