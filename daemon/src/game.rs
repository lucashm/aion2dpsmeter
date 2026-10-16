//! Finds the running game under Proton and the TCP ports its sockets use,
//! straight from /proc. This replaces A2Tools' window-title check, and lets
//! the dispatcher ignore every connection that is not the game's own.

use std::collections::HashSet;
use std::fs;

#[derive(Debug, Default, Clone)]
pub struct GameState {
    pub pids: Vec<u32>,
    /// Local ports of TCP sockets held by the game's processes.
    pub local_ports: HashSet<u16>,
}

impl GameState {
    pub fn running(&self) -> bool {
        !self.pids.is_empty()
    }
}

/// The game's process name. Wine shows the Windows path in cmdline and a
/// truncated name ("AION2.exe" fits in 15 chars) in comm.
fn is_game(pid: u32) -> bool {
    let comm = fs::read_to_string(format!("/proc/{pid}/comm")).unwrap_or_default();
    if comm.trim().eq_ignore_ascii_case("AION2.exe") {
        return true;
    }
    let cmdline = fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
    let first = cmdline.split(|b| *b == 0).next().unwrap_or_default();
    let first = String::from_utf8_lossy(first).to_ascii_lowercase();
    first.ends_with("\\aion2.exe") || first.ends_with("/aion2.exe")
}

pub fn scan() -> GameState {
    let mut state = GameState::default();
    let Ok(entries) = fs::read_dir("/proc") else {
        return state;
    };
    let mut inodes = HashSet::new();
    for e in entries.flatten() {
        let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<u32>().ok()) else {
            continue;
        };
        if !is_game(pid) {
            continue;
        }
        state.pids.push(pid);
        let Ok(fds) = fs::read_dir(format!("/proc/{pid}/fd")) else {
            continue;
        };
        for fd in fds.flatten() {
            if let Ok(target) = fs::read_link(fd.path()) {
                let t = target.to_string_lossy();
                if let Some(inode) = t.strip_prefix("socket:[").and_then(|s| s.strip_suffix(']'))
                    && let Ok(n) = inode.parse::<u64>()
                {
                    inodes.insert(n);
                }
            }
        }
    }
    if inodes.is_empty() {
        return state;
    }
    // The game's process may share its netns with ours or not; its own view
    // of the tables is the one that matches its sockets.
    let netns_root = state
        .pids
        .first()
        .map(|p| format!("/proc/{p}/net"))
        .unwrap_or_else(|| "/proc/net".into());
    for table in ["tcp", "tcp6"] {
        let Ok(text) = fs::read_to_string(format!("{netns_root}/{table}")) else {
            continue;
        };
        for line in text.lines().skip(1) {
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.len() < 10 {
                continue;
            }
            let Ok(inode) = f[9].parse::<u64>() else {
                continue;
            };
            if !inodes.contains(&inode) {
                continue;
            }
            if let Some(port) = f[1]
                .rsplit(':')
                .next()
                .and_then(|p| u16::from_str_radix(p, 16).ok())
            {
                state.local_ports.insert(port);
            }
        }
    }
    state
}
