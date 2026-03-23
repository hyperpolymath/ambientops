// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
//! # Network Ambulance — Gossamer backend
//!
//! Provides the native backend for the Network Ambulance GUI.  Registers
//! four IPC commands that the ReScript frontend dispatches via
//! `RuntimeBridge.invoke`:
//!
//! - `run_diagnostics` — run the D backend `diagnose --json`
//! - `run_repair`      — run the D backend `repair <target> --json`
//! - `check_privileges` — test whether we have root/euid 0
//! - `get_platform_info` — return the OS name string
//!
//! All commands are synchronous (`Fn(Value) -> Result<Value, String>`)
//! as required by the gossamer-rs handler API.

use gossamer_rs::App;
use serde::{Deserialize, Serialize};
use std::process::Command;

// =============================================================================
// Data types — match the JSON the D backend emits
// =============================================================================

/// Result of a full diagnostic run from the D backend.
#[derive(Debug, Serialize, Deserialize)]
struct DiagnosticResult {
    /// D backend version string.
    version: String,
    /// Tool identifier (always "network-ambulance-d").
    tool: String,
    /// DNS diagnostic findings.
    dns: serde_json::Value,
    /// Routing table diagnostic findings.
    routing: serde_json::Value,
    /// Connectivity test results.
    connectivity: serde_json::Value,
    /// Network interface status.
    interfaces: serde_json::Value,
}

/// Result of a targeted repair run from the D backend.
#[derive(Debug, Serialize, Deserialize)]
struct RepairResult {
    /// D backend version string.
    version: String,
    /// Tool identifier (always "network-ambulance-d").
    tool: String,
    /// DNS repair actions taken.
    dns_repair: serde_json::Value,
    /// Interface repair actions taken.
    interface_repair: serde_json::Value,
    /// Routing repair actions taken.
    routing_repair: serde_json::Value,
}

// =============================================================================
// Command handlers
// =============================================================================

/// Run network diagnostics by invoking the D backend binary.
///
/// Expects no payload arguments.  Returns the full DiagnosticResult as JSON.
fn handle_run_diagnostics(
    _payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let output = Command::new("./bin/network-ambulance-d")
        .args(["diagnose", "--json"])
        .output()
        .map_err(|e| format!("Failed to execute D backend: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "D backend failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let result: DiagnosticResult = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    serde_json::to_value(result).map_err(|e| e.to_string())
}

/// Run a targeted network repair by invoking the D backend binary.
///
/// Expects `payload.target` — the repair target string
/// (e.g. "dns", "interfaces", "routing", "networkmanager").
fn handle_run_repair(
    payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let target = payload["target"]
        .as_str()
        .ok_or_else(|| "missing 'target' field in payload".to_string())?;

    // Privilege check on Unix — repair needs root
    #[cfg(unix)]
    {
        // SAFETY: geteuid is a trivial POSIX syscall with no preconditions
        if unsafe { libc::geteuid() } != 0 {
            return Err("Repair operations require administrator privileges".to_string());
        }
    }

    let output = Command::new("./bin/network-ambulance-d")
        .args(["repair", target, "--json"])
        .output()
        .map_err(|e| format!("Failed to execute D backend: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "D backend repair failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let result: RepairResult = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    serde_json::to_value(result).map_err(|e| e.to_string())
}

/// Check whether the process is running with elevated (root) privileges.
///
/// Returns `true` on Unix if euid == 0.  Returns `false` on all other
/// platforms (Windows privilege detection is not yet implemented).
fn handle_check_privileges(
    _payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    #[cfg(unix)]
    {
        // SAFETY: geteuid is a trivial POSIX syscall with no preconditions
        let is_root = unsafe { libc::geteuid() } == 0;
        Ok(serde_json::json!(is_root))
    }

    #[cfg(not(unix))]
    {
        Ok(serde_json::json!(false))
    }
}

/// Return the current platform name (e.g. "linux", "macos", "windows").
///
/// Uses `std::env::consts::OS` — no payload arguments needed.
fn handle_get_platform_info(
    _payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    Ok(serde_json::json!(std::env::consts::OS))
}

// =============================================================================
// Entry point
// =============================================================================

fn main() -> Result<(), gossamer_rs::Error> {
    let mut app = App::new("Network Ambulance", 1024, 768)?;

    // Register all IPC commands — names match what RuntimeBridge.invoke dispatches
    app.command("run_diagnostics", handle_run_diagnostics);
    app.command("run_repair", handle_run_repair);
    app.command("check_privileges", handle_check_privileges);
    app.command("get_platform_info", handle_get_platform_info);

    // Navigate to the frontend dist (Vite-built ReScript output)
    app.navigate("dist/index.html")?;

    // Block on the Gossamer event loop until the window is closed
    app.run();
    Ok(())
}
