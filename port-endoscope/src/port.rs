// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Port introspection via /proc/net/{tcp,udp} and /proc/*/fd.
//!
//! Parses the kernel's network socket tables directly from procfs rather than
//! shelling out to `ss` or `lsof`.  This gives us PID ownership and socket
//! state without any external dependencies.

use anyhow::Result;
use std::collections::HashMap;
use std::fs;


/// A process holding a port.
#[derive(Debug, Clone)]
pub struct PortHolder {
    /// Process ID that owns the socket.
    pub pid: u32,
    /// Local port number.
    pub local_port: u16,
    /// Socket state (LISTEN, ESTABLISHED, TIME_WAIT, CLOSE_WAIT, etc.).
    pub socket_state: String,
    /// File descriptor number within the process (if determinable).
    pub fd: Option<u32>,
}

/// TCP socket states from /proc/net/tcp (hex state field).
fn tcp_state_name(hex: &str) -> &'static str {
    match hex {
        "01" => "ESTABLISHED",
        "02" => "SYN_SENT",
        "03" => "SYN_RECV",
        "04" => "FIN_WAIT1",
        "05" => "FIN_WAIT2",
        "06" => "TIME_WAIT",
        "07" => "CLOSE",
        "08" => "CLOSE_WAIT",
        "09" => "LAST_ACK",
        "0A" => "LISTEN",
        "0B" => "CLOSING",
        _ => "UNKNOWN",
    }
}

/// Parse a hex-encoded socket address from /proc/net/tcp.
/// Format: AABBCCDD:PORT (IPv4 in little-endian hex, port in hex).
fn parse_port_from_hex(addr: &str) -> Option<u16> {
    let parts: Vec<&str> = addr.split(':').collect();
    if parts.len() != 2 {
        return None;
    }
    u16::from_str_radix(parts[1], 16).ok()
}

/// Parse /proc/net/tcp or /proc/net/udp and return entries matching a port.
fn parse_proc_net(path: &str, target_port: Option<u16>) -> Result<Vec<(u16, String, u64)>> {
    let content = fs::read_to_string(path)?;
    let mut results = Vec::new();

    for line in content.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 10 {
            continue;
        }

        let local_addr = fields[1];
        let state_hex = fields[3];
        let inode_str = fields[9];

        let local_port = match parse_port_from_hex(local_addr) {
            Some(p) => p,
            None => continue,
        };

        if let Some(target) = target_port {
            if local_port != target {
                continue;
            }
        }

        let state = tcp_state_name(state_hex).to_string();
        let inode: u64 = inode_str.parse().unwrap_or(0);

        if inode == 0 {
            continue; // Skip entries with no inode (kernel sockets)
        }

        results.push((local_port, state, inode));
    }

    Ok(results)
}

/// Build a mapping from socket inode → (PID, FD) by scanning /proc/*/fd/.
fn build_inode_to_pid_map() -> HashMap<u64, (u32, u32)> {
    let mut map = HashMap::new();

    let proc_dir = match fs::read_dir("/proc") {
        Ok(d) => d,
        Err(_) => return map,
    };

    for entry in proc_dir.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();

        // Only numeric directories (PIDs)
        let pid: u32 = match name_str.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };

        let fd_dir = format!("/proc/{}/fd", pid);
        let fd_entries = match fs::read_dir(&fd_dir) {
            Ok(d) => d,
            Err(_) => continue, // Permission denied or process gone
        };

        for fd_entry in fd_entries.flatten() {
            let fd_name = fd_entry.file_name();
            let fd_num: u32 = match fd_name.to_string_lossy().parse() {
                Ok(n) => n,
                Err(_) => continue,
            };

            let link_path = format!("/proc/{}/fd/{}", pid, fd_num);
            let link_target = match fs::read_link(&link_path) {
                Ok(t) => t,
                Err(_) => continue,
            };

            let target_str = link_target.to_string_lossy();

            // Socket links look like: socket:[12345]
            if let Some(inode_str) = target_str
                .strip_prefix("socket:[")
                .and_then(|s| s.strip_suffix(']'))
            {
                if let Ok(inode) = inode_str.parse::<u64>() {
                    map.insert(inode, (pid, fd_num));
                }
            }
        }
    }

    map
}

/// Find all processes holding a specific port.
pub fn find_port_holders(port: u16, proto: &str) -> Result<Vec<PortHolder>> {
    let proc_path = match proto {
        "udp" => "/proc/net/udp",
        _ => "/proc/net/tcp",
    };

    let socket_entries = parse_proc_net(proc_path, Some(port))?;

    if socket_entries.is_empty() {
        return Ok(Vec::new());
    }

    // Build the inode → PID map
    let inode_map = build_inode_to_pid_map();

    let mut holders = Vec::new();
    for (local_port, state, inode) in socket_entries {
        if let Some(&(pid, fd)) = inode_map.get(&inode) {
            holders.push(PortHolder {
                pid,
                local_port,
                socket_state: state,
                fd: Some(fd),
            });
        } else {
            // Socket exists but no process found (maybe kernel-owned or permission denied)
            holders.push(PortHolder {
                pid: 0,
                local_port,
                socket_state: state,
                fd: None,
            });
        }
    }

    Ok(holders)
}

/// Find all listening TCP ports with their holders.
pub fn find_all_listening() -> Result<Vec<PortHolder>> {
    let tcp_entries = parse_proc_net("/proc/net/tcp", None)?;
    let inode_map = build_inode_to_pid_map();

    let mut holders = Vec::new();
    for (local_port, state, inode) in tcp_entries {
        // Include LISTEN, TIME_WAIT, CLOSE_WAIT — anything potentially stuck
        let (pid, fd) = inode_map
            .get(&inode)
            .copied()
            .unwrap_or((0, 0));

        holders.push(PortHolder {
            pid,
            local_port,
            socket_state: state,
            fd: if pid > 0 { Some(fd) } else { None },
        });
    }

    // Sort by port number
    holders.sort_by_key(|h| h.local_port);

    // Deduplicate by (port, pid) — keep first occurrence
    let mut seen = HashMap::new();
    holders.retain(|h| {
        let key = (h.local_port, h.pid);
        if seen.contains_key(&key) {
            false
        } else {
            seen.insert(key, true);
            true
        }
    });

    Ok(holders)
}

