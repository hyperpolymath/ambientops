// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Safe diagnostic capture with PII redaction.
// Ported from capture.v — same redaction rules, same capture modules.

use crate::incident::{atomic_write, CommandLog, Config, Incident};
use chrono::Utc;
use std::process::Command;

struct CaptureModule {
    name: &'static str,
    display_name: &'static str,
    commands: &'static [&'static str],
}

// ── PII redaction ────────────────────────────────────────────────────────────

const SENSITIVE_KEYS: &[&str] = &[
    "password", "passwd", "pwd", "secret", "token",
    "api_key", "api-key", "apikey",
    "auth_token", "auth-token", "authtoken",
    "access_token", "access-token", "accesstoken",
    "private_key", "private-key", "privatekey",
    "aws_secret", "aws-secret",
    "bearer",
];

const SENSITIVE_PREFIXES: &[&str] = &[
    "akia", "abia", "acca", "asia",                 // AWS
    "ghp_", "gho_", "ghu_", "ghs_", "ghr_",         // GitHub
];

pub fn redact_pii(content: &str) -> String {
    content.lines().map(redact_line).collect::<Vec<_>>().join("\n")
}

fn redact_line(line: &str) -> String {
    let lower = line.to_lowercase();
    let mut result = line.to_string();

    // Key=value / key: value patterns
    for key in SENSITIVE_KEYS {
        if lower.contains(key) {
            result = redact_after_sep(&result, key, '=');
            result = redact_after_sep(&result, key, ':');
        }
    }

    // Token prefix patterns
    for prefix in SENSITIVE_PREFIXES {
        if lower.contains(prefix) {
            result = redact_token(&result, prefix);
        }
    }

    // Private key block
    let lower_r = result.to_lowercase();
    if lower_r.contains("-----begin") && lower_r.contains("private key") {
        return "[REDACTED PRIVATE KEY BLOCK]".to_string();
    }

    result = redact_ssn(&result);
    result = redact_email(&result);
    result
}

fn redact_after_sep(line: &str, key: &str, sep: char) -> String {
    let lower = line.to_lowercase();
    let Some(key_pos) = lower.find(key) else { return line.to_string() };
    let rest = &line[key_pos + key.len()..];
    let Some(sep_pos) = rest.find(sep) else { return line.to_string() };
    let val_start_raw = key_pos + key.len() + sep_pos + 1;
    if val_start_raw >= line.len() { return line.to_string(); }

    let after_sep = &line[val_start_raw..];
    let start_offset = after_sep.len() - after_sep.trim_start().len();
    let val_start = val_start_raw + start_offset;
    if val_start >= line.len() { return line.to_string(); }

    let val_slice = &line[val_start..];
    let end = val_slice.find(|c: char| c.is_whitespace()).unwrap_or(val_slice.len());
    if end == 0 { return line.to_string(); }

    format!("{}{}{}", &line[..val_start], "[REDACTED]", &line[val_start + end..])
}

fn redact_token(line: &str, prefix: &str) -> String {
    let lower = line.to_lowercase();
    let Some(pos) = lower.find(prefix) else { return line.to_string() };
    let after = &line[pos + prefix.len()..];
    let end = after
        .find(|c: char| !(c.is_alphanumeric() || c == '_' || c == '-'))
        .unwrap_or(after.len());
    if end == 0 { return line.to_string(); }
    format!("{}{}{}", &line[..pos], "[REDACTED]", &line[pos + prefix.len() + end..])
}

fn redact_ssn(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut result = String::with_capacity(line.len());
    let mut i = 0;
    while i < bytes.len() {
        if i + 10 < bytes.len()
            && bytes[i].is_ascii_digit()
            && bytes[i + 1].is_ascii_digit()
            && bytes[i + 2].is_ascii_digit()
            && bytes[i + 3] == b'-'
            && bytes[i + 4].is_ascii_digit()
            && bytes[i + 5].is_ascii_digit()
            && bytes[i + 6] == b'-'
            && bytes[i + 7].is_ascii_digit()
            && bytes[i + 8].is_ascii_digit()
            && bytes[i + 9].is_ascii_digit()
            && bytes[i + 10].is_ascii_digit()
        {
            result.push_str("[REDACTED-SSN]");
            i += 11;
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }
    result
}

fn redact_email(line: &str) -> String {
    let Some(at) = line.find('@') else { return line.to_string() };
    // Find start of local part
    let local_start = line[..at]
        .rfind(|c: char| !(c.is_alphanumeric() || "._%+-".contains(c)))
        .map(|p| p + 1)
        .unwrap_or_else(|| 0);
    // Find end of domain
    let domain = &line[at + 1..];
    let domain_end = domain
        .find(|c: char| !(c.is_alphanumeric() || ".-".contains(c)))
        .unwrap_or(domain.len());
    let has_dot = domain[..domain_end].contains('.');
    if has_dot && domain_end > 2 && at > local_start {
        format!(
            "{}[REDACTED-EMAIL]{}",
            &line[..local_start],
            &line[at + 1 + domain_end..]
        )
    } else {
        line.to_string()
    }
}

// ── Capture modules ──────────────────────────────────────────────────────────

#[cfg(target_os = "linux")]
const MODULES: &[CaptureModule] = &[
    CaptureModule {
        name: "os_version",
        display_name: "OS Version",
        commands: &["cat /etc/os-release", "uname -a"],
    },
    CaptureModule {
        name: "uptime",
        display_name: "System Uptime",
        commands: &["uptime", "cat /proc/uptime"],
    },
    CaptureModule {
        name: "disk_free",
        display_name: "Disk Space",
        commands: &["df -h", "df -i"],
    },
    CaptureModule {
        name: "memory",
        display_name: "Memory Status",
        commands: &["free -h"],
    },
    CaptureModule {
        name: "network_summary",
        display_name: "Network Summary",
        commands: &["ip addr show", "ip route show"],
    },
    CaptureModule {
        name: "process_summary",
        display_name: "Process Summary",
        commands: &["ps aux --sort=-%mem", "ps aux --sort=-%cpu"],
    },
];

#[cfg(target_os = "macos")]
const MODULES: &[CaptureModule] = &[
    CaptureModule { name: "os_version",       display_name: "OS Version",       commands: &["sw_vers", "uname -a"] },
    CaptureModule { name: "uptime",           display_name: "System Uptime",    commands: &["uptime"] },
    CaptureModule { name: "disk_free",        display_name: "Disk Space",       commands: &["df -h"] },
    CaptureModule { name: "memory",           display_name: "Memory Status",    commands: &["vm_stat"] },
    CaptureModule { name: "network_summary",  display_name: "Network Summary",  commands: &["ifconfig", "netstat -rn"] },
    CaptureModule { name: "process_summary",  display_name: "Process Summary",  commands: &["ps aux"] },
];

#[cfg(target_os = "windows")]
const MODULES: &[CaptureModule] = &[
    CaptureModule { name: "os_version",       display_name: "OS Version",       commands: &["ver"] },
    CaptureModule { name: "disk_free",        display_name: "Disk Space",       commands: &["wmic logicaldisk get size,freespace,caption"] },
    CaptureModule { name: "memory",           display_name: "Memory Status",    commands: &["systeminfo | findstr Memory"] },
    CaptureModule { name: "network_summary",  display_name: "Network Summary",  commands: &["ipconfig /all"] },
    CaptureModule { name: "process_summary",  display_name: "Process Summary",  commands: &["tasklist /V"] },
];

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
const MODULES: &[CaptureModule] = &[
    CaptureModule { name: "os_version", display_name: "OS Version", commands: &["uname -a"] },
];

pub fn run_all(inc: &mut Incident, cfg: &Config) {
    for module in MODULES {
        let ok = run_module(module, inc, cfg);
        if ok {
            println!("  \x1b[32m✓\x1b[0m {}", module.display_name);
        } else {
            println!("  \x1b[33m○\x1b[0m {} (skipped)", module.display_name);
        }

        let now = Utc::now().to_rfc3339();
        inc.commands.push(CommandLog {
            name: module.name.to_string(),
            command: module.commands.join(" | "),
            started_at: now.clone(),
            ended_at: now,
            exit_code: if ok { 0 } else { 1 },
            output_len: 0,
        });
    }

    // Update receipt with command log
    let _ = crate::incident::write_envelope(inc, cfg);
}

fn run_module(module: &CaptureModule, inc: &Incident, cfg: &Config) -> bool {
    let mut parts: Vec<String> = Vec::new();
    let mut any_ok = false;

    for &cmd in module.commands {
        if cfg.dry_run {
            parts.push(format!("[DRY-RUN] Would execute: {cmd}"));
            any_ok = true;
            continue;
        }

        // Split command into argv to avoid shell injection
        let argv: Vec<&str> = cmd.split_whitespace().collect();
        if argv.is_empty() { continue; }
        let output = Command::new(argv[0]).args(&argv[1..]).output();
        if let Ok(out) = output {
            if out.status.success() {
                parts.push(format!("=== {cmd} ==="));
                parts.push(String::from_utf8_lossy(&out.stdout).into_owned());
                parts.push(String::new());
                any_ok = true;
            }
        }
    }

    if !any_ok || cfg.dry_run { return any_ok; }

    let raw = parts.join("\n");
    let redacted = redact_pii(&raw);
    let log_file = inc.logs_path.join(format!("{}.log", module.name));

    if let Err(e) = atomic_write(&log_file, &redacted) {
        eprintln!("\x1b[33m[WARN]\x1b[0m capture {}: {e}", module.name);
        return false;
    }
    true
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_api_key() {
        let line = "API_KEY=supersecretvalue123";
        let out = redact_line(line);
        assert!(out.contains("[REDACTED]"), "expected redaction in: {out}");
        assert!(!out.contains("supersecretvalue"), "value should be gone: {out}");
    }

    #[test]
    fn redacts_github_token() {
        let line = "token: ghp_ABCDEF1234567890";
        let out = redact_line(line);
        assert!(out.contains("[REDACTED]"), "expected redaction: {out}");
    }

    #[test]
    fn redacts_ssn() {
        let line = "SSN: 123-45-6789 on file";
        let out = redact_ssn(line);
        assert!(out.contains("[REDACTED-SSN]"), "expected SSN redaction: {out}");
    }

    #[test]
    fn redacts_email() {
        let line = "contact: user@example.com please";
        let out = redact_email(line);
        assert!(out.contains("[REDACTED-EMAIL]"), "expected email redaction: {out}");
    }

    #[test]
    fn innocent_text_unchanged() {
        let line = "uptime: 3 days, 4 hours";
        assert_eq!(redact_line(line), line);
    }
}
