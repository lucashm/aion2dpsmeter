//! Windows IPC has no public endpoint: the desktop owns these anonymous pipes.
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, mpsc::Sender};

use anyhow::Result;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd", rename_all = "camelCase")]
pub enum Command {
    Reset,
    TargetMode { mode: String },
    Focus { id: Option<i32> },
    History { limit: Option<usize> },
    Fight { id: String },
    Shutdown,
}

#[derive(Clone, Default)]
pub struct Clients(Arc<parking_lot::Mutex<()>>);

impl Clients {
    pub fn broadcast(&self, line: &str) {
        let _guard = self.0.lock();
        let mut out = std::io::stdout().lock();
        let _ = writeln!(out, "{line}").and_then(|_| out.flush());
    }
}

// Kept in the common call signature; Windows does not create a socket file.
pub fn default_socket_path() -> PathBuf {
    PathBuf::new()
}

pub fn serve(
    _path: &Path,
    _clients: Clients,
    commands: Sender<Command>,
    on_connect: impl Fn() + Send + Sync + 'static,
) -> Result<()> {
    std::thread::Builder::new()
        .name("desktop-input".into())
        .spawn(move || {
            for line in std::io::stdin().lock().lines() {
                let Ok(line) = line else { break };
                match serde_json::from_str::<Command>(&line) {
                    Ok(cmd) => {
                        if commands.send(cmd).is_err() {
                            return;
                        }
                    }
                    Err(e) => tracing::warn!("Bad desktop command: {e}"),
                }
            }
            // Closing the app's pipe also saves the fight and stops capture.
            let _ = commands.send(Command::Shutdown);
        })?;
    on_connect();
    Ok(())
}
