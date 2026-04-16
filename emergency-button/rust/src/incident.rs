// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Incident bundle creation and management.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

pub const SCHEMA_VERSION: &str = "1.0.0";

pub struct Config {
    pub quick_backup_dest: Option<String>,
    pub dry_run: bool,
}

pub struct Incident {
    pub id: String,
    pub correlation_id: String,
    pub path: PathBuf,
    pub logs_path: PathBuf,
    pub created_at: String,
    pub commands: Vec<CommandLog>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CommandLog {
    pub name: String,
    pub command: String,
    pub started_at: String,
    pub ended_at: String,
    pub exit_code: i32,
    pub output_len: usize,
}

#[derive(Serialize)]
struct IncidentEnvelope {
    schema_version: String,
    id: String,
    correlation_id: String,
    created_at: String,
    hostname: String,
    username: String,
    working_dir: String,
    platform: PlatformInfo,
    trigger: TriggerInfo,
    commands: Vec<CommandLog>,
}

#[derive(Serialize)]
struct PlatformInfo {
    os: String,
    arch: String,
    kernel: String,
}

#[derive(Serialize)]
struct TriggerInfo {
    version: String,
    dry_run: bool,
}

pub fn create_bundle(cfg: &Config) -> Result<Incident, Box<dyn std::error::Error>> {
    let now = Utc::now();
    let timestamp = now.format("%Y%m%d-%H%M%S").to_string();
    // Use nanoseconds + random-ish bits to prevent ID collisions
    let ns = now.timestamp_subsec_nanos();
    let random_suffix = format!("{:04x}", (ns ^ (ns >> 16)) & 0xFFFF);
    let incident_id = format!("incident-{timestamp}-{ns:09}-{random_suffix}");
    let correlation_id = format!("corr-{:016x}", now.timestamp_nanos_opt().unwrap_or(0));

    let base_dir = std::env::current_dir()?;
    let incident_path = base_dir.join(&incident_id);
    let logs_path = incident_path.join("logs");

    if cfg.dry_run {
        println!("\x1b[36m[DRY-RUN]\x1b[0m Would create: {}", incident_path.display());
        println!("\x1b[36m[DRY-RUN]\x1b[0m Would create: {}", logs_path.display());
        println!("\x1b[36m[DRY-RUN]\x1b[0m Correlation ID: {correlation_id}");
        return Ok(Incident {
            id: incident_id,
            correlation_id,
            path: incident_path,
            logs_path,
            created_at: now.to_rfc3339(),
            commands: vec![],
        });
    }

    fs::create_dir_all(&logs_path)?;

    let inc = Incident {
        id: incident_id,
        correlation_id,
        path: incident_path,
        logs_path,
        created_at: now.to_rfc3339(),
        commands: vec![],
    };

    // Write initial incident.json
    write_envelope(&inc, cfg)?;
    Ok(inc)
}

pub fn write_envelope(inc: &Incident, cfg: &Config) -> Result<(), Box<dyn std::error::Error>> {
    if cfg.dry_run {
        return Ok(());
    }

    let hostname = hostname_string();
    let username = std::env::var("USER").or_else(|_| std::env::var("USERNAME")).unwrap_or_default();
    let working_dir = std::env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_default();

    let envelope = IncidentEnvelope {
        schema_version: SCHEMA_VERSION.to_string(),
        id: inc.id.clone(),
        correlation_id: inc.correlation_id.clone(),
        created_at: inc.created_at.clone(),
        hostname,
        username,
        working_dir,
        platform: current_platform(),
        trigger: TriggerInfo {
            version: "0.2.0".to_string(),
            dry_run: cfg.dry_run,
        },
        commands: inc.commands.clone(),
    };

    let json = serde_json::to_string_pretty(&envelope)?;
    atomic_write(&inc.path.join("incident.json"), &json)?;
    Ok(())
}

pub fn write_receipt(inc: &Incident, cfg: &Config) -> Result<(), Box<dyn std::error::Error>> {
    write_envelope(inc, cfg)
}

/// Write to temp file then rename for atomicity.
pub fn atomic_write(path: &std::path::Path, content: &str) -> Result<(), Box<dyn std::error::Error>> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, content)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

fn hostname_string() -> String {
    #[cfg(unix)]
    {
        use std::process::Command;
        Command::new("hostname")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_else(|_| "unknown".to_string())
    }
    #[cfg(windows)]
    {
        std::env::var("COMPUTERNAME").unwrap_or_else(|_| "unknown".to_string())
    }
}

fn current_platform() -> PlatformInfo {
    #[cfg(target_os = "linux")]
    let os = "linux".to_string();
    #[cfg(target_os = "macos")]
    let os = "macos".to_string();
    #[cfg(target_os = "windows")]
    let os = "windows".to_string();
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    let os = std::env::consts::OS.to_string();

    let arch = std::env::consts::ARCH.to_string();
    let kernel = kernel_version();
    PlatformInfo { os, arch, kernel }
}

fn kernel_version() -> String {
    #[cfg(unix)]
    {
        use std::process::Command;
        Command::new("uname")
            .arg("-r")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_else(|_| "unknown".to_string())
    }
    #[cfg(windows)]
    {
        "windows".to_string()
    }
}
