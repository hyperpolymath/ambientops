// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// AmbientOps Pulse — low-overhead watcher for memory pressure + systemd-oomd kills.
// This module is intentionally non-destructive: it only observes and notifies.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{hash_map::DefaultHasher, HashMap, HashSet};
use std::env;
use std::fs;
use std::fs::OpenOptions;
use std::hash::{Hash, Hasher};
use std::io::Write;
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
    pub a2ml_log_path: String,
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

#[derive(Debug, Clone, Serialize)]
struct PulseAssessment {
    category: String,
    severity: String,
    summary: String,
    action: String,
    confidence: f32,
}

#[derive(Debug, Clone, Copy)]
struct ReasoningContext {
    memory_level: MemoryLevel,
    available_pct: u8,
    swap_used_pct: u8,
    oom_event_seen: bool,
    notify_backend_degraded: bool,
    journal_backend_degraded: bool,
    memory_backend_degraded: bool,
}

impl ReasoningContext {
    fn from_state(state: &WatchState, snapshot: Option<&MemorySnapshot>, oom_event_seen: bool, now_epoch: i64) -> Self {
        let memory_level = snapshot
            .map(classify_memory_level)
            .unwrap_or_else(|| MemoryLevel::from_str(&state.last_mem_level));
        let available_pct = snapshot.map(|s| s.available_pct).unwrap_or(100);
        let swap_used_pct = snapshot.map(|s| s.swap_used_pct).unwrap_or_else(|| 0);

        Self {
            memory_level,
            available_pct,
            swap_used_pct,
            oom_event_seen,
            notify_backend_degraded: state.notify_fail_streak >= NOTIFY_FAIL_SUPPRESS_THRESHOLD
                || state.notify_suppressed_until_epoch > now_epoch,
            journal_backend_degraded: state.consecutive_journal_failures >= BACKEND_DEGRADED_THRESHOLD,
            memory_backend_degraded: state.consecutive_mem_failures >= BACKEND_DEGRADED_THRESHOLD,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum LogicTerm {
    Atom(String),
    Var(String),
    Compound(String, Vec<LogicTerm>),
}

#[derive(Debug, Clone)]
struct LogicClause {
    head: LogicTerm,
    body: Vec<LogicTerm>,
    confidence: f32,
}

type LogicSubstitution = HashMap<String, LogicTerm>;

#[derive(Debug, Default)]
struct MiniKanrenLikeEngine {
    clauses: Vec<LogicClause>,
}

impl MiniKanrenLikeEngine {
    fn add_fact(&mut self, head: LogicTerm, confidence: f32) {
        self.clauses.push(LogicClause {
            head,
            body: Vec::new(),
            confidence,
        });
    }

    fn add_rule(&mut self, head: LogicTerm, body: Vec<LogicTerm>, confidence: f32) {
        self.clauses.push(LogicClause {
            head,
            body,
            confidence,
        });
    }

    fn walk(&self, term: &LogicTerm, subst: &LogicSubstitution) -> LogicTerm {
        match term {
            LogicTerm::Var(name) => {
                if let Some(next) = subst.get(name) {
                    self.walk(next, subst)
                } else {
                    term.clone()
                }
            }
            _ => term.clone(),
        }
    }

    fn unify(&self, left: &LogicTerm, right: &LogicTerm, subst: &LogicSubstitution) -> Option<LogicSubstitution> {
        let left = self.walk(left, subst);
        let right = self.walk(right, subst);

        match (&left, &right) {
            (LogicTerm::Var(v1), LogicTerm::Var(v2)) if v1 == v2 => Some(subst.clone()),
            (LogicTerm::Var(v), term) | (term, LogicTerm::Var(v)) => {
                let mut next = subst.clone();
                next.insert(v.clone(), term.clone());
                Some(next)
            }
            (LogicTerm::Atom(a), LogicTerm::Atom(b)) if a == b => Some(subst.clone()),
            (LogicTerm::Compound(name1, args1), LogicTerm::Compound(name2, args2))
                if name1 == name2 && args1.len() == args2.len() =>
            {
                let mut merged = subst.clone();
                for (a, b) in args1.iter().zip(args2.iter()) {
                    merged = self.unify(a, b, &merged)?;
                }
                Some(merged)
            }
            _ => None,
        }
    }

    fn query(&self, goal: &LogicTerm) -> Vec<(LogicSubstitution, f32)> {
        let mut results = Vec::new();
        for clause in &self.clauses {
            if let Some(initial_subst) = self.unify(goal, &clause.head, &HashMap::new()) {
                if clause.body.is_empty() {
                    results.push((initial_subst, clause.confidence));
                } else if let Some((proved_subst, body_confidence)) = self.prove_body(&clause.body, &initial_subst) {
                    results.push((proved_subst, clause.confidence * body_confidence));
                }
            }
        }
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        results
    }

    fn prove_body(&self, goals: &[LogicTerm], subst: &LogicSubstitution) -> Option<(LogicSubstitution, f32)> {
        let mut current = subst.clone();
        let mut confidence = 1.0f32;

        for goal in goals {
            let resolved = self.walk(goal, &current);
            let mut matches = self.query(&resolved).into_iter();
            let (next_subst, next_confidence) = matches.next()?;
            current.extend(next_subst);
            confidence *= next_confidence;
        }

        Some((current, confidence))
    }
}

fn atom(value: &str) -> LogicTerm {
    LogicTerm::Atom(value.to_string())
}

fn var(value: &str) -> LogicTerm {
    LogicTerm::Var(value.to_string())
}

fn compound(name: &str, args: Vec<LogicTerm>) -> LogicTerm {
    LogicTerm::Compound(name.to_string(), args)
}

fn subst_atom(subst: &LogicSubstitution, key: &str) -> Option<String> {
    match subst.get(key) {
        Some(LogicTerm::Atom(value)) => Some(value.clone()),
        _ => None,
    }
}

fn infer_assessments(ctx: &ReasoningContext) -> Vec<PulseAssessment> {
    let mut engine = MiniKanrenLikeEngine::default();

    let swap_state = if ctx.swap_used_pct >= WARN_SWAP_PCT { "high" } else { "low" };
    let avail_state = if ctx.available_pct <= WARN_MEM_PCT { "low" } else { "ok" };
    let oom_state = if ctx.oom_event_seen { "seen" } else { "none" };
    let notify_state = if ctx.notify_backend_degraded { "degraded" } else { "healthy" };
    let journal_state = if ctx.journal_backend_degraded { "degraded" } else { "healthy" };
    let memory_backend_state = if ctx.memory_backend_degraded { "degraded" } else { "healthy" };

    engine.add_fact(compound("mem_level", vec![atom(ctx.memory_level.as_str())]), 1.0);
    engine.add_fact(compound("swap_state", vec![atom(swap_state)]), 1.0);
    engine.add_fact(compound("available_state", vec![atom(avail_state)]), 1.0);
    engine.add_fact(compound("oom_event", vec![atom(oom_state)]), 1.0);
    engine.add_fact(compound("notify_backend", vec![atom(notify_state)]), 1.0);
    engine.add_fact(compound("journal_backend", vec![atom(journal_state)]), 1.0);
    engine.add_fact(compound("memory_backend", vec![atom(memory_backend_state)]), 1.0);

    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("stability"),
                atom("critical"),
                atom("OOM kills observed during critical memory pressure; possible crash loop."),
                atom("Investigate: journalctl --user -p err --since '5 min ago' | grep 'dumped core'"),
            ],
        ),
        vec![
            compound("mem_level", vec![atom("critical")]),
            compound("oom_event", vec![atom("seen")]),
        ],
        0.98,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("memory"),
                atom("critical"),
                atom("Memory pressure is critical and likely to trigger app terminations."),
                atom("Close high-RSS apps and inspect top consumers with ps -eo pid,rss,comm --sort=-rss"),
            ],
        ),
        vec![compound("mem_level", vec![atom("critical")])],
        0.92,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("memory"),
                atom("warning"),
                atom("Memory pressure is elevated."),
                atom("Trim workloads, close heavy tabs/apps, and monitor for escalation."),
            ],
        ),
        vec![compound("mem_level", vec![atom("warning")])],
        0.72,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("memory"),
                atom("warning"),
                atom("Swap usage is high; thrashing risk is increasing."),
                atom("Reduce concurrent workloads; consider increasing swap or free RAM."),
            ],
        ),
        vec![compound("swap_state", vec![atom("high")])],
        0.74,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("notifications"),
                atom("warning"),
                atom("Notification backend is degraded; pulse is operating in log-first mode."),
                atom("Check DISPLAY/WAYLAND/DBus session, then restart ambientops-pulse.service."),
            ],
        ),
        vec![compound("notify_backend", vec![atom("degraded")])],
        0.79,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("telemetry"),
                atom("warning"),
                atom("journalctl access is degraded; OOM visibility may be incomplete."),
                atom("Verify journalctl permissions and user session journal availability."),
            ],
        ),
        vec![compound("journal_backend", vec![atom("degraded")])],
        0.76,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("telemetry"),
                atom("warning"),
                atom("Memory snapshot backend is degraded; pressure classification may be stale."),
                atom("Inspect /proc/meminfo access and service sandbox permissions."),
            ],
        ),
        vec![compound("memory_backend", vec![atom("degraded")])],
        0.76,
    );
    engine.add_rule(
        compound(
            "assessment",
            vec![
                atom("memory"),
                atom("low"),
                atom("Memory pressure is normal."),
                atom("No action required."),
            ],
        ),
        vec![
            compound("mem_level", vec![atom("normal")]),
            compound("swap_state", vec![atom("low")]),
            compound("available_state", vec![atom("ok")]),
        ],
        0.55,
    );

    let query = compound(
        "assessment",
        vec![var("Category"), var("Severity"), var("Summary"), var("Action")],
    );
    let results = engine.query(&query);

    let mut seen = HashSet::new();
    let mut assessments = Vec::new();
    for (subst, confidence) in results {
        let Some(category) = subst_atom(&subst, "Category") else {
            continue;
        };
        let Some(severity) = subst_atom(&subst, "Severity") else {
            continue;
        };
        let Some(summary) = subst_atom(&subst, "Summary") else {
            continue;
        };
        let Some(action) = subst_atom(&subst, "Action") else {
            continue;
        };

        let dedupe_key = format!("{category}|{severity}|{summary}|{action}");
        if seen.contains(&dedupe_key) {
            continue;
        }
        seen.insert(dedupe_key);
        assessments.push(PulseAssessment {
            category,
            severity,
            summary,
            action,
            confidence,
        });
    }

    assessments
}

pub fn run(cfg: Config) -> Result<(), Box<dyn std::error::Error>> {
    let mut state = load_state(&cfg.state_path);
    if state.last_scan_epoch == 0 {
        state.last_scan_epoch = Utc::now().timestamp() - cfg.lookback_seconds.max(30);
    }
    state.last_mem_level = normalize_level(&state.last_mem_level).to_string();

    log_line(&format!(
        "ambientops-pulse started (poll={}s, lookback={}s, cooldown={}s, state={}, a2ml={})",
        cfg.poll_seconds,
        cfg.lookback_seconds,
        cfg.notify_cooldown_seconds,
        cfg.state_path,
        cfg.a2ml_log_path
    ));
    let startup_context = ReasoningContext::from_state(&state, None, false, Utc::now().timestamp());
    emit_a2ml_event(
        &cfg,
        "pulse_start",
        "low",
        "ambientops-pulse started",
        json!({
            "poll_seconds": cfg.poll_seconds,
            "lookback_seconds": cfg.lookback_seconds,
            "notify_cooldown_seconds": cfg.notify_cooldown_seconds,
            "state_path": cfg.state_path.as_str(),
            "a2ml_log_path": cfg.a2ml_log_path.as_str()
        }),
        &infer_assessments(&startup_context),
    );

    loop {
        let now_epoch = Utc::now().timestamp();
        maybe_recover_notification_channel(&cfg, &mut state, now_epoch);
        let since_epoch = state
            .last_scan_epoch
            .max(now_epoch - cfg.lookback_seconds.max(30))
            .saturating_sub(2);

        match read_oom_kills_since(since_epoch) {
            Ok(events) => {
                if state.consecutive_journal_failures >= BACKEND_DEGRADED_THRESHOLD {
                    log_line("journal access recovered");
                    let context = ReasoningContext::from_state(&state, None, false, now_epoch);
                    emit_a2ml_event(
                        &cfg,
                        "backend_recovered",
                        "low",
                        "journal backend recovered",
                        json!({
                            "backend": "journalctl",
                            "consecutive_failures_before_recovery": state.consecutive_journal_failures
                        }),
                        &infer_assessments(&context),
                    );
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
                    let context = ReasoningContext::from_state(&state, None, false, now_epoch);
                    emit_a2ml_event(
                        &cfg,
                        "backend_degraded",
                        "warning",
                        "journal backend has repeated failures",
                        json!({
                            "backend": "journalctl",
                            "consecutive_failures": failures,
                            "error": e.to_string()
                        }),
                        &infer_assessments(&context),
                    );
                }
            }
        }

        match read_memory_snapshot() {
            Ok(snapshot) => {
                if state.consecutive_mem_failures >= BACKEND_DEGRADED_THRESHOLD {
                    log_line("memory snapshot backend recovered");
                    let context = ReasoningContext::from_state(&state, Some(&snapshot), false, now_epoch);
                    emit_a2ml_event(
                        &cfg,
                        "backend_recovered",
                        "low",
                        "memory snapshot backend recovered",
                        json!({
                            "backend": "meminfo",
                            "consecutive_failures_before_recovery": state.consecutive_mem_failures
                        }),
                        &infer_assessments(&context),
                    );
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
                    let context = ReasoningContext::from_state(&state, None, false, now_epoch);
                    emit_a2ml_event(
                        &cfg,
                        "backend_degraded",
                        "warning",
                        "memory snapshot backend has repeated failures",
                        json!({
                            "backend": "meminfo",
                            "consecutive_failures": failures,
                            "error": e.to_string()
                        }),
                        &infer_assessments(&context),
                    );
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
    let context = ReasoningContext::from_state(state, None, true, now_epoch);
    let assessments = infer_assessments(&context);

    let cooldown_ok = now_epoch - state.last_oom_notify_epoch >= cfg.notify_cooldown_seconds;
    if !cooldown_ok {
        log_line(&format!(
            "oom event observed (suppressed by cooldown): {} {}",
            event.timestamp, event.target_hint
        ));
        emit_a2ml_event(
            cfg,
            "oom_kill",
            "critical",
            "systemd-oomd kill observed (notification suppressed by cooldown)",
            json!({
                "timestamp": event.timestamp,
                "target_hint": event.target_hint,
                "target_path": event.target_path,
                "cooldown_seconds": cfg.notify_cooldown_seconds,
                "notification_sent": false,
                "suppressed_by_cooldown": true
            }),
            &assessments,
        );
        return;
    }

    let reasoner_hint = assessments
        .iter()
        .find(|a| a.category == "stability" || a.category == "memory")
        .or_else(|| assessments.first())
        .map(|a| format!("\nReasoner ({:.0}%): {}\nAction: {}", a.confidence * 100.0, a.summary, a.action))
        .unwrap_or_default();

    let title = "Memory Shortage Avoided";
    let body = format!(
        "systemd-oomd terminated {} due to sustained memory pressure.\nInspect with: journalctl --since \"10 min ago\" -u systemd-oomd --no-pager{}",
        event.target_hint, reasoner_hint
    );

    let notified = send_notification(
        cfg,
        state,
        now_epoch,
        OOM_NOTIFY_ID,
        "critical",
        "dialog-warning",
        title,
        &body,
    );
    if notified {
        state.last_oom_notify_epoch = now_epoch;
    }
    emit_a2ml_event(
        cfg,
        "oom_kill",
        "critical",
        "systemd-oomd kill observed",
        json!({
            "timestamp": event.timestamp,
            "target_hint": event.target_hint,
            "target_path": event.target_path,
            "notification_sent": notified,
            "suppressed_by_cooldown": false
        }),
        &assessments,
    );

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
    let context = ReasoningContext::from_state(state, Some(snapshot), false, now_epoch);
    let assessments = infer_assessments(&context);

    match level {
        MemoryLevel::Normal => {
            if previous != MemoryLevel::Normal {
                let title = "Memory Recovered";
                let reasoner_hint = assessments
                    .iter()
                    .find(|a| a.category == "memory")
                    .or_else(|| assessments.first())
                    .map(|a| format!("\nReasoner ({:.0}%): {}", a.confidence * 100.0, a.summary))
                    .unwrap_or_default();
                let body = format!(
                    "Memory pressure is back to normal.\nAvailable: {}MB ({}%), swap used: {}%.{}",
                    snapshot.available_mb, snapshot.available_pct, snapshot.swap_used_pct, reasoner_hint
                );
                let notified = send_notification(
                    cfg,
                    state,
                    now_epoch,
                    MEM_NOTIFY_ID,
                    "low",
                    "dialog-information",
                    title,
                    &body,
                );
                if notified {
                    state.last_mem_notify_epoch = now_epoch;
                }
                emit_a2ml_event(
                    cfg,
                    "memory_recovered",
                    "low",
                    "memory pressure recovered to normal",
                    json!({
                        "available_mb": snapshot.available_mb,
                        "available_pct": snapshot.available_pct,
                        "swap_used_pct": snapshot.swap_used_pct,
                        "previous_level": previous.as_str(),
                        "notification_sent": notified
                    }),
                    &assessments,
                );
            }
        }
        MemoryLevel::Warning | MemoryLevel::Critical => {
            let top = top_process_summary().unwrap_or_else(|| "Top process unavailable.".to_string());
            let title = if level == MemoryLevel::Critical {
                "Memory Pressure Critical"
            } else {
                "Memory Pressure Warning"
            };
            let reasoner_hint = assessments
                .iter()
                .find(|a| a.category == "stability" || a.category == "memory")
                .or_else(|| assessments.first())
                .map(|a| format!("Reasoner ({:.0}%): {} Action: {}", a.confidence * 100.0, a.summary, a.action))
                .unwrap_or_default();
            let body = format!(
                "Available: {}MB ({}%), swap used: {}%.\n{}\n{}\nConsider closing heavy apps/tabs.",
                snapshot.available_mb, snapshot.available_pct, snapshot.swap_used_pct, top, reasoner_hint
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
            let notified = send_notification(
                cfg,
                state,
                now_epoch,
                MEM_NOTIFY_ID,
                urgency,
                icon,
                title,
                &body,
            );
            if notified {
                state.last_mem_notify_epoch = now_epoch;
            }
            emit_a2ml_event(
                cfg,
                "memory_pressure",
                level.as_str(),
                "memory pressure warning/critical event",
                json!({
                    "level": level.as_str(),
                    "available_mb": snapshot.available_mb,
                    "available_pct": snapshot.available_pct,
                    "swap_used_pct": snapshot.swap_used_pct,
                    "top_process_summary": top,
                    "notification_sent": notified
                }),
                &assessments,
            );
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
        let context = ReasoningContext::from_state(state, None, false, now_epoch);
        emit_a2ml_event(
            cfg,
            "notification",
            "low",
            "notification emitted in dry-run mode",
            json!({
                "replace_id": replace_id,
                "urgency": urgency,
                "icon": icon,
                "title": title,
                "dry_run": true
            }),
            &infer_assessments(&context),
        );
        record_notify_success(state);
        return true;
    }

    if now_epoch < state.notify_suppressed_until_epoch {
        let context = ReasoningContext::from_state(state, None, false, now_epoch);
        emit_a2ml_event(
            cfg,
            "notification_suppressed",
            "warning",
            "notification suppressed due to previous backend failures",
            json!({
                "replace_id": replace_id,
                "urgency": urgency,
                "title": title,
                "suppressed_until_epoch": state.notify_suppressed_until_epoch
            }),
            &infer_assessments(&context),
        );
        return false;
    }

    if !notification_context_ready() {
        if now_epoch - state.last_no_session_log_epoch >= SESSION_WARN_COOLDOWN_SECONDS {
            log_line("warn: no GUI notification session detected; skipping desktop notification");
            state.last_no_session_log_epoch = now_epoch;
        }
        let context = ReasoningContext::from_state(state, None, false, now_epoch);
        emit_a2ml_event(
            cfg,
            "notification_skipped",
            "warning",
            "no GUI notification session detected",
            json!({
                "replace_id": replace_id,
                "urgency": urgency,
                "title": title
            }),
            &infer_assessments(&context),
        );
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
            let context = ReasoningContext::from_state(state, None, false, now_epoch);
            emit_a2ml_event(
                cfg,
                "notification",
                "low",
                "desktop notification delivered",
                json!({
                    "replace_id": replace_id,
                    "urgency": urgency,
                    "icon": icon,
                    "title": title,
                    "dry_run": false,
                    "success": true
                }),
                &infer_assessments(&context),
            );
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
            let context = ReasoningContext::from_state(state, None, false, now_epoch);
            emit_a2ml_event(
                cfg,
                "notification_failure",
                "warning",
                "notify-send returned non-zero status",
                json!({
                    "replace_id": replace_id,
                    "urgency": urgency,
                    "title": title,
                    "error": detail
                }),
                &infer_assessments(&context),
            );
            false
        }
        Err(e) => {
            let detail = format!("unable to execute notify-send: {e}");
            record_notify_failure(state, now_epoch, &detail);
            let context = ReasoningContext::from_state(state, None, false, now_epoch);
            emit_a2ml_event(
                cfg,
                "notification_failure",
                "warning",
                "notify-send execution failed",
                json!({
                    "replace_id": replace_id,
                    "urgency": urgency,
                    "title": title,
                    "error": detail
                }),
                &infer_assessments(&context),
            );
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

fn maybe_recover_notification_channel(cfg: &Config, state: &mut WatchState, now_epoch: i64) {
    if state.notify_suppressed_until_epoch == 0 || now_epoch < state.notify_suppressed_until_epoch {
        return;
    }

    state.notify_suppressed_until_epoch = 0;
    state.notify_fail_streak = 0;
    log_line("notification suppression window elapsed; retrying notifications");
    let context = ReasoningContext::from_state(state, None, false, now_epoch);
    emit_a2ml_event(
        cfg,
        "notification_recovery",
        "low",
        "notification suppression window elapsed",
        json!({
            "event": "suppression_elapsed",
            "notify_fail_streak_reset": true
        }),
        &infer_assessments(&context),
    );
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

fn event_integrity_hash(payload: &serde_json::Value) -> String {
    let payload_json = serde_json::to_string(payload).unwrap_or_else(|_| "{}".to_string());
    let mut hasher = DefaultHasher::new();
    payload_json.hash(&mut hasher);
    format!("siphash13:{:016x}", hasher.finish())
}

fn append_a2ml_envelope(path: &str, envelope: &serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(parent) = Path::new(path).parent() {
        fs::create_dir_all(parent)?;
    }

    let is_new_file = !Path::new(path).exists();
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;

    if is_new_file {
        writeln!(file, "# SPDX-License-Identifier: MPL-2.0")?;
        writeln!(file, "# AmbientOps Pulse A2ML log (append-only JSON envelopes)")?;
    }
    writeln!(file, "{}", serde_json::to_string(envelope)?)?;
    Ok(())
}

fn emit_a2ml_event(
    cfg: &Config,
    event_type: &str,
    severity: &str,
    message: &str,
    context: serde_json::Value,
    assessments: &[PulseAssessment],
) {
    let issued_at = Utc::now().to_rfc3339();
    let payload = json!({
        "event_id": format!("{}-{event_type}", Utc::now().timestamp_millis()),
        "event_type": event_type,
        "severity": severity,
        "component": "ambientops-pulse",
        "issued_at": issued_at,
        "message": message,
        "context": context,
        "diagnostics": assessments
    });
    let envelope = json!({
        "a2ml": {
            "version": "1.0",
            "type": "pulse-event",
            "issuer": "ambientops-pulse",
            "issued_at": issued_at,
            "event_hash": event_integrity_hash(&payload)
        },
        "payload": payload
    });

    if let Err(e) = append_a2ml_envelope(&cfg.a2ml_log_path, &envelope) {
        log_line(&format!(
            "warn: unable to append A2ML pulse log entry at {}: {e}",
            cfg.a2ml_log_path
        ));
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
    let a2ml_log_path = Path::new(&cfg.a2ml_log_path);
    let a2ml_log_dir = a2ml_log_path.parent().unwrap_or(Path::new("."));

    let has_journalctl = command_exists("journalctl");
    let has_notify_send = command_exists("notify-send");
    let has_ps = command_exists("ps");
    let has_notify_context = notification_context_ready();
    let state_file_exists = state_path.exists();
    let state_dir_writable = probe_write_access(state_dir);
    let a2ml_log_exists = a2ml_log_path.exists();
    let a2ml_dir_writable = probe_write_access(a2ml_log_dir);
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
    if !a2ml_dir_writable {
        issues.push(format!(
            "A2ML log directory is not writable: {}",
            a2ml_log_dir.display()
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

    let status = if !state_dir_writable || !a2ml_dir_writable || !has_journalctl {
        "unhealthy"
    } else if issues.is_empty() {
        "healthy"
    } else {
        "degraded"
    };
    let issues_for_event = issues.clone();

    let report = json!({
        "timestamp": Utc::now().to_rfc3339(),
        "component": "ambientops-pulse",
        "status": status,
        "state_path": cfg.state_path.as_str(),
        "a2ml_log_path": cfg.a2ml_log_path.as_str(),
        "checks": {
            "journalctl_found": has_journalctl,
            "notify_send_found": has_notify_send,
            "ps_found": has_ps,
            "notification_context_ready": has_notify_context,
            "state_file_exists": state_file_exists,
            "state_dir_writable": state_dir_writable,
            "a2ml_log_exists": a2ml_log_exists,
            "a2ml_log_dir_writable": a2ml_dir_writable,
            "recent_user_core_dumps_10m": recent_core_dumps_10m
        },
        "issues": issues
    });

    println!("{}", serde_json::to_string_pretty(&report)?);
    let doctor_context = ReasoningContext {
        memory_level: MemoryLevel::Normal,
        available_pct: 100,
        swap_used_pct: 0,
        oom_event_seen: recent_core_dumps_10m > 0,
        notify_backend_degraded: !has_notify_send || !has_notify_context,
        journal_backend_degraded: !has_journalctl,
        memory_backend_degraded: false,
    };
    let severity = match status {
        "unhealthy" => "critical",
        "degraded" => "warning",
        _ => "low",
    };
    emit_a2ml_event(
        cfg,
        "doctor_report",
        severity,
        "pulse doctor completed",
        json!({
            "status": status,
            "issues": issues_for_event,
            "recent_user_core_dumps_10m": recent_core_dumps_10m,
            "state_path": cfg.state_path.as_str(),
            "a2ml_log_path": cfg.a2ml_log_path.as_str()
        }),
        &infer_assessments(&doctor_context),
    );
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

    #[test]
    fn infers_possible_crash_loop_for_oom_plus_critical_memory() {
        let ctx = ReasoningContext {
            memory_level: MemoryLevel::Critical,
            available_pct: 10,
            swap_used_pct: 97,
            oom_event_seen: true,
            notify_backend_degraded: false,
            journal_backend_degraded: false,
            memory_backend_degraded: false,
        };
        let assessments = infer_assessments(&ctx);
        assert!(assessments.iter().any(|a| a.summary.contains("possible crash loop")));
    }

    #[test]
    fn event_integrity_hash_is_stable() {
        let payload = serde_json::json!({
            "event": "memory_pressure",
            "level": "warning",
            "available_pct": 22
        });
        let first = event_integrity_hash(&payload);
        let second = event_integrity_hash(&payload);
        assert_eq!(first, second);
    }
}
