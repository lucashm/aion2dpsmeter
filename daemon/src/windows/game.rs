//! Process and socket ownership via Toolhelp and IP Helper; no game handles,
//! memory access, window-title heuristics, or external PowerShell processes.
use std::collections::HashSet;
use std::mem::{size_of, zeroed};
use windows_sys::Win32::{
    Foundation::{CloseHandle, ERROR_INSUFFICIENT_BUFFER, INVALID_HANDLE_VALUE, NO_ERROR},
    NetworkManagement::IpHelper::{
        GetExtendedTcpTable, MIB_TCP6ROW_OWNER_PID, MIB_TCPROW_OWNER_PID, TCP_TABLE_OWNER_PID_ALL,
    },
    Networking::WinSock::{AF_INET, AF_INET6},
    System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
        TH32CS_SNAPPROCESS,
    },
};

#[derive(Debug, Default, Clone)]
pub struct GameState {
    pub pids: Vec<u32>,
    pub local_ports: HashSet<u16>,
}

impl GameState {
    pub fn running(&self) -> bool {
        !self.pids.is_empty()
    }
}

pub fn scan() -> GameState {
    let mut state = GameState::default();
    // SAFETY: snapshot handle is checked and closed; entry has the required size.
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot == INVALID_HANDLE_VALUE {
            return state;
        }
        let mut entry: PROCESSENTRY32W = zeroed();
        entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        let mut more = Process32FirstW(snapshot, &mut entry);
        while more != 0 {
            let end = entry
                .szExeFile
                .iter()
                .position(|c| *c == 0)
                .unwrap_or(entry.szExeFile.len());
            if String::from_utf16_lossy(&entry.szExeFile[..end]).eq_ignore_ascii_case("AION2.exe") {
                state.pids.push(entry.th32ProcessID);
            }
            more = Process32NextW(snapshot, &mut entry);
        }
        CloseHandle(snapshot);
    }
    if !state.pids.is_empty() {
        for family in [AF_INET, AF_INET6] {
            collect_ports(family as u32, &mut state);
        }
    }
    state
}

fn collect_ports(family: u32, state: &mut GameState) {
    let mut bytes = 0u32;
    // SAFETY: the initial null buffer queries the required allocation size.
    let result = unsafe {
        GetExtendedTcpTable(
            std::ptr::null_mut(),
            &mut bytes,
            0,
            family,
            TCP_TABLE_OWNER_PID_ALL,
            0,
        )
    };
    if result != ERROR_INSUFFICIENT_BUFFER {
        return;
    }
    // Tables can grow between calls. Retry with the new required size.
    for _ in 0..3 {
        let mut buffer = vec![0u32; (bytes as usize).div_ceil(4)];
        // SAFETY: buffer is DWORD-aligned and at least `bytes` long.
        let result = unsafe {
            GetExtendedTcpTable(
                buffer.as_mut_ptr().cast(),
                &mut bytes,
                0,
                family,
                TCP_TABLE_OWNER_PID_ALL,
                0,
            )
        };
        if result == ERROR_INSUFFICIENT_BUFFER {
            continue;
        }
        if result != NO_ERROR {
            return;
        }
        let Some(&count) = buffer.first() else {
            return;
        };
        let row_size = if family == AF_INET as u32 {
            size_of::<MIB_TCPROW_OWNER_PID>()
        } else {
            size_of::<MIB_TCP6ROW_OWNER_PID>()
        };
        let available = (buffer.len() * 4).saturating_sub(4) / row_size;
        for i in 0..(count as usize).min(available) {
            // SAFETY: each row is bounded by the allocation above. Both tables
            // start with a DWORD count followed by DWORD-aligned rows.
            let (pid, port) = unsafe {
                let row = buffer.as_ptr().cast::<u8>().add(4 + i * row_size);
                if family == AF_INET as u32 {
                    let row = row.cast::<MIB_TCPROW_OWNER_PID>().read_unaligned();
                    (row.dwOwningPid, row.dwLocalPort)
                } else {
                    let row = row.cast::<MIB_TCP6ROW_OWNER_PID>().read_unaligned();
                    (row.dwOwningPid, row.dwLocalPort)
                }
            };
            if state.pids.contains(&pid) {
                state.local_ports.insert(u16::from_be(port as u16));
            }
        }
        return;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn socket_tables_identify_this_process_on_ipv4_and_ipv6() {
        for address in ["127.0.0.1:0", "[::1]:0"] {
            let listener = std::net::TcpListener::bind(address).unwrap();
            let mut state = GameState {
                pids: vec![std::process::id()],
                local_ports: HashSet::new(),
            };
            let family = if listener.local_addr().unwrap().is_ipv4() {
                AF_INET
            } else {
                AF_INET6
            };
            collect_ports(family as u32, &mut state);
            assert!(
                state
                    .local_ports
                    .contains(&listener.local_addr().unwrap().port())
            );
        }
    }
    #[test]
    fn unrelated_process_ports_are_excluded() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let mut state = GameState {
            pids: vec![u32::MAX],
            local_ports: HashSet::new(),
        };
        collect_ports(AF_INET as u32, &mut state);
        assert!(
            !state
                .local_ports
                .contains(&listener.local_addr().unwrap().port())
        );
    }
}
