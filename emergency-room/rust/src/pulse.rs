// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// AmbientOps Pulse — low-overhead watcher for memory pressure + systemd-oomd kills.
// This module is intentionally non-destructive: it only observes and notifies.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::env;
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
const NOTIFY_FAIL_SUPPRESS_THRESHOLD: u32 = 3;
const NOTIFY_SUPPRESS_SECONDS: i64 = 300;
const BACKEND_DEGRADED_THRESHOLD: u32 = 3;
const SESSION_WARN_COOLDOWN_SECONDS: i64 = 60;

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
#[serde(default)]
struct WatchState {
    last_scan_epoch: i64,
    last_oom_signature: String,
    last_oom_notify_epoch: i64,
    last_mem_notify_epoch: i64,
    last_mem_level: String,
    notify_fail_streak: u32,
    notify_suppressed_until_epoch: i64,
    last_notify_error: String,
    consecutive_journal_failures: u32,
    consecutive_mem_failures: u32,
    last_loop_ok_epoch: i64,
    last_no_session_log_epoch: i64,
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
        maybe_recover_notification_channel(&mut state, now_epoch);
        let since_epoch = state
            .last_scan_epoch
            .max(now_epoch - cfg.lookback_seconds.max(30))
            .saturating_sub(2);

        match read_oom_kills_since(since_epoch) {
            Ok(events) => {
                if state.consecutive_journal_failures >= BACKEND_DEGRADED_THRESHOLD {
                    log_line("journal access recovered");
                }
                state.consecutive_journal_failures = 0;
                handle_oom_events(&cfg, &mut state, now_epoch, &events);
            }
            Err(e) => {
                state.consecutive_journal_failures = state.consecutive_journal_failures.saturating_add(1);
                let failures = state.consecutive_journal_failures;
                if failures <= 2 || failures % 10 == 0 {
                    log_line(&format!(
                        "warn: unable to read oom journal events (consecutive={failures}): {e}"
                    ));
                }
                if failures == BACKEND_DEGRADED_THRESHOLD {
                    log_line("degraded: journal backend has repeated failures; continuing in best-effort mode");
                }
            }
        }

        match read_memory_snapshot() {
            Ok(snapshot) => {
                if state.consecutive_mem_failures >= BACKEND_DEGRADED_THRESHOLD {
                    log_line("memory snapshot backend recovered");
                }
                state.consecutive_mem_failures = 0;
                handle_memory_pressure(&cfg, &mut state, now_epoch, &snapshot);
            }
            Err(e) => {
                state.consecutive_mem_failures = state.consecutive_mem_failures.saturating_add(1);
                let failures = state.consecutive_mem_failures;
                if failures <= 2 || failures % 10 == 0 {
                    log_line(&format!(
                        "warn: unable to read memory snapshot (consecutive={failures}): {e}"
                    ));
                }
                if failures == BACKEND_DEGRADED_THRESHOLD {
                    log_line("degraded: memory snapshot backend has repeated failures; continuing in best-effort mode");
                }
            }
        }

        state.last_scan_epoch = now_epoch;
        state.last_loop_ok_epoch = now_epoch;
        if let Err(e) = save_state(&cfg.state_path, &state) {
            log_line(&format!("warn: unable to persist pulse state: {e}"));
        }

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
        state,
        now_epoch,
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
                if send_notification(
                    cfg,
                    state,
                    now_epoch,
                    MEM_NOTIFY_ID,
                    "low",
                    "dialog-information",
                    title,
                    &body,
                ) {
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
            if send_notification(
                cfg,
                state,
                now_epoch,
                MEM_NOTIFY_ID,
                urgency,
                icon,
                title,
                &body,
            ) {
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

fn send_notification(
    cfg: &Config,
    state: &mut WatchState,
    now_epoch: i64,
    replace_id: &str,
    urgency: &str,
    icon: &str,
    title: &str,
    body: &str,
) -> bool {
    if cfg.dry_run {
        log_line(&format!("dry-run notify ({urgency}): {title} — {body}"));
        record_notify_success(state);
        return true;
    }

    if now_epoch < state.notify_suppressed_until_epoch {
        return false;
    }

    if !notification_context_ready() {
        if now_epoch - state.last_no_session_log_epoch >= SESSION_WARN_COOLDOWN_SECONDS {
            log_line("warn: no GUI notification session detected; skipping desktop notification");
            state.last_no_session_log_epoch = now_epoch;
        }
        return false;
    }

    let output = Command::new("notify-send")
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
        .output();

    match output {
        Ok(out) if out.status.success() => {
            record_notify_success(state);
            true
        }
        Ok(out) => {
            let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
            let detail = if stderr.is_empty() {
                format!("notify-send exit status {}", out.status)
            } else {
                stderr
            };
            record_notify_failure(state, now_epoch, &detail);
            false
        }
        Err(e) => {
            record_notify_failure(state, now_epoch, &format!("unable to execute notify-send: {e}"));
            false
        }
    }
}

fn record_notify_success(state: &mut WatchState) {
    if state.notify_fail_streak > 0 || state.notify_suppressed_until_epoch > 0 {
        log_line("notification backend recovered");
    }
    state.notify_fail_streak = 0;
    state.notify_suppressed_until_epoch = 0;
    state.last_notify_error.clear();
}

fn record_notify_failure(state: &mut WatchState, now_epoch: i64, detail: &str) {
    state.notify_fail_streak = state.notify_fail_streak.saturating_add(1);
    state.last_notify_error = truncate_for_log(detail, 240);

    if state.notify_fail_streak >= NOTIFY_FAIL_SUPPRESS_THRESHOLD {
        state.notify_suppressed_until_epoch = now_epoch + NOTIFY_SUPPRESS_SECONDS;
        log_line(&format!(
            "warn: notification backend failing (streak={}, suppress={}s): {}",
            state.notify_fail_streak, NOTIFY_SUPPRESS_SECONDS, state.last_notify_error
        ));
        return;
    }

    log_line(&format!(
        "warn: notification send failed (streak={}): {}",
        state.notify_fail_streak, state.last_notify_error
    ));
}

fn maybe_recover_notification_channel(state: &mut WatchState, now_epoch: i64) {
    if state.notify_suppressed_until_epoch == 0 || now_epoch < state.notify_suppressed_until_epoch {
        return;
    }

    state.notify_suppressed_until_epoch = 0;
    state.notify_fail_streak = 0;
    log_line("notification suppression window elapsed; retrying notifications");
}

fn notification_context_ready() -> bool {
    let has_display = env::var("WAYLAND_DISPLAY").map(|v| !v.trim().is_empty()).unwrap_or(false)
        || env::var("DISPLAY").map(|v| !v.trim().is_empty()).unwrap_or(false);
    let has_session_bus = env::var("DBUS_SESSION_BUS_ADDRESS")
        .map(|v| !v.trim().is_empty())
        .unwrap_or(false)
        || env::var("XDG_RUNTIME_DIR")
            .ok()
            .map(|p| Path::new(&p).join("bus").exists())
            .unwrap_or(false);
    has_display && has_session_bus
}

fn truncate_for_log(s: &str, max_chars: usize) -> String {
    let mut out = String::new();
    let mut count = 0usize;
    for ch in s.chars() {
        if count >= max_chars {
            out.push_str("...");
            break;
        }
        out.push(ch);
        count += 1;
    }
    out
}

fn normalize_level(level: &str) -> &str {
    match level {
        "warning" | "critical" | "normal" => level,
        _ => "normal",
    }
}

fn load_state(path: &str) -> WatchState {
    let raw = match fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(_) => return WatchState::default(),
    };

    match serde_json::from_str::<WatchState>(&raw) {
        Ok(state) => state,
        Err(e) => {
            backup_corrupt_state(path, &raw);
            log_line(&format!("warn: state file was invalid JSON, reset to defaults: {e}"));
            WatchState::default()
        }
    }
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

fn backup_corrupt_state(path: &str, raw: &str) {
    let backup = format!("{path}.corrupt.{}", Utc::now().timestamp());
    if fs::write(&backup, raw).is_ok() {
        log_line(&format!("saved corrupt state backup: {backup}"));
    }
}

fn log_line(message: &str) {
    println!("{} [ambientops-pulse] {}", Utc::now().to_rfc3339(), message);
}

fn command_exists(cmd: &str) -> bool {
    env::var_os("PATH")
        .map(|paths| env::split_paths(&paths).any(|p| p.join(cmd).exists()))
        .unwrap_or(false)
}

fn probe_write_access(dir: &Path) -> bool {
    if fs::create_dir_all(dir).is_err() {
        return false;
    }
    let probe = dir.join(".pulse-write-probe.tmp");
    if fs::write(&probe, "ok").is_err() {
        return false;
    }
    let _ = fs::remove_file(probe);
    true
}

fn recent_user_core_dumps(minutes: u64) -> Result<u32, Box<dyn std::error::Error>> {
    let since = format!("{minutes} min ago");
    let out = Command::new("journalctl")
        .args(["--user", "-p", "err", "--since", &since, "--no-pager"])
        .output()?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        let msg = if stderr.is_empty() {
            format!("journalctl returned non-zero status: {}", out.status)
        } else {
            stderr
        };
        return Err(msg.into());
    }
    let logs = String::from_utf8_lossy(&out.stdout);
    Ok(logs.lines().filter(|line| line.contains("dumped core")).count() as u32)
}

pub fn doctor(cfg: &Config) -> Result<(), Box<dyn std::error::Error>> {
    let state_path = Path::new(&cfg.state_path);
    let state_dir = state_path.parent().unwrap_or(Path::new("."));

    let has_journalctl = command_exists("journalctl");
    let has_notify_send = command_exists("notify-send");
    let has_ps = command_exists("ps");
    let has_notify_context = notification_context_ready();
    let state_file_exists = state_path.exists();
    let state_dir_writable = probe_write_access(state_dir);
    let recent_core_dumps_10m = recent_user_core_dumps(10).unwrap_or(0);

    let mut issues: Vec<String> = Vec::new();
    if !has_journalctl {
        issues.push("journalctl not found on PATH".to_string());
    }
    if !has_notify_send {
        issues.push("notify-send not found; desktop notifications unavailable".to_string());
    }
    if !has_ps {
        issues.push("ps not found; top-process hints unavailable".to_string());
    }
    if !state_dir_writable {
        issues.push(format!(
            "state directory is not writable: {}",
            state_dir.display()
        ));
    }
    if !has_notify_context {
        issues.push("GUI notification context is missing (DISPLAY/WAYLAND or DBus)".to_string());
    }
    if recent_core_dumps_10m > 0 {
        issues.push(format!(
            "observed {recent_core_dumps_10m} user core-dump error entries in last 10m"
        ));
    }

    let status = if !state_dir_writable || !has_journalctl {
        "unhealthy"
    } else if issues.is_empty() {
        "healthy"
    } else {
        "degraded"
    };

    let report = json!({
        "timestamp": Utc::now().to_rfc3339(),
        "component": "ambientops-pulse",
        "status": status,
        "state_path": cfg.state_path,
        "checks": {
            "journalctl_found": has_journalctl,
            "notify_send_found": has_notify_send,
            "ps_found": has_ps,
            "notification_context_ready": has_notify_context,
            "state_file_exists": state_file_exists,
            "state_dir_writable": state_dir_writable,
            "recent_user_core_dumps_10m": recent_core_dumps_10m
        },
        "issues": issues
    });

    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
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
