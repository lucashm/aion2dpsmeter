//! One actor owns capture and overlays. Webview polling only reads its coalesced cache.
use crate::backend::{self, Backend};
use crate::model::read_pets;
use crate::preferences::Preferences;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::os::windows::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Condvar, Mutex, mpsc};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub revision: u64,
    pub running: bool,
    pub replay: bool,
    pub replay_complete: bool,
    pub state: Value,
    pub pets: Value,
    pub fights: Value,
    pub fight: Value,
    pub adapters: Vec<backend::Adapter>,
    pub preferences: Preferences,
    pub error: Option<String>,
    pub notice: Option<Notice>,
    pub overlay_locked: bool,
    pub overlay_hotkey: bool,
    pub overlay_passthrough: bool,
    pub overlay_windows: usize,
    pub data_dir: String,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Notice {
    pub text: String,
    pub expires: u64,
}

impl Default for Snapshot {
    fn default() -> Self {
        Self {
            revision: 0,
            running: false,
            replay: false,
            replay_complete: false,
            state: json!({}),
            pets: Value::Null,
            fights: json!([]),
            fight: Value::Null,
            adapters: Vec::new(),
            preferences: Preferences::default(),
            error: None,
            notice: None,
            overlay_locked: false,
            overlay_hotkey: false,
            overlay_passthrough: false,
            overlay_windows: 0,
            data_dir: backend::data_dir().display().to_string(),
        }
    }
}

impl Snapshot {
    fn clear_live_state(&mut self) {
        self.running = false;
        self.state = json!({});
    }
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "camelCase", deny_unknown_fields)]
pub enum Action {
    Start { replay: Option<String> },
    Stop {},
    Reset {},
    Target { mode: String },
    Focus { id: Option<i32> },
    History {},
    Fight { id: String },
    Preferences { preferences: Preferences },
    RefreshAdapters {},
    LockOverlay { locked: bool },
    TestAlert {},
}

enum Request {
    Action(Action, mpsc::Sender<Result<(), String>>),
    Quit,
}

pub struct Session {
    tx: mpsc::SyncSender<Request>,
    cache: Arc<Mutex<Snapshot>>,
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
}

impl Session {
    pub fn new() -> Self {
        let cache = Arc::new(Mutex::new(Snapshot::default()));
        let (tx, rx) = mpsc::sync_channel(32);
        let shared = cache.clone();
        let thread = std::thread::spawn(move || Actor::new(shared).run(rx));
        Self {
            tx,
            cache,
            thread: Mutex::new(Some(thread)),
        }
    }
    pub fn snapshot(&self) -> Snapshot {
        self.cache.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
    pub fn act(&self, action: Action) -> Result<(), String> {
        let (tx, rx) = mpsc::channel();
        self.tx
            .try_send(Request::Action(action, tx))
            .map_err(|_| "Companion is busy or shutting down".to_string())?;
        rx.recv_timeout(Duration::from_secs(10))
            .map_err(|_| "Companion command timed out".to_string())?
    }
    pub fn shutdown(&self) {
        let mut thread = self.thread.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(handle) = thread.take() {
            let _ = self.tx.send(Request::Quit);
            let _ = handle.join();
        }
    }
}

struct Actor {
    cache: Arc<Mutex<Snapshot>>,
    snapshot: Snapshot,
    backend: Option<Backend>,
    overlay: Option<Overlay>,
    reminders: [u64; 2],
}

impl Actor {
    fn new(cache: Arc<Mutex<Snapshot>>) -> Self {
        let mut snapshot = Snapshot::default();
        let _ = std::fs::create_dir_all(backend::data_dir());
        match Preferences::load(&backend::data_dir().join("companion.json")) {
            Ok(prefs) => snapshot.preferences = prefs,
            Err(e) => snapshot.error = Some(e),
        }
        Self {
            cache,
            snapshot,
            backend: None,
            overlay: None,
            reminders: [0; 2],
        }
    }
    fn publish(&mut self) {
        self.snapshot.revision += 1;
        *self.cache.lock().unwrap_or_else(|e| e.into_inner()) = self.snapshot.clone();
        if let Some(overlay) = &self.overlay {
            overlay.push(json!({
                "state":self.snapshot.state, "preferences":self.snapshot.preferences,
                "notice":self.snapshot.notice, "locked":self.snapshot.overlay_locked,
            }));
        }
    }
    fn start(&mut self, replay: Option<String>) -> Result<(), String> {
        self.backend.take();
        self.snapshot.running = false;
        self.snapshot.state = json!({});
        self.snapshot.fight = Value::Null;
        self.snapshot.pets = Value::Null;
        self.snapshot.replay = replay.as_ref().is_some_and(|p| !p.is_empty());
        self.snapshot.replay_complete = false;
        let mut backend = Backend::start(
            &self.snapshot.preferences.iface,
            replay.as_deref().unwrap_or(""),
            true,
            || {},
        )?;
        backend.send(json!({"cmd":"history","limit":200}));
        self.backend = Some(backend);
        self.snapshot.running = true;
        self.snapshot.error = None;
        Ok(())
    }
    fn send(&mut self, value: Value) -> Result<(), String> {
        let backend = self
            .backend
            .as_mut()
            .ok_or("Start capture to use this command")?;
        backend.send(value);
        Ok(())
    }
    fn action(&mut self, action: Action) -> Result<(), String> {
        match action {
            Action::Start { replay } => self.start(replay)?,
            Action::Stop {} => {
                self.backend.take();
                self.snapshot.clear_live_state();
            }
            Action::Reset {} => self.send(json!({"cmd":"reset"}))?,
            Action::Target { mode } => {
                if !["bossTargets", "allTargets", "lastHitByMe"].contains(&mode.as_str()) {
                    return Err("Invalid target mode".into());
                }
                self.send(json!({"cmd":"targetMode","mode":mode}))?;
            }
            Action::Focus { id } => self.send(json!({"cmd":"focus","id":id}))?,
            Action::History {} => self.send(json!({"cmd":"history","limit":200}))?,
            Action::Fight { id } => {
                if id.is_empty()
                    || id.len() > 160
                    || !id
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
                {
                    return Err("Invalid fight ID".into());
                }
                self.snapshot.fight = Value::Null;
                self.send(json!({"cmd":"fight","id":id}))?;
            }
            Action::RefreshAdapters {} => self.snapshot.adapters = backend::adapters()?,
            Action::Preferences { preferences } => {
                preferences.validate()?;
                preferences.save(&backend::data_dir().join("companion.json"))?;
                self.snapshot.preferences = preferences;
                self.sync_overlay()?;
            }
            Action::LockOverlay { locked } => {
                if locked && (!self.snapshot.overlay_hotkey || self.overlay.is_none()) {
                    return Err(
                        "Open the overlays and register Ctrl+Alt+M before enabling click-through"
                            .into(),
                    );
                }
                self.snapshot.overlay_locked = locked;
            }
            Action::TestAlert {} => {
                self.notice("Test reminder · Shugo Festival starts in 3 minutes".into())
            }
        }
        Ok(())
    }
    fn notice(&mut self, text: String) {
        self.snapshot.notice = Some(Notice {
            text,
            expires: now_ms() + 10_000,
        });
        if self.snapshot.preferences.sound {
            // SAFETY: plays the system notification sound without an HWND.
            unsafe {
                windows_sys::Win32::System::Diagnostics::Debug::MessageBeep(0);
            }
        }
    }
    fn sync_overlay(&mut self) -> Result<(), String> {
        if self.snapshot.preferences.overlay_visible && self.overlay.is_none() {
            self.snapshot.overlay_locked = false;
            self.snapshot.overlay_hotkey = false;
            self.overlay = Some(Overlay::start()?);
        } else if !self.snapshot.preferences.overlay_visible {
            self.overlay.take();
            self.snapshot.overlay_locked = false;
            self.snapshot.overlay_hotkey = false;
            self.snapshot.overlay_windows = 0;
            self.snapshot.overlay_passthrough = false;
        }
        Ok(())
    }
    fn message(&mut self, value: Value) {
        match value["type"].as_str() {
            Some("state") => self.snapshot.state = value,
            Some("replayFinished") => self.snapshot.replay_complete = true,
            Some("pets") => self.snapshot.pets = read_pets(value),
            Some("history") => self.snapshot.fights = value["fights"].clone(),
            Some("fight") => self.snapshot.fight = value,
            Some("fightSaved") => {
                let _ = self.send(json!({"cmd":"history","limit":200}));
            }
            Some("cube") => match value["event"].as_str() {
                Some("near") => self.notice(format!(
                    "Hidden cube nearby · {} m",
                    value["distance"]
                        .as_f64()
                        .map(|d| format!("{d:.0}"))
                        .unwrap_or("?".into())
                )),
                Some("opening") => self.notice("Someone is opening a hidden cube".into()),
                _ => {}
            },
            _ => {}
        }
    }
    fn run(mut self, rx: mpsc::Receiver<Request>) {
        match backend::adapters() {
            Ok(adapters) => self.snapshot.adapters = adapters,
            Err(e) => self.snapshot.error = Some(e),
        }
        if self.snapshot.preferences.auto_start
            && let Err(e) = self.start(None)
        {
            self.snapshot.error = Some(e);
        }
        if let Err(e) = self.sync_overlay() {
            self.snapshot.error = Some(e);
        }
        self.publish();
        loop {
            let mut changed = false;
            match rx.recv_timeout(Duration::from_millis(25)) {
                Ok(Request::Quit) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Ok(Request::Action(action, reply)) => {
                    let result = self.action(action);
                    if let Err(e) = &result {
                        self.snapshot.error = Some(e.clone());
                    } else {
                        self.snapshot.error = None;
                    }
                    self.publish();
                    let _ = reply.send(result);
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
            for _ in 0..256 {
                let message = self.backend.as_mut().and_then(Backend::next_message);
                let Some(message) = message else { break };
                self.message(message);
                changed = true;
            }
            if let Some(result) = self.backend.as_mut().and_then(Backend::exited) {
                self.backend.take();
                // A dead capture process cannot provide live combat, HP or latency.
                self.snapshot.clear_live_state();
                if let Err(e) = result {
                    self.snapshot.error = Some(e);
                }
                changed = true;
            }
            if let Some(overlay) = &mut self.overlay {
                if let Ok(event) = overlay.events.try_recv() {
                    match event["type"].as_str() {
                        Some("hotkeyReady") => self.snapshot.overlay_hotkey = true,
                        Some("overlayStatus") => {
                            self.snapshot.overlay_windows =
                                event["windows"].as_u64().unwrap_or(0) as usize;
                            self.snapshot.overlay_passthrough =
                                event["passthrough"].as_bool().unwrap_or(false);
                        }
                        Some("toggleLock") if self.snapshot.overlay_hotkey => {
                            self.snapshot.overlay_locked = !self.snapshot.overlay_locked
                        }
                        Some("hotkeyError") => {
                            self.snapshot.overlay_hotkey = false;
                            self.snapshot.overlay_locked = false;
                            self.snapshot.error = event["error"].as_str().map(str::to_owned);
                        }
                        _ => {}
                    }
                    changed = true;
                }
                if matches!(overlay.child.try_wait(), Ok(Some(_))) {
                    self.overlay.take();
                    self.snapshot.overlay_hotkey = false;
                    self.snapshot.overlay_locked = false;
                    self.snapshot.preferences.overlay_visible = false;
                    changed = true;
                }
            }
            let now = now_ms();
            if self
                .snapshot
                .notice
                .as_ref()
                .is_some_and(|n| n.expires <= now)
            {
                self.snapshot.notice = None;
                changed = true;
            }
            if self.snapshot.state["capture"]["gameRunning"].as_bool() == Some(true) {
                for (i, (enabled, minute, name)) in [
                    (self.snapshot.preferences.notify_shugo, 0, "Shugo Festival"),
                    (
                        self.snapshot.preferences.notify_invasion,
                        30,
                        "Dimensional Invasion",
                    ),
                ]
                .into_iter()
                .enumerate()
                {
                    let next = next_event(now, minute);
                    if enabled
                        && next - now <= u64::from(self.snapshot.preferences.event_lead) * 60_000
                        && self.reminders[i] != next
                    {
                        self.reminders[i] = next;
                        self.notice(format!(
                            "{name} starts in {} minutes",
                            (next - now).div_ceil(60_000)
                        ));
                        changed = true;
                    }
                }
            }
            if changed {
                self.publish();
            }
        }
        self.overlay.take();
        self.backend.take();
    }
}

pub fn next_event(now: u64, minute: u64) -> u64 {
    let start = now / 3_600_000 * 3_600_000 + minute * 60_000;
    if start <= now {
        start + 3_600_000
    } else {
        start
    }
}

type Slot = Arc<(Mutex<(Option<Value>, bool)>, Condvar)>;
struct Overlay {
    child: Child,
    slot: Slot,
    writer: Option<std::thread::JoinHandle<()>>,
    events: mpsc::Receiver<Value>,
}
impl Overlay {
    fn start() -> Result<Self, String> {
        let mut child = Command::new(std::env::current_exe().map_err(|e| e.to_string())?)
            .arg("--overlay-stdio")
            .creation_flags(0x0800_0000)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| e.to_string())?;
        let mut input = child.stdin.take().ok_or("Overlay input missing")?;
        let out = child.stdout.take().ok_or("Overlay output missing")?;
        let slot: Slot = Arc::new((Mutex::new((None, false)), Condvar::new()));
        let shared = slot.clone();
        let writer = std::thread::spawn(move || {
            loop {
                let (mutex, ready) = &*shared;
                let mut pending = mutex.lock().unwrap_or_else(|e| e.into_inner());
                while pending.0.is_none() && !pending.1 {
                    pending = ready.wait(pending).unwrap_or_else(|e| e.into_inner());
                }
                if pending.1 {
                    break;
                }
                let value = pending.0.take().unwrap();
                drop(pending);
                if writeln!(input, "{value}")
                    .and_then(|_| input.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
        let (tx, events) = mpsc::sync_channel(8);
        std::thread::spawn(move || {
            for line in BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                if let Ok(event) = serde_json::from_str(&line)
                    && tx.send(event).is_err()
                {
                    break;
                }
            }
        });
        Ok(Self {
            child,
            slot,
            writer: Some(writer),
            events,
        })
    }
    fn push(&self, value: Value) {
        self.slot.0.lock().unwrap_or_else(|e| e.into_inner()).0 = Some(value);
        self.slot.1.notify_one();
    }
}
impl Drop for Overlay {
    fn drop(&mut self) {
        self.slot.0.lock().unwrap_or_else(|e| e.into_inner()).1 = true;
        self.slot.1.notify_one();
        let _ = self.child.kill();
        let _ = self.child.wait();
        if let Some(writer) = self.writer.take() {
            let _ = writer.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn capture_exit_invalidates_live_widgets_but_retains_saved_data() {
        let mut snapshot = Snapshot {
            running: true,
            state: json!({"capture":{"locked":true,"gameRunning":true},"pingMs":40,
                "players":[{"damage":1000}],"target":{"currentHp":50}}),
            fights: json!([{"id":"saved"}]),
            pets: json!({"levels":{"1002":1}}),
            ..Snapshot::default()
        };
        snapshot.clear_live_state();
        assert!(!snapshot.running);
        assert_eq!(snapshot.state, json!({}));
        assert_eq!(snapshot.fights[0]["id"], "saved");
        assert_eq!(snapshot.pets["levels"]["1002"], 1);
    }
    #[test]
    fn hourly_reminders_advance_once_and_cross_midnight() {
        assert_eq!(next_event(0, 0), 3_600_000);
        assert_eq!(next_event(1_700_000, 30), 1_800_000);
        assert_eq!(next_event(1_800_000, 30), 5_400_000);
    }
    #[test]
    fn native_commands_are_typed_and_reject_unexpected_input() {
        assert!(
            serde_json::from_value::<Action>(json!({"action":"shell","command":"anything"}))
                .is_err()
        );
        assert!(serde_json::from_value::<Action>(json!({"action":"reset","extra":true})).is_err());
    }
}
