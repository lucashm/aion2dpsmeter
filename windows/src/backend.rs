//! Owns one daemon. Its stdin/stdout are private pipes; stderr is a local log.
use std::io::{BufRead, BufReader, Write};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use eframe::egui;
use serde::{Deserialize, Serialize};
use serde_json::Value;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub fn data_dir() -> PathBuf {
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("aion2-meter")
}

fn command() -> Result<Command, String> {
    let system = std::env::var_os("SystemRoot")
        .map(PathBuf::from)
        .unwrap_or_else(|| "C:/Windows".into());
    if !system.join("System32/wpcap.dll").is_file() {
        return Err("Npcap is required. Install 64-bit Npcap from https://npcap.com/#download with 'WinPcap API-compatible Mode' enabled, then restart the app.".into());
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let daemon = exe.with_file_name("aion2-meterd.exe");
    if !daemon.is_file() {
        return Err(
            "aion2-meterd.exe is missing. Extract the entire Windows ZIP before starting the app."
                .into(),
        );
    }
    let mut command = Command::new(daemon);
    command.creation_flags(CREATE_NO_WINDOW);
    Ok(command)
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Adapter {
    pub name: String,
    pub description: Option<String>,
    pub addresses: Vec<String>,
}

pub fn adapters() -> Result<Vec<Adapter>, String> {
    let output = command()?
        .arg("--list-interfaces")
        .output()
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(format!(
            "Cannot load Npcap ({}). Install 64-bit Npcap in WinPcap API-compatible mode, then restart the app. {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| format!("Cannot read Npcap adapters: {e}"))
}

pub struct Backend {
    // The OS releases this capture lock even when the app crashes.
    _lock: std::fs::File,
    child: Child,
    input: Option<ChildStdin>,
    messages: Receiver<Value>,
    output_closed: bool,
}

impl Backend {
    pub fn start(
        iface: &str,
        replay: &str,
        stay_open: bool,
        wake: impl Fn() + Send + 'static,
    ) -> Result<Self, String> {
        let mut command = command()?;
        std::fs::create_dir_all(data_dir()).map_err(|e| e.to_string())?;
        let lock = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(data_dir().join("capture.lock"))
            .map_err(|e| e.to_string())?;
        lock.try_lock().map_err(|e| {
            format!("Cannot start capture: another meter may already be running ({e}).")
        })?;
        // Truncate on each start so a long-running capture cannot fill the disk
        // across restarts. Traffic is never recorded unless --record is used.
        let log =
            std::fs::File::create(data_dir().join("capture.log")).map_err(|e| e.to_string())?;
        command.arg("--stdio");
        if !replay.is_empty() {
            command.args(["--pcap", replay, "--realtime"]);
            if stay_open {
                command.arg("--stay-open");
            }
        } else if !iface.is_empty() {
            command.args(["--iface", iface]);
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(log)
            .spawn()
            .map_err(|e| format!("Cannot start capture: {e}"))?;
        let input = child.stdin.take();
        let out = child.stdout.take().expect("piped stdout");
        let (tx, messages) = mpsc::sync_channel(64);
        std::thread::spawn(move || {
            for line in BufReader::new(out).lines() {
                let Ok(line) = line else { break };
                if let Ok(value) = serde_json::from_str(&line) {
                    if tx.send(value).is_err() {
                        break;
                    }
                    wake();
                }
            }
            drop(tx);
            wake();
        });
        Ok(Self {
            _lock: lock,
            child,
            input,
            messages,
            output_closed: false,
        })
    }

    pub fn send(&mut self, value: Value) {
        if let Some(input) = &mut self.input {
            let _ = writeln!(input, "{value}");
        }
    }

    pub fn next_message(&mut self) -> Option<Value> {
        match self.messages.try_recv() {
            Ok(message) => Some(message),
            Err(mpsc::TryRecvError::Empty) => None,
            Err(mpsc::TryRecvError::Disconnected) => {
                self.output_closed = true;
                None
            }
        }
    }

    pub fn exited(&mut self) -> Option<Result<(), String>> {
        // A process can exit before its reader forwards the last stdout line.
        // Disconnection is observed only after all queued messages are consumed.
        if !self.output_closed {
            return None;
        }
        match self.child.try_wait() {
            Ok(Some(status)) if status.success() => Some(Ok(())),
            Ok(Some(status)) => Some(Err(format!(
                "Capture exited ({status}). See {}. Check Npcap and the selected adapter.",
                data_dir().join("capture.log").display()
            ))),
            Err(e) => Some(Err(e.to_string())),
            Ok(None) => None,
        }
    }
}

impl Drop for Backend {
    fn drop(&mut self) {
        self.send(serde_json::json!({"cmd":"shutdown"}));
        self.input.take();
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            // Drain events so the output pipe cannot block the daemon's save.
            while self.messages.try_recv().is_ok() {}
            if matches!(self.child.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub enum Hotkey {
    Ready,
    Toggle,
    Error(String),
}

pub fn hotkey(ctx: egui::Context) -> Receiver<Hotkey> {
    use windows_sys::Win32::UI::{
        Input::KeyboardAndMouse::{MOD_ALT, MOD_CONTROL, MOD_NOREPEAT, RegisterHotKey},
        WindowsAndMessaging::{GetMessageW, MSG, WM_HOTKEY},
    };
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        // SAFETY: hotkey belongs to this thread's message queue, with no HWND.
        unsafe {
            let modifiers = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
            // Isolated native QA does not compete with an already running user's meter.
            #[cfg(feature = "ui-smoke")]
            let modifiers = if std::env::var_os("AION2_COMPANION_SMOKE_REPORT").is_some() {
                modifiers | windows_sys::Win32::UI::Input::KeyboardAndMouse::MOD_SHIFT
            } else {
                modifiers
            };
            if RegisterHotKey(std::ptr::null_mut(), 1, modifiers, u32::from(b'M')) == 0 {
                let _ = tx.send(Hotkey::Error("Ctrl+Alt+M is in use. Click-through is disabled; close the other hotkey app and restart to enable it.".into()));
                ctx.request_repaint();
                return;
            }
            let _ = tx.send(Hotkey::Ready);
            ctx.request_repaint();
            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
                if msg.message == WM_HOTKEY {
                    if tx.send(Hotkey::Toggle).is_err() {
                        break;
                    }
                    ctx.request_repaint();
                }
            }
        }
    });
    rx
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn finished_backend() -> (Backend, mpsc::SyncSender<Value>) {
        let mut child = Command::new("cmd.exe")
            .args(["/C", "exit 0"])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
            .unwrap();
        assert!(child.wait().unwrap().success());
        let (tx, messages) = mpsc::sync_channel(4);
        (
            Backend {
                _lock: std::fs::File::open("NUL").unwrap(),
                child,
                input: None,
                messages,
                output_closed: false,
            },
            tx,
        )
    }

    #[test]
    fn process_exit_waits_for_delayed_stdout_reader() {
        let (mut backend, reader) = finished_backend();
        assert!(backend.next_message().is_none());
        assert!(backend.exited().is_none());

        let final_state = json!({"type":"state", "players":[{"id":1,"damage":27200}]});
        reader.send(final_state.clone()).unwrap();
        drop(reader);
        assert_eq!(backend.next_message(), Some(final_state));
        assert!(backend.next_message().is_none());
        assert!(backend.exited().unwrap().is_ok());
    }

    #[test]
    fn process_exit_waits_for_all_queued_messages() {
        let (mut backend, reader) = finished_backend();
        let state = json!({"type":"state"});
        let pets = json!({"type":"pets"});
        reader.send(state.clone()).unwrap();
        reader.send(pets.clone()).unwrap();
        drop(reader);

        assert!(backend.exited().is_none());
        assert_eq!(backend.next_message(), Some(state));
        assert!(backend.exited().is_none());
        assert_eq!(backend.next_message(), Some(pets));
        assert!(backend.next_message().is_none());
        assert!(backend.exited().unwrap().is_ok());
    }
}
