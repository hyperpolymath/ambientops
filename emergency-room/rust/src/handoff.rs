// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Handoff to specialized tools (psa, ambientops).
// CRIT-001: Path validation before any shell invocation.

use crate::incident::{atomic_write, Config, Incident, SCHEMA_VERSION};
use std::process::Command;

struct HandoffTarget {
    name: &'static str,
    command: &'static str,
}

const TARGETS: &[HandoffTarget] = &[
    HandoffTarget { name: "psa",    command: "psa"    },
    HandoffTarget { name: "ambientops", command: "ambientops" },
];

/// Validate path contains only safe chars (no shell metacharacters).
fn is_path_safe(path: &str) -> bool {
    if path.is_empty() || path.contains("..") {
        return false;
    }
    path.chars().all(|c| c.is_alphanumeric() || "-_./".contains(c))
}

pub fn run(inc: &Incident, cfg: &Config) {
    if !is_path_safe(inc.path.to_str().unwrap_or("")) {
        eprintln!("\x1b[31m[ERROR]\x1b[0m Invalid incident path (possible injection)");
        return;
    }

    let target = TARGETS.iter().find(|t| tool_exists(t.command));

    if let Some(t) = target {
        println!("\x1b[34m[HANDOFF]\x1b[0m Found {}: {}", t.name, t.name);
        println!();

        let inc_path = inc.path.display().to_string();
        let args = ["crisis", "--incident", &inc_path, "--correlation-id", &inc.correlation_id];

        if cfg.dry_run {
            println!("\x1b[36m[DRY-RUN]\x1b[0m Would execute: {} {}", t.command, args.join(" "));
            return;
        }

        log_handoff(inc, t.name, t.command, &args, cfg);

        println!("\x1b[34m[INFO]\x1b[0m Launching: {} {}", t.command, args.join(" "));
        println!();

        let status = Command::new(t.command).args(&args).status();
        if let Ok(s) = status {
            if !s.success() {
                eprintln!("\x1b[33m[WARN]\x1b[0m {} exited with {}", t.name, s);
            }
        }
    } else {
        println!("\x1b[33m[INFO]\x1b[0m No specialized tools found (psa, ambientops)");
        println!("\x1b[34m[INFO]\x1b[0m Incident bundle is ready for manual review");
        println!();
        println!("\x1b[36mSuggested next steps:\x1b[0m");
        println!("  1. Review logs in: {}", inc.logs_path.display());
        println!("  2. Install psa or ambientops for enhanced diagnostics");
        println!("  3. Share the incident bundle for analysis");
    }
}

fn tool_exists(name: &str) -> bool {
    #[cfg(windows)]
    let out = Command::new("where").arg(name).output();
    #[cfg(not(windows))]
    let out = Command::new("sh").args(["-c", &format!("command -v {name}")]).output();
    out.map(|o| o.status.success()).unwrap_or(false)
}

fn log_handoff(inc: &Incident, tool_name: &str, cmd: &str, args: &[&str], cfg: &Config) {
    if cfg.dry_run { return; }
    let content = format!(
        "schema_version: {SCHEMA_VERSION}\n\nHandoff to: {tool_name}\nCommand: {cmd} {}\n",
        args.join(" ")
    );
    let path = inc.logs_path.join("handoff.log");
    if let Err(e) = atomic_write(&path, &content) {
        eprintln!("\x1b[33m[WARN]\x1b[0m Could not write handoff log: {e}");
    }
}
