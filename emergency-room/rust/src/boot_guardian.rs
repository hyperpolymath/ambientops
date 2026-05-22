// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Boot Guardian — boot-loop detection via persistent stamp file.
// Addresses CC-002 (unsafe shutdowns) and CC-003 (PCIe link failures).
// Ported from boot_guardian.v.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

const BOOT_LOOP_THRESHOLD: usize = 5;
const BOOT_LOOP_WINDOW_SECS: i64 = 600; // 10 minutes

#[derive(Serialize, Deserialize, Default)]
pub struct BootStampFile {
    pub stamps: Vec<BootStamp>,
    pub safe_mode: bool,
    pub loop_count: u32,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct BootStamp {
    pub timestamp: String,
    pub kernel: String,
    pub epoch_seconds: i64,
    pub boot_id: String,
}

#[derive(Serialize)]
pub struct BootGuardianReport {
    pub schema_version: String,
    pub check_time: String,
    pub boot_loop_detected: bool,
    pub recent_boot_count: usize,
    pub window_seconds: i64,
    pub threshold: usize,
    pub safe_mode_recommended: bool,
    pub pcie_link_errors: Vec<PcieLinkError>,
}

#[derive(Serialize)]
pub struct PcieLinkError {
    pub device: String,
    pub message: String,
    pub severity: String,
}

pub fn record_boot(stamp_path: &str, dry_run: bool) -> Result<(), Box<dyn std::error::Error>> {
    let mut stamps = load_stamps(stamp_path);
    let current_boot_id = read_boot_id();

    // Idempotent: skip if already recorded this boot
    if !current_boot_id.is_empty() && stamps.stamps.iter().any(|s| s.boot_id == current_boot_id) {
        return Ok(());
    }

    let now = Utc::now();
    let stamp = BootStamp {
        timestamp: now.to_rfc3339(),
        kernel: kernel_version(),
        epoch_seconds: now.timestamp(),
        boot_id: current_boot_id,
    };

    if dry_run {
        println!("\x1b[36m[DRY-RUN]\x1b[0m Would record boot: {}", stamp.timestamp);
        return Ok(());
    }

    stamps.stamps.push(stamp);
    // Prune old stamps (> 24 hours) to keep the file from growing unboundedly
    let cutoff = now.timestamp() - 86400;
    stamps.stamps.retain(|s| s.epoch_seconds > cutoff);

    save_stamps(stamp_path, &stamps)
}

pub fn check_health(stamp_path: &str) -> Result<BootGuardianReport, Box<dyn std::error::Error>> {
    let stamps = load_stamps(stamp_path);
    let now = Utc::now().timestamp();
    let window_start = now - BOOT_LOOP_WINDOW_SECS;

    let recent: Vec<&BootStamp> = stamps.stamps.iter()
        .filter(|s| s.epoch_seconds >= window_start)
        .collect();

    let boot_loop_detected = recent.len() >= BOOT_LOOP_THRESHOLD;
    let pcie_errors = scan_pcie_errors();

    Ok(BootGuardianReport {
        schema_version: "1.0.0".to_string(),
        check_time: Utc::now().to_rfc3339(),
        boot_loop_detected,
        recent_boot_count: recent.len(),
        window_seconds: BOOT_LOOP_WINDOW_SECS,
        threshold: BOOT_LOOP_THRESHOLD,
        safe_mode_recommended: boot_loop_detected || !pcie_errors.is_empty(),
        pcie_link_errors: pcie_errors,
    })
}

fn load_stamps(path: &str) -> BootStampFile {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_stamps(path: &str, stamps: &BootStampFile) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(parent) = Path::new(path).parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(stamps)?;
    let tmp = format!("{path}.tmp");
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

fn read_boot_id() -> String {
    #[cfg(target_os = "linux")]
    {
        fs::read_to_string("/proc/sys/kernel/random/boot_id")
            .map(|s| s.trim().to_string())
            .unwrap_or_default()
    }
    #[cfg(not(target_os = "linux"))]
    {
        String::new()
    }
}

fn kernel_version() -> String {
    use std::process::Command;
    Command::new("uname").arg("-r").output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "unknown".to_string())
}

/// Scan dmesg for PCIe link errors (CC-003: link failures cause boot loops).
fn scan_pcie_errors() -> Vec<PcieLinkError> {
    #[cfg(not(target_os = "linux"))]
    { return vec![]; }

    #[cfg(target_os = "linux")]
    {
        use std::process::Command;
        let output = Command::new("dmesg").args(["--level=err,warn", "--notime"]).output();
        let Ok(out) = output else { return vec![]; };
        let text = String::from_utf8_lossy(&out.stdout);

        text.lines()
            .filter(|l| l.contains("PCIe") || l.contains("pcie") || l.contains("AER"))
            .map(|l| PcieLinkError {
                device: extract_pci_slot(l),
                message: l.trim().to_string(),
                severity: if l.contains("error") || l.contains("Error") { "error" } else { "warning" }.to_string(),
            })
            .collect()
    }
}

fn extract_pci_slot(line: &str) -> String {
    // Look for patterns like "0000:01:00.0" or "01:00.0"
    for word in line.split_whitespace() {
        let w = word.trim_matches(|c: char| !c.is_alphanumeric() && c != ':' && c != '.');
        let parts: Vec<&str> = w.split(':').collect();
        if parts.len() >= 2 && parts[parts.len() - 1].contains('.') {
            return w.to_string();
        }
    }
    "unknown".to_string()
}
