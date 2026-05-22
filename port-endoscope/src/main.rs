// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! # port-endoscope
//!
//! Automatic port recovery tool.  Detects stuck, orphaned, or zombie processes
//! holding TCP/UDP ports and reclaims them — either on demand or as a background
//! watcher.
//!
//! ## Problem
//!
//! When you close a dev server (deno, node, python, etc.), the port often stays
//! locked: TIME_WAIT state, zombie process, or a child that didn't get SIGTERM.
//! Restarting the server fails with "address already in use".  Every developer
//! hits this; no tool solves it automatically.
//!
//! ## Solution
//!
//! port-endoscope provides three modes:
//!
//! - **check**: show what holds a port (PID, process name, state, age)
//! - **free**: kill the holder and reclaim the port
//! - **watch**: continuously monitor a port and auto-reclaim when the expected
//!   process dies but the port stays locked
//!
//! ## Usage
//!
//! ```bash
//! port-endoscope check 6860              # Who holds port 6860?
//! port-endoscope free 6860               # Kill it and reclaim
//! port-endoscope free 6860 --grace 5     # SIGTERM, wait 5s, then SIGKILL
//! port-endoscope watch 6860 --for deno   # Auto-reclaim when deno dies
//! port-endoscope status                  # Show all ports with stuck holders
//! ```

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::collections::HashMap;

mod port;
mod process;

/// Automatic port recovery tool — never suffer "address already in use" again
#[derive(Parser)]
#[command(name = "port-endoscope", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Show what process holds a port
    Check {
        /// Port number to inspect
        port: u16,
        /// Protocol: tcp (default) or udp
        #[arg(long, default_value = "tcp")]
        proto: String,
    },

    /// Kill the process holding a port and reclaim it
    Free {
        /// Port number to free
        port: u16,
        /// Seconds to wait between SIGTERM and SIGKILL (0 = immediate SIGKILL)
        #[arg(long, default_value = "3")]
        grace: u64,
        /// Protocol: tcp (default) or udp
        #[arg(long, default_value = "tcp")]
        proto: String,
        /// Don't actually kill — just show what would happen
        #[arg(long)]
        dry_run: bool,
    },

    /// Watch a port and auto-reclaim when the expected process dies
    Watch {
        /// Port number to watch
        port: u16,
        /// Only allow this process name on the port (kill anything else)
        #[arg(long, value_name = "PROCESS")]
        allow: Option<String>,
        /// Poll interval in seconds
        #[arg(long, default_value = "2")]
        interval: u64,
        /// Grace period before SIGKILL (seconds)
        #[arg(long, default_value = "3")]
        grace: u64,
    },

    /// Show all listening ports with process info and detect stuck holders
    Status {
        /// Only show ports that appear stuck (TIME_WAIT, zombie, or no listener)
        #[arg(long)]
        stuck: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Check { port, proto } => cmd_check(port, &proto),
        Command::Free { port, grace, proto, dry_run } => cmd_free(port, grace, &proto, dry_run),
        Command::Watch { port, allow, interval, grace } => cmd_watch(port, allow, interval, grace),
        Command::Status { stuck } => cmd_status(stuck),
    }
}

/// Show what process holds a port.
fn cmd_check(port: u16, proto: &str) -> Result<()> {
    let holders = port::find_port_holders(port, proto)
        .context("Failed to query port holders")?;

    if holders.is_empty() {
        println!("Port {}/{} is free — no process holds it.", port, proto);
        return Ok(());
    }

    println!("Port {}/{}:", port, proto);
    for h in &holders {
        let proc_info = process::get_process_info(h.pid);
        let zombie_marker = if proc_info.is_zombie { " [ZOMBIE]" } else { "" };
        let age_str = match proc_info.age_secs {
            Some(age) => format!(" (running {}s)", age),
            None => String::new(),
        };

        println!(
            "  PID {:<8} {:<20} state={:<12} fd={}{}{} ",
            h.pid,
            proc_info.name,
            h.socket_state,
            h.fd.map_or("-".to_string(), |fd| fd.to_string()),
            age_str,
            zombie_marker,
        );
    }

    Ok(())
}

/// Kill the process holding a port and reclaim it.
fn cmd_free(port: u16, grace_secs: u64, proto: &str, dry_run: bool) -> Result<()> {
    let holders = port::find_port_holders(port, proto)
        .context("Failed to query port holders")?;

    if holders.is_empty() {
        println!("Port {}/{} is already free.", port, proto);
        return Ok(());
    }

    // Deduplicate by PID (a process may hold multiple FDs on the same port)
    let mut seen_pids: HashMap<u32, bool> = HashMap::new();

    for h in &holders {
        if seen_pids.contains_key(&h.pid) {
            continue;
        }
        seen_pids.insert(h.pid, true);

        let proc_info = process::get_process_info(h.pid);

        if dry_run {
            println!(
                "[dry-run] Would kill PID {} ({}) holding port {}/{}",
                h.pid, proc_info.name, port, proto
            );
            continue;
        }

        println!(
            "Freeing port {}/{}: killing PID {} ({})...",
            port, proto, h.pid, proc_info.name
        );

        match process::kill_gracefully(h.pid, grace_secs) {
            Ok(()) => println!("  PID {} terminated.", h.pid),
            Err(e) => eprintln!("  Failed to kill PID {}: {}", h.pid, e),
        }
    }

    // Verify the port is now free
    if !dry_run {
        std::thread::sleep(std::time::Duration::from_millis(500));
        let remaining = port::find_port_holders(port, proto).unwrap_or_default();
        if remaining.is_empty() {
            println!("Port {}/{} is now free.", port, proto);
        } else {
            eprintln!(
                "Warning: port {}/{} still has {} holder(s) — may be in TIME_WAIT.",
                port, proto, remaining.len()
            );
        }
    }

    Ok(())
}

/// Watch a port and auto-reclaim when the expected process dies.
fn cmd_watch(port: u16, allowed_process: Option<String>, interval_secs: u64, grace: u64) -> Result<()> {
    println!(
        "Watching port {} (poll every {}s, grace {}s{})",
        port,
        interval_secs,
        grace,
        allowed_process
            .as_ref()
            .map_or(String::new(), |p| format!(", allow: {}", p)),
    );

    let interval = std::time::Duration::from_secs(interval_secs);

    loop {
        let holders = port::find_port_holders(port, "tcp").unwrap_or_default();

        for h in &holders {
            let info = process::get_process_info(h.pid);

            // Check if this holder is a zombie or TIME_WAIT orphan
            let is_zombie = info.is_zombie;
            let is_time_wait = h.socket_state == "TIME-WAIT" || h.socket_state == "TIME_WAIT";
            let is_wrong_process = allowed_process.as_ref().map_or(false, |allowed| {
                !info.name.contains(allowed.as_str())
            });

            if is_zombie || is_time_wait || is_wrong_process {
                let reason = if is_zombie {
                    "zombie process"
                } else if is_time_wait {
                    "TIME_WAIT orphan"
                } else {
                    "unauthorized process"
                };

                eprintln!(
                    "[port-endoscope] Port {} held by PID {} ({}) — {} — reclaiming...",
                    port, h.pid, info.name, reason
                );

                if !is_time_wait {
                    // TIME_WAIT sockets don't have a killable process
                    match process::kill_gracefully(h.pid, grace) {
                        Ok(()) => eprintln!("[port-endoscope] PID {} terminated.", h.pid),
                        Err(e) => eprintln!("[port-endoscope] Failed to kill PID {}: {}", h.pid, e),
                    }
                } else {
                    eprintln!(
                        "[port-endoscope] TIME_WAIT on port {} — will clear in ~60s (kernel handles this).",
                        port
                    );
                }
            }
        }

        std::thread::sleep(interval);
    }
}

/// Show all listening ports with process info.
fn cmd_status(stuck_only: bool) -> Result<()> {
    let all_ports = port::find_all_listening()
        .context("Failed to enumerate listening ports")?;

    if all_ports.is_empty() {
        println!("No listening ports found.");
        return Ok(());
    }

    println!(
        "{:<8} {:<8} {:<20} {:<12} {:<10} {}",
        "PORT", "PID", "PROCESS", "STATE", "AGE", "FLAGS"
    );
    println!("{}", "-".repeat(72));

    for h in &all_ports {
        let info = process::get_process_info(h.pid);
        let age_str = info.age_secs.map_or("-".to_string(), |a| format!("{}s", a));

        let mut flags = Vec::new();
        if info.is_zombie {
            flags.push("ZOMBIE");
        }
        if h.socket_state == "TIME-WAIT" || h.socket_state == "TIME_WAIT" {
            flags.push("TIME_WAIT");
        }

        let is_stuck = info.is_zombie
            || h.socket_state == "TIME-WAIT"
            || h.socket_state == "TIME_WAIT";

        if stuck_only && !is_stuck {
            continue;
        }

        println!(
            "{:<8} {:<8} {:<20} {:<12} {:<10} {}",
            h.local_port,
            h.pid,
            info.name,
            h.socket_state,
            age_str,
            flags.join(", "),
        );
    }

    Ok(())
}
