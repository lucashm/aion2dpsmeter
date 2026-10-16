//! aion2-meter-tray: a system tray icon for the AION 2 meter. Left click opens
//! edit mode (or starts the meter); right click has the controls. It runs
//! without any special permission and stays in the tray while the meter is
//! stopped, so the meter can be started from it.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ksni::blocking::TrayMethods;
use ksni::menu::StandardItem;
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
    let _ = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
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
        let mut data = ICON.to_vec();
        if !self.status().running {
            // Stopped: greyed out.
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
            overlay_ipc("edit", None);
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
                enabled: false,
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            // DMS draws no checkmarks: the label says what a click does, and
            // the state flips at once so the rest of the menu follows.
            StandardItem {
                label: if status.running {
                    "Stop meter"
                } else {
                    "Start meter"
                }
                .into(),
                icon_name: if status.running {
                    "media-playback-stop"
                } else {
                    "media-playback-start"
                }
                .into(),
                activate: Box::new(|this: &mut Self| {
                    let mut s = this.status.lock().unwrap();
                    systemctl(if s.running { "stop" } else { "start" });
                    s.running = !s.running;
                    s.hold_until = Some(std::time::Instant::now() + Duration::from_secs(4));
                    if !s.running {
                        s.capture = None;
                    }
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Edit layout".into(),
                icon_name: "transform-move".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("edit", None)),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Fight history".into(),
                icon_name: "view-history".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("history", None)),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Show / hide widgets".into(),
                enabled: status.running,
                activate: Box::new(|_| overlay_ipc("toggle", None)),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Reset meter".into(),
                icon_name: "edit-clear".into(),
                enabled: live,
                activate: Box::new(|this: &mut Self| {
                    this.send(serde_json::json!({ "cmd": "reset" }))
                }),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                // DMS draws no checkmarks: a ✓ in the label shows it is on.
                label: if status.autostart {
                    "✓ Start at login"
                } else {
                    "    Start at login"
                }
                .into(),
                activate: Box::new(|this: &mut Self| {
                    let mut s = this.status.lock().unwrap();
                    systemctl(if s.autostart { "disable" } else { "enable" });
                    s.autostart = !s.autostart;
                    s.hold_until = Some(std::time::Instant::now() + Duration::from_secs(4));
                }),
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

/// The app icon as 64x64 ARGB32, made from desktop/aion2-meter.png by
/// scripts/tray-icon.py.
const ICON: &[u8; 64 * 64 * 4] = include_bytes!("../icon-64.argb");

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
    let status = Arc::new(Mutex::new(Status::default()));
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
        let changed = {
            let mut s = status.lock().unwrap();
            if s.hold_until.is_some_and(|t| std::time::Instant::now() < t) {
                false
            } else {
                let changed = s.running != running || s.autostart != autostart;
                s.running = running;
                s.autostart = autostart;
                changed
            }
        };
        if changed {
            handle.update(|_| {});
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}
