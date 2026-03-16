// SPDX-License-Identifier: PMPL-1.0-or-later
//! Disk and storage management tools
//!
//! Security: All user-supplied paths are validated before use in commands

use anyhow::Result;
use sysinfo::Disks;
use crate::storage::Storage;
use crate::cache::Cache;
use crate::validation::validate_safe_path;

/// Disk action types
#[derive(Debug, Clone)]
pub enum DiskAction {
    Usage,
    Large { min_size: String, path: String },
    Io,
    Duplicates { path: String },
    Health,
}

pub async fn handle(action: DiskAction, _storage: &Storage, _cache: &Cache) -> Result<()> {
    match action {
        DiskAction::Usage => show_usage().await?,
        DiskAction::Large { min_size, path } => find_large(&min_size, &path).await?,
        DiskAction::Io => show_io().await?,
        DiskAction::Duplicates { path } => find_duplicates(&path).await?,
        DiskAction::Health => show_health().await?,
    }
    Ok(())
}

async fn show_usage() -> Result<()> {
    let disks = Disks::new_with_refreshed_list();

    println!("{:<20} {:>10} {:>10} {:>10} {:>6}", "FILESYSTEM", "SIZE", "USED", "AVAIL", "USE%");
    println!("{}", "-".repeat(60));

    for disk in disks.list() {
        let total = disk.total_space();
        let avail = disk.available_space();
        let used = total - avail;
        let use_pct = if total > 0 { (used as f64 / total as f64) * 100.0 } else { 0.0 };

        println!(
            "{:<20} {:>10} {:>10} {:>10} {:>5.1}%",
            disk.mount_point().display(),
            format_size(total),
            format_size(used),
            format_size(avail),
            use_pct
        );
    }

    Ok(())
}

fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;

    if bytes >= TB {
        format!("{:.1}T", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.1}G", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1}M", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1}K", bytes as f64 / KB as f64)
    } else {
        format!("{}B", bytes)
    }
}

async fn find_large(min_size: &str, path: &str) -> Result<()> {
    // SECURITY: Validate path to prevent command injection
    let safe_path = validate_safe_path(path)
        .map_err(|e| anyhow::anyhow!("Invalid path: {}", e))?;

    let _min_bytes = parse_size(min_size)?;
    println!("Finding files larger than {} in {}...", min_size, safe_path);

    // Would use walkdir crate for recursive search
    // For now, use find command with validated path
    let output = tokio::process::Command::new("find")
        .args([safe_path, "-type", "f", "-size", &format!("+{}", min_size)])
        .output()
        .await?;

    print!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

fn parse_size(s: &str) -> Result<u64> {
    let s = s.trim().to_uppercase();
    let (num, suffix) = s.split_at(s.len() - 1);
    let num: u64 = num.parse()?;

    Ok(match suffix {
        "K" => num * 1024,
        "M" => num * 1024 * 1024,
        "G" => num * 1024 * 1024 * 1024,
        "T" => num * 1024 * 1024 * 1024 * 1024,
        _ => num,
    })
}

async fn show_io() -> Result<()> {
    println!("Disk I/O by process (requires root for some info):");
    // Would use /proc/[pid]/io for per-process I/O
    Ok(())
}

async fn find_duplicates(path: &str) -> Result<()> {
    // SECURITY: Validate path to prevent command injection
    let safe_path = validate_safe_path(path)
        .map_err(|e| anyhow::anyhow!("Invalid path: {}", e))?;

    println!("Finding duplicate files in {}...", safe_path);
    // Would hash files and group by hash
    Ok(())
}

async fn show_health() -> Result<()> {
    println!("Disk health (SMART data):");
    // Would use smartctl
    Ok(())
}
