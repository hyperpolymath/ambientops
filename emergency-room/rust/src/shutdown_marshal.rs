// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Shutdown Marshal — graceful shutdown orchestration.
// Addresses CC-002 (unsafe shutdowns): coordinates component notification,
// evidence envelope finalisation, and ungraceful-shutdown detection on next boot.
// Ported from shutdown_marshal.v.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

const STATE_PATH: &str = "/var/lib/ambientops/shutdown-marshal/state.json";
const NOTIFY_COMPONENTS: &[&str] = &["observatory", "clinician", "session-sentinel"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShutdownReason {
    UserInitiated,
    Scheduled,
    Emergency,
    KernelPanic,
    PowerLoss,
    Unknown,
}

impl ShutdownReason {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().replace('-', "_").as_str() {
            "user_initiated"  => Self::UserInitiated,
            "scheduled"       => Self::Scheduled,
            "emergency"       => Self::Emergency,
            "kernel_panic"    => Self::KernelPanic,
            "power_loss"      => Self::PowerLoss,
            _                 => Self::Unknown,
        }
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Self::UserInitiated => "user_initiated",
            Self::Scheduled     => "scheduled",
            Self::Emergency     => "emergency",
            Self::KernelPanic   => "kernel_panic",
            Self::PowerLoss     => "power_loss",
            Self::Unknown       => "unknown",
        }
    }
}

#[derive(Serialize, Deserialize, Default)]
struct ShutdownState {
    schema_version: String,
    last_clean_shutdown: String,
    shutdown_in_progress: bool,
    shutdown_reason: String,
    notified_components: Vec<String>,
    pending_flushes: Vec<String>,
    ungraceful_count: u32,
}

#[derive(Serialize)]
pub struct ShutdownReport {
    pub schema_version: String,
    pub initiated_at: String,
    pub completed_at: String,
    pub reason: String,
    pub success: bool,
    pub notified: Vec<String>,
    pub failed_notifications: Vec<String>,
    pub ungraceful_count: u32,
}

pub fn orchestrate(
    reason_str: &str,
    grace_period_secs: u64,
    dry_run: bool,
) -> Result<ShutdownReport, Box<dyn std::error::Error>> {
    let reason = ShutdownReason::from_str(reason_str);
    let initiated_at = Utc::now().to_rfc3339();

    // Check for previous ungraceful shutdowns
    let mut state = load_state();
    if state.shutdown_in_progress {
        state.ungraceful_count += 1;
        println!(
            "\x1b[33m[WARN]\x1b[0m Previous shutdown was ungraceful ({} total)",
            state.ungraceful_count
        );
    }

    state.shutdown_in_progress = true;
    state.shutdown_reason = reason.as_str().to_string();
    if !dry_run {
        let _ = save_state(&state);
    }

    println!("\x1b[34m[SHUTDOWN]\x1b[0m Reason: {}", reason.as_str());
    println!("\x1b[34m[SHUTDOWN]\x1b[0m Grace period: {grace_period_secs}s");
    println!();

    // Notify each component
    let mut notified: Vec<String> = vec![];
    let mut failed: Vec<String> = vec![];

    for component in NOTIFY_COMPONENTS {
        if dry_run {
            println!("\x1b[36m[DRY-RUN]\x1b[0m Would notify: {component}");
            notified.push(component.to_string());
            continue;
        }

        print!("  Notifying {component}… ");
        let ok = notify_component(component, grace_period_secs);
        if ok {
            println!("\x1b[32m✓\x1b[0m");
            notified.push(component.to_string());
        } else {
            println!("\x1b[33m✗\x1b[0m (not running or timed out)");
            failed.push(component.to_string());
        }
    }

    println!();
    println!(
        "\x1b[34m[SHUTDOWN]\x1b[0m Notified {}/{} components",
        notified.len(),
        NOTIFY_COMPONENTS.len()
    );

    // Mark as clean shutdown
    let completed_at = Utc::now().to_rfc3339();
    state.shutdown_in_progress = false;
    state.last_clean_shutdown = completed_at.clone();
    state.notified_components = notified.clone();
    if !dry_run {
        let _ = save_state(&state);
    }

    Ok(ShutdownReport {
        schema_version: "1.0.0".to_string(),
        initiated_at,
        completed_at,
        reason: reason.as_str().to_string(),
        success: true,
        notified,
        failed_notifications: failed,
        ungraceful_count: state.ungraceful_count,
    })
}

/// Send SIGTERM to a component (by process name) and wait up to grace_period.
fn notify_component(name: &str, grace_period_secs: u64) -> bool {
    // Try systemctl first (systemd environments)
    let systemctl = Command::new("systemctl")
        .args(["stop", &format!("ambientops-{name}"), "--no-block"])
        .status();
    if systemctl.map(|s| s.success()).unwrap_or(false) {
        // Wait for it to stop
        std::thread::sleep(Duration::from_secs(grace_period_secs.min(5)));
        return true;
    }

    // Fallback: send SIGTERM to process by name
    #[cfg(unix)]
    {
        let kill = Command::new("pkill").args(["-TERM", name]).status();
        if kill.map(|s| s.success()).unwrap_or(false) {
            std::thread::sleep(Duration::from_secs(grace_period_secs.min(5)));
            return true;
        }
    }

    false
}

fn load_state() -> ShutdownState {
    fs::read_to_string(STATE_PATH)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_state(state: &ShutdownState) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(parent) = Path::new(STATE_PATH).parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(state)?;
    let tmp = format!("{STATE_PATH}.tmp");
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, STATE_PATH)?;
    Ok(())
}
