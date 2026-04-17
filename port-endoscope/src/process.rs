// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Process introspection and termination via procfs and signals.
//!
//! Reads /proc/<pid>/stat and /proc/<pid>/status to determine process name,
//! state (zombie, sleeping, running), and age. Provides graceful kill
//! (SIGTERM → wait → SIGKILL) for port reclamation.

use anyhow::Result;
use std::fs;
use std::time::Duration;

/// Information about a process.
#[derive(Debug, Clone)]
pub struct ProcessInfo {
    /// Process name (from /proc/<pid>/comm or /proc/<pid>/stat).
    pub name: String,
    /// Whether the process is a zombie (state Z in /proc/<pid>/stat).
    pub is_zombie: bool,
    /// Process age in seconds (since start time), if determinable.
    pub age_secs: Option<u64>,
}

/// Read process information from /proc/<pid>/.
pub fn get_process_info(pid: u32) -> ProcessInfo {
    let default = ProcessInfo {
        name: "<unknown>".to_string(),
        is_zombie: false,
        age_secs: None,
    };

    if pid == 0 {
        return ProcessInfo {
            name: "<kernel>".to_string(),
            ..default
        };
    }

    // Read process name from /proc/<pid>/comm
    let name = fs::read_to_string(format!("/proc/{}/comm", pid))
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "<dead>".to_string());

    // Read process state from /proc/<pid>/stat
    // Format: pid (name) state ...
    let is_zombie = fs::read_to_string(format!("/proc/{}/stat", pid))
        .map(|stat| {
            // Find the closing paren (process name can contain spaces/parens)
            if let Some(close_paren) = stat.rfind(')') {
                let after = &stat[close_paren + 1..];
                let fields: Vec<&str> = after.split_whitespace().collect();
                // First field after (name) is the state
                fields.first().map_or(false, |s| *s == "Z")
            } else {
                false
            }
        })
        .unwrap_or(false);

    // Read process start time for age calculation
    let age_secs = calculate_process_age(pid);

    ProcessInfo {
        name,
        is_zombie,
        age_secs,
    }
}

/// Calculate the age of a process in seconds.
///
/// Uses /proc/<pid>/stat field 22 (starttime in clock ticks since boot)
/// and /proc/uptime to compute elapsed time.
fn calculate_process_age(pid: u32) -> Option<u64> {
    // Get system uptime in seconds
    let uptime_str = fs::read_to_string("/proc/uptime").ok()?;
    let uptime_secs: f64 = uptime_str
        .split_whitespace()
        .next()?
        .parse()
        .ok()?;

    // Get process start time (field 22 in /proc/<pid>/stat, 0-indexed field 21)
    let stat_str = fs::read_to_string(format!("/proc/{}/stat", pid)).ok()?;
    let close_paren = stat_str.rfind(')')?;
    let after = &stat_str[close_paren + 1..];
    let fields: Vec<&str> = after.split_whitespace().collect();

    // Field index 19 after the closing paren = field 22 overall (starttime)
    let starttime_ticks: u64 = fields.get(19)?.parse().ok()?;

    // Clock ticks per second (usually 100 on Linux)
    let ticks_per_sec: u64 = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as u64;
    if ticks_per_sec == 0 {
        return None;
    }

    let start_secs = starttime_ticks / ticks_per_sec;
    let age = uptime_secs as u64 - start_secs;

    Some(age)
}

/// Kill a process gracefully: SIGTERM first, wait grace_secs, then SIGKILL.
///
/// If grace_secs is 0, sends SIGKILL immediately.
/// Returns Ok(()) if the process is confirmed dead.
pub fn kill_gracefully(pid: u32, grace_secs: u64) -> Result<()> {
    use nix::sys::signal::{self, Signal};
    use nix::unistd::Pid;

    let nix_pid = Pid::from_raw(pid as i32);

    if grace_secs == 0 {
        // Immediate SIGKILL
        signal::kill(nix_pid, Signal::SIGKILL)
            .map_err(|e| anyhow::anyhow!("SIGKILL failed for PID {}: {}", pid, e))?;
        wait_for_death(pid, 5)?;
        return Ok(());
    }

    // Try SIGTERM first
    match signal::kill(nix_pid, Signal::SIGTERM) {
        Ok(()) => {}
        Err(nix::errno::Errno::ESRCH) => {
            // Process already gone
            return Ok(());
        }
        Err(e) => {
            return Err(anyhow::anyhow!("SIGTERM failed for PID {}: {}", pid, e));
        }
    }

    // Wait for grace period, checking if process exits
    let poll_interval = Duration::from_millis(200);
    let deadline = std::time::Instant::now() + Duration::from_secs(grace_secs);

    while std::time::Instant::now() < deadline {
        if !is_process_alive(pid) {
            return Ok(());
        }
        std::thread::sleep(poll_interval);
    }

    // Still alive after grace period — escalate to SIGKILL
    eprintln!(
        "  PID {} did not exit after {}s SIGTERM — sending SIGKILL",
        pid, grace_secs
    );

    match signal::kill(nix_pid, Signal::SIGKILL) {
        Ok(()) => {}
        Err(nix::errno::Errno::ESRCH) => return Ok(()), // Already gone
        Err(e) => {
            return Err(anyhow::anyhow!("SIGKILL failed for PID {}: {}", pid, e));
        }
    }

    wait_for_death(pid, 5)
}

/// Check if a process is still alive by sending signal 0.
pub fn is_process_alive(pid: u32) -> bool {
    use nix::sys::signal;
    use nix::unistd::Pid;

    signal::kill(Pid::from_raw(pid as i32), None).is_ok()
}

/// Wait for a process to die, polling every 200ms.
fn wait_for_death(pid: u32, timeout_secs: u64) -> Result<()> {
    let poll = Duration::from_millis(200);
    let deadline = std::time::Instant::now() + Duration::from_secs(timeout_secs);

    while std::time::Instant::now() < deadline {
        if !is_process_alive(pid) {
            return Ok(());
        }
        std::thread::sleep(poll);
    }

    if is_process_alive(pid) {
        Err(anyhow::anyhow!(
            "PID {} still alive after {}s — may require root privileges",
            pid, timeout_secs
        ))
    } else {
        Ok(())
    }
}
