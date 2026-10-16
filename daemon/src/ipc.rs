//! The overlay's connection: a Unix socket carrying newline-delimited JSON.
//! The daemon broadcasts state; clients send commands.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use parking_lot::Mutex;
use serde::Deserialize;
use tracing::{debug, info, warn};

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd", rename_all = "camelCase")]
pub enum Command {
    /// Save what is on the meter, then clear it.
    Reset,
    TargetMode { mode: String },
    /// Whose skills to list; null for yourself.
    Focus { id: Option<i32> },
    History { limit: Option<usize> },
    Fight { id: String },
}

#[derive(Clone, Default)]
pub struct Clients(Arc<Mutex<Vec<UnixStream>>>);

impl Clients {
    /// Sends one JSON line to every client, dropping those that do not keep up.
    pub fn broadcast(&self, line: &str) {
        let mut clients = self.0.lock();
        clients.retain_mut(|c| {
            let ok = c.write_all(line.as_bytes()).and_then(|_| c.write_all(b"\n")).is_ok();
            if !ok {
                debug!("Overlay client dropped");
                // Its reader thread holds a clone: without this the client
                // never sees EOF, so it never reconnects.
                let _ = c.shutdown(std::net::Shutdown::Both);
            }
            ok
        });
    }

    pub fn count(&self) -> usize {
        self.0.lock().len()
    }
}

pub fn default_socket_path() -> PathBuf {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    dir.join("aion2-meter.sock")
}

/// Listens on `path`; each client gets the broadcasts, and its commands go to
/// `commands`. `on_connect` runs for a new client (to send it the current
/// state right away).
pub fn serve(
    path: &Path,
    clients: Clients,
    commands: Sender<Command>,
    on_connect: impl Fn() + Send + Sync + 'static,
) -> Result<()> {
    if UnixStream::connect(path).is_ok() {
        anyhow::bail!("another aion2-meterd is already listening on {}", path.display());
    }
    let _ = std::fs::remove_file(path);
    let listener = UnixListener::bind(path).with_context(|| format!("cannot listen on {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    info!("Overlay socket: {}", path.display());
    let on_connect = Arc::new(on_connect);
    std::thread::Builder::new().name("ipc-accept".into()).spawn(move || {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { continue };
            let _ = stream.set_write_timeout(Some(Duration::from_millis(100)));
            let Ok(reader) = stream.try_clone() else { continue };
            clients.0.lock().push(stream);
            info!("Overlay connected ({} client(s))", clients.count());
            let commands = commands.clone();
            std::thread::spawn(move || {
                for line in BufReader::new(reader).lines() {
                    let Ok(line) = line else { break };
                    if line.trim().is_empty() {
                        continue;
                    }
                    match serde_json::from_str::<Command>(&line) {
                        Ok(cmd) => {
                            if commands.send(cmd).is_err() {
                                break;
                            }
                        }
                        Err(e) => warn!("Bad command {line:?}: {e}"),
                    }
                }
            });
            on_connect();
        }
    })?;
    Ok(())
}
