// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Quick backup to an external destination.
// CRIT-002: Path validation before any subprocess invocation.

use crate::incident::{Config, Incident};
use std::path::Path;
use std::process::Command;

/// Validate destination path is safe (no shell metacharacters).
fn validate_dest(path: &str) -> Result<(), String> {
    if path.is_empty() {
        return Err("empty path".to_string());
    }
    const DANGEROUS: &[char] = &[';', '|', '&', '$', '`', '(', ')', '{', '}',
                                   '[', ']', '<', '>', '\n', '\r', '*', '?', '~', '!', '#'];
    for &c in DANGEROUS {
        if path.contains(c) {
            return Err(format!("dangerous character '{c}' in path"));
        }
    }
    Ok(())
}

pub fn run(inc: &Incident, cfg: &Config) {
    let dest = match &cfg.quick_backup_dest {
        Some(d) => d.as_str(),
        None => return,
    };

    if let Err(e) = validate_dest(dest) {
        eprintln!("\x1b[31m[ERROR]\x1b[0m Invalid backup destination: {e}");
        return;
    }

    if !Path::new(dest).exists() {
        eprintln!("\x1b[31m[ERROR]\x1b[0m Backup destination does not exist: {dest}");
        eprintln!("\x1b[34m[INFO]\x1b[0m Please create the directory or mount the drive first.");
        return;
    }

    let src = inc.path.display().to_string();

    if cfg.dry_run {
        println!("\x1b[36m[DRY-RUN]\x1b[0m Would copy {src} → {dest}");
        return;
    }

    println!("\x1b[34m[INFO]\x1b[0m Copying incident bundle to {dest}…");

    // Use cp -r on Unix, xcopy on Windows — safest cross-platform approach.
    #[cfg(windows)]
    let status = Command::new("xcopy").args([&src, dest, "/E", "/I", "/Q"]).status();
    #[cfg(not(windows))]
    let status = Command::new("cp").args(["-r", &src, dest]).status();

    match status {
        Ok(s) if s.success() => {
            println!("\x1b[32m[OK]\x1b[0m Backup complete: {dest}");
        }
        Ok(s) => {
            eprintln!("\x1b[31m[ERROR]\x1b[0m Backup failed with exit code {s}");
        }
        Err(e) => {
            eprintln!("\x1b[31m[ERROR]\x1b[0m Backup command failed: {e}");
        }
    }
}
