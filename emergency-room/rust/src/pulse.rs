// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// AmbientOps Pulse — low-overhead watcher for memory pressure + systemd-oomd kills.
// This module is intentionally non-destructive: it only observes and notifies.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::Duration;

const WARN_MEM_PCT: u8 = 25;
const CRITICAL_MEM_PCT: u8 = 15;
const WARN_SWAP_PCT: u8 = 80;
const CRITICAL_SWAP_PCT: u8 = 95;

const OOM_NOTIFY_ID: &str = "82101";
const MEM_NOTIFY_ID: &str = "82102";

#[derive(Clone)]
pub struct Config {
    pub poll_seconds: u64,
    pub lookback_seconds: i64,
    pub notify_cooldown_seconds: i64,
    pub state_path: String,
    pub once: bool,
    pub dry_run: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct WatchState {
    last_scan_epoch: i64,
    last_oom_signature: String,
    last_oom_notify_epoch: i64,
    last_mem_notify_epoch: i64,
    last_mem_level: String,
}

#[derive(Debug, Clone)]
struct OomKillEvent {
    timestamp: String,
    target_path: String,
    target_hint: String,
    signature: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MemoryLevel {
    Normal,
    Warning,
    Critical,
}

impl MemoryLevel {
    fn as_str(self) -> &'static str {
        match self {
            MemoryLevel::Normal => "normal",
            MemoryLevel::Warning => "warning",
            MemoryLevel::Critical => "critical",
        }
    }

    fn from_str(s: &str) -> Self {
        match s {
            "warning" => MemoryLevel::Warning,
            "critical" => MemoryLevel::Critical,
            _ => MemoryLevel::Normal,
        }
    }
}

#[derive(Debug, Clone)]
struct MemorySnapshot {
    available_mb: u64,
    available_pct: u8,
    swap_used_pct: u8,
}

pub fn run(cfg: Config) -> Result<(), Box<dyn std::error::Error>> {
    let mut state = load_state(&cfg.state_path);
    if state.last_scan_epoch == 0 {
        state.last_scan_epoch = Utc::now().timestamp() - cfg.lookback_seconds.max(30);
    }
    state.last_mem_level = normalize_level(&state.last_mem_level).to_string();

    log_line(&format!(
        "ambientops-pulse started (poll={}s, lookback={}s, cooldown={}s, state={})",
        cfg.poll_seconds, cfg.lookback_seconds, cfg.notify_cooldown_seconds, cfg.state_path
    ));

    loop {
        let now_epoch = Utc::now().timestamp();
        let since_epoch = state
            .last_scan_epoch
            .max(now_epoch - cfg.lookback_seconds.max(30))
            .saturating_sub(2);

        match read_oom_kills_since(since_epoch) {
            Ok(events) => {
                handle_oom_events(&cfg, &mut state, now_epoch, &events);
            }
            Err(e) => {
                log_line(&format!("warn: unable to read oom journal events: {e}"));
            }
        }

        match read_memory_snapshot() {
            Ok(snapshot) => {
                handle_memory_pressure(&cfg, &mut state, now_epoch, &snapshot);
            }
            Err(e) => {
                log_line(&format!("warn: unable to read memory snapshot: {e}"));
            }
        }

        state.last_scan_epoch = now_epoch;
        let _ = save_state(&cfg.state_path, &state);

        if cfg.once {
            break;
        }
        thread::sleep(Duration::from_secs(cfg.poll_seconds.max(3)));
    }

    Ok(())
}

fn handle_oom_events(cfg: &Config, state: &mut WatchState, now_epoch: i64, events: &[OomKillEvent]) {
    let Some(event) = events
        .iter()
        .rev()
        .find(|e| e.signature != state.last_oom_signature) else {
        return;
    };

    state.last_oom_signature = event.signature.clone();

    let cooldown_ok = now_epoch - state.last_oom_notify_epoch >= cfg.notify_cooldown_seconds;
    if !cooldown_ok {
        log_line(&format!(
            "oom event observed (suppressed by cooldown): {} {}",
            event.timestamp, event.target_hint
        ));
        return;
    }

    let title = "Memory Shortage Avoided";
    let body = format!(
        "systemd-oomd terminated {} due to sustained memory pressure.\nInspect with: journalctl --since \"10 min ago\" -u systemd-oomd --no-pager",
        event.target_hint
    );

    if send_notification(
        cfg,
        OOM_NOTIFY_ID,
        "critical",
        "dialog-warning",
        title,
        &body,
    ) {
        state.last_oom_notify_epoch = now_epoch;
    }

    log_line(&format!(
        "oom kill event: {} target={} ({})",
        event.timestamp, event.target_hint, event.target_path
    ));
}

fn handle_memory_pressure(cfg: &Config, state: &mut WatchState, now_epoch: i64, snapshot: &MemorySnapshot) {
    let level = classify_memory_level(snapshot);
    let previous = MemoryLevel::from_str(&state.last_mem_level);
    state.last_mem_level = level.as_str().to_string();

    let changed = level != previous;
    let cooldown_ok = now_epoch - state.last_mem_notify_epoch >= cfg.notify_cooldown_seconds;
    if !changed && !cooldown_ok {
        return;
    }

    match level {
        MemoryLevel::Normal => {
            if previous != MemoryLevel::Normal {
                let title = "Memory Recovered";
                let body = format!(
                    "Memory pressure is back to normal.\nAvailable: {}MB ({}%), swap used: {}%.",
                    snapshot.available_mb, snapshot.available_pct, snapshot.swap_used_pct
                );
                if send_notification(cfg, MEM_NOTIFY_ID, "low", "dialog-information", title, &body) {
                    state.last_mem_notify_epoch = now_epoch;
                }
            }
        }
        MemoryLevel::Warning | MemoryLevel::Critical => {
            let top = top_process_summary().unwrap_or_else(|| "Top process unavailable.".to_string());
            let title = if level == MemoryLevel::Critical {
                "Memory Pressure Critical"
            } else {
                "Memory Pressure Warning"
            };
            let body = format!(
                "Available: {}MB ({}%), swap used: {}%.\n{}\nConsider closing heavy apps/tabs.",
                snapshot.available_mb, snapshot.available_pct, snapshot.swap_used_pct, top
            );
            let urgency = if level == MemoryLevel::Critical {
                "critical"
            } else {
                "normal"
            };
            let icon = if level == MemoryLevel::Critical {
                "dialog-error"
            } else {
                "dialog-warning"
            };
            if send_notification(cfg, MEM_NOTIFY_ID, urgency, icon, title, &body) {
                state.last_mem_notify_epoch = now_epoch;
            }
            log_line(&format!(
                "memory {}: available={}MB ({}%), swap={}%",
                level.as_str(),
                snapshot.available_mb,
                snapshot.available_pct,
                snapshot.swap_used_pct
            ));
        }
    }
}

fn classify_memory_level(snapshot: &MemorySnapshot) -> MemoryLevel {
    if snapshot.available_pct <= CRITICAL_MEM_PCT || snapshot.swap_used_pct >= CRITICAL_SWAP_PCT {
        MemoryLevel::Critical
    } else if snapshot.available_pct <= WARN_MEM_PCT || snapshot.swap_used_pct >= WARN_SWAP_PCT {
        MemoryLevel::Warning
    } else {
        MemoryLevel::Normal
    }
}

fn read_memory_snapshot() -> Result<MemorySnapshot, Box<dyn std::error::Error>> {
    let meminfo = fs::read_to_string("/proc/meminfo")?;
    let mut mem_total_kb: u64 = 0;
    let mut mem_avail_kb: u64 = 0;
    let mut swap_total_kb: u64 = 0;
    let mut swap_free_kb: u64 = 0;

    for line in meminfo.lines() {
        if let Some(v) = parse_meminfo_line(line, "MemTotal:") {
            mem_total_kb = v;
        } else if let Some(v) = parse_meminfo_line(line, "MemAvailable:") {
            mem_avail_kb = v;
        } else if let Some(v) = parse_meminfo_line(line, "SwapTotal:") {
            swap_total_kb = v;
        } else if let Some(v) = parse_meminfo_line(line, "SwapFree:") {
            swap_free_kb = v;
        }
    }

    if mem_total_kb == 0 {
        return Err("MemTotal was zero".into());
    }

    let available_pct = ((mem_avail_kb.saturating_mul(100)) / mem_total_kb).min(100) as u8;
    let swap_used_pct = if swap_total_kb == 0 {
        0
    } else {
        (((swap_total_kb.saturating_sub(swap_free_kb)).saturating_mul(100)) / swap_total_kb).min(100) as u8
    };

    Ok(MemorySnapshot {
        available_mb: mem_avail_kb / 1024,
        available_pct,
        swap_used_pct,
    })
}

fn parse_meminfo_line(line: &str, key: &str) -> Option<u64> {
    if !line.starts_with(key) {
        return None;
    }
    line.split_whitespace().nth(1)?.parse::<u64>().ok()
}

fn read_oom_kills_since(since_epoch: i64) -> Result<Vec<OomKillEvent>, Box<dyn std::error::Error>> {
    let since = format!("@{since_epoch}");
    let args = [
        "--no-pager",
        "--output=short-iso",
        "--since",
        &since,
        "-u",
        "systemd-oomd.service",
    ];

    let out = Command::new("journalctl").args(args).output()?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr).to_string();
        return Err(format!("journalctl failed: {}", err.trim()).into());
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    Ok(parse_oom_events(&stdout))
}

fn parse_oom_events(journal_output: &str) -> Vec<OomKillEvent> {
    let mut events = Vec::new();
    for line in journal_output.lines() {
        let Some(event) = parse_oom_event_line(line) else {
            continue;
        };
        events.push(event);
    }
    events
}

fn parse_oom_event_line(line: &str) -> Option<OomKillEvent> {
    let marker = "Killed ";
    let reason = " due to memory pressure";
    let start = line.find(marker)?;
    let rest = &line[start + marker.len()..];
    let end = rest.find(reason)?;
    let target = rest[..end].trim();
    if target.is_empty() {
        return None;
    }

    let timestamp = line.split_whitespace().next().unwrap_or("unknown").to_string();
    let target_hint = cgroup_hint(target);
    let signature = format!("{timestamp}|{target}");

    Some(OomKillEvent {
        timestamp,
        target_path: target.to_string(),
        target_hint,
        signature,
    })
}

fn cgroup_hint(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    if let Some(last) = trimmed.rsplit('/').next() {
        if !last.is_empty() {
            return last.to_string();
        }
    }
    trimmed.to_string()
}

fn top_process_summary() -> Option<String> {
    let out = Command::new("ps")
        .args(["-eo", "pid,rss,comm", "--sort=-rss", "--no-headers"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let pid = parts.next()?;
        let rss_kb = parts.next()?.parse::<u64>().ok()?;
        let comm = parts.next()?;
        if rss_kb < 1024 || is_noise_process(comm) {
            continue;
        }
        let rss_mb = rss_kb / 1024;
        return Some(format!("Top process: {comm} (PID {pid}, {rss_mb}MB)."));
    }
    None
}

fn is_noise_process(comm: &str) -> bool {
    matches!(
        comm,
        "systemd" | "systemd-oomd" | "resource-guardian" | "emergency-room" | "bash" | "zsh" | "fish" | "ps" | "rg"
    )
}

fn send_notification(cfg: &Config, replace_id: &str, urgency: &str, icon: &str, title: &str, body: &str) -> bool {
    if cfg.dry_run {
        log_line(&format!("dry-run notify ({urgency}): {title} — {body}"));
        return true;
    }

    let status = Command::new("notify-send")
        .args([
            "--app-name",
            "AmbientOps",
            "--urgency",
            urgency,
            "--icon",
            icon,
            "-r",
            replace_id,
            title,
            body,
        ])
        .status();

    status.map(|s| s.success()).unwrap_or(false)
}

fn normalize_level(level: &str) -> &str {
    match level {
        "warning" | "critical" | "normal" => level,
        _ => "normal",
    }
}

fn load_state(path: &str) -> WatchState {
    fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str::<WatchState>(&raw).ok())
        .unwrap_or_default()
}

fn save_state(path: &str, state: &WatchState) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(parent) = Path::new(path).parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(state)?;
    let tmp = format!("{path}.tmp");
    fs::write(&tmp, json)?;
    fs::rename(tmp, path)?;
    Ok(())
}

fn log_line(message: &str) {
    println!("{} [ambientops-pulse] {}", Utc::now().to_rfc3339(), message);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_oom_line() {
        let line = "2026-04-12T19:04:42+0100 host systemd-oomd[939]: Killed /user.slice/user-1000.slice/user@1000.service/app.slice/flatpak-session-helper.service due to memory pressure for /user.slice/user-1000.slice/user@1000.service/app.slice being 82.36% > 80.00% for > 20s with reclaim activity";
        let event = parse_oom_event_line(line).expect("event should parse");
        assert_eq!(event.target_hint, "flatpak-session-helper.service");
        assert!(event.signature.contains("flatpak-session-helper.service"));
    }

    #[test]
    fn classifies_memory_levels() {
        let normal = MemorySnapshot {
            available_mb: 16000,
            available_pct: 40,
            swap_used_pct: 10,
        };
        let warn = MemorySnapshot {
            available_mb: 7000,
            available_pct: 22,
            swap_used_pct: 50,
        };
        let critical = MemorySnapshot {
            available_mb: 5000,
            available_pct: 14,
            swap_used_pct: 97,
        };
        assert_eq!(classify_memory_level(&normal), MemoryLevel::Normal);
        assert_eq!(classify_memory_level(&warn), MemoryLevel::Warning);
        assert_eq!(classify_memory_level(&critical), MemoryLevel::Critical);
    }
}
