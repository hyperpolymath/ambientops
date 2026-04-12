// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Emergency Room — trigger + boot-guardian + shutdown-marshal.
// Rust replacement for src/*.v (V-lang banned 2026-04-10).

mod backup;
mod boot_guardian;
mod capture;
mod handoff;
mod incident;
mod pulse;
mod shutdown_marshal;

use clap::{Args, Parser, Subcommand};

#[derive(Parser)]
#[command(
    name    = "emergency-room",
    version = "0.2.0",
    about   = "Emergency recovery orchestrator with boot-loop detection and graceful shutdown"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Create incident bundle and capture safe diagnostics
    Trigger(TriggerArgs),
    /// Record boot and detect boot loops
    BootGuardian(BootGuardianArgs),
    /// Orchestrate graceful system shutdown
    ShutdownMarshal(ShutdownArgs),
    /// Watch journal for oomd kill events and notify safely
    #[command(name = "pulse", alias = "oom-watch")]
    Pulse(PulseArgs),
}

#[derive(Args)]
struct TriggerArgs {
    #[arg(short = 'b', long)]
    quick_backup: Option<String>,
    #[arg(short = 'n', long)]
    dry_run: bool,
    #[arg(short = 'V', long)]
    verbose: bool,
}

#[derive(Args)]
struct BootGuardianArgs {
    /// Path to boot stamp file
    #[arg(long, default_value = "/var/lib/ambientops/boot-guardian/stamps.json")]
    stamp_path: String,
    /// Record the current boot
    #[arg(long)]
    record: bool,
    /// Check for boot loops and print report
    #[arg(long)]
    check: bool,
    #[arg(short = 'n', long)]
    dry_run: bool,
}

#[derive(Args)]
struct ShutdownArgs {
    /// Reason for shutdown
    #[arg(long, default_value = "user-initiated")]
    reason: String,
    /// Grace period in seconds
    #[arg(long, default_value_t = 30)]
    grace_period: u64,
    #[arg(short = 'n', long)]
    dry_run: bool,
}

#[derive(Args)]
struct PulseArgs {
    /// Poll interval in seconds
    #[arg(long, default_value_t = 20)]
    poll_seconds: u64,
    /// Initial lookback window in seconds on first run
    #[arg(long, default_value_t = 180)]
    lookback_seconds: i64,
    /// Minimum seconds between desktop notifications
    #[arg(long, default_value_t = 120)]
    notify_cooldown_seconds: i64,
    /// Persisted state path for deduplication and cursoring
    #[arg(long)]
    state_path: Option<String>,
    /// Run one iteration and exit
    #[arg(long)]
    once: bool,
    /// Run self-diagnostics and print a health report as JSON
    #[arg(long)]
    doctor: bool,
    #[arg(short = 'n', long)]
    dry_run: bool,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Some(Command::Trigger(args)) => run_trigger(args),
        Some(Command::BootGuardian(args)) => run_boot_guardian(args),
        Some(Command::ShutdownMarshal(args)) => run_shutdown_marshal(args),
        Some(Command::Pulse(args)) => run_pulse(args),
        None => print_help(),
    }
}

fn run_trigger(args: TriggerArgs) {
    let cfg = incident::Config {
        quick_backup_dest: args.quick_backup.clone(),
        dry_run: args.dry_run,
        verbose: args.verbose,
    };

    println!();
    println!("\x1b[34m╔══════════════════════════════════════════╗\x1b[0m");
    println!("\x1b[34m║\x1b[0m       \x1b[1mEMERGENCY ROOM\x1b[0m                     \x1b[34m║\x1b[0m");
    println!("\x1b[34m║\x1b[0m       Safe • Offline • Idempotent        \x1b[34m║\x1b[0m");
    println!("\x1b[34m╚══════════════════════════════════════════╝\x1b[0m");
    println!();

    if cfg.dry_run {
        println!("\x1b[33m[DRY-RUN]\x1b[0m Preview mode — no changes will be made");
        println!();
    }

    let mut inc = match incident::create_bundle(&cfg) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("\x1b[31m[ERROR]\x1b[0m Failed to create incident bundle: {e}");
            std::process::exit(1);
        }
    };

    println!("\x1b[32m[OK]\x1b[0m Created incident bundle: {}", inc.path.display());
    println!("\x1b[34m[INFO]\x1b[0m Correlation ID: {}", inc.correlation_id);
    println!();

    println!("\x1b[34m[INFO]\x1b[0m Capturing safe diagnostics…");
    capture::run_all(&mut inc, &cfg);

    if let Err(e) = incident::write_receipt(&inc, &cfg) {
        eprintln!("\x1b[33m[WARN]\x1b[0m Could not write receipt: {e}");
    }

    if cfg.quick_backup_dest.is_some() {
        println!();
        backup::run(&inc, &cfg);
    }

    println!();
    handoff::run(&inc, &cfg);

    println!();
    println!("\x1b[32m════════════════════════════════════════════\x1b[0m");
    println!("\x1b[32m[DONE]\x1b[0m Incident bundle ready: {}", inc.path.display());
    println!("\x1b[32m════════════════════════════════════════════\x1b[0m");
}

fn run_boot_guardian(args: BootGuardianArgs) {
    if args.record {
        match boot_guardian::record_boot(&args.stamp_path, args.dry_run) {
            Ok(()) => println!("\x1b[32m[OK]\x1b[0m Boot recorded"),
            Err(e) => eprintln!("\x1b[31m[ERROR]\x1b[0m {e}"),
        }
    }
    if args.check {
        match boot_guardian::check_health(&args.stamp_path) {
            Ok(report) => {
                let json = serde_json::to_string_pretty(&report).unwrap_or_default();
                println!("{json}");
                if report.boot_loop_detected {
                    eprintln!("\x1b[31m[WARN]\x1b[0m Boot loop detected! {} boots in {} seconds",
                        report.recent_boot_count, report.window_seconds);
                }
            }
            Err(e) => eprintln!("\x1b[31m[ERROR]\x1b[0m {e}"),
        }
    }
    if !args.record && !args.check {
        eprintln!("Use --record or --check. See --help.");
    }
}

fn run_shutdown_marshal(args: ShutdownArgs) {
    match shutdown_marshal::orchestrate(&args.reason, args.grace_period, args.dry_run) {
        Ok(report) => {
            let json = serde_json::to_string_pretty(&report).unwrap_or_default();
            println!("{json}");
        }
        Err(e) => eprintln!("\x1b[31m[ERROR]\x1b[0m {e}"),
    }
}

fn run_pulse(args: PulseArgs) {
    let state_path = args.state_path.unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        format!("{home}/.local/share/ambientops/pulse/state.json")
    });

    let cfg = pulse::Config {
        poll_seconds: args.poll_seconds,
        lookback_seconds: args.lookback_seconds,
        notify_cooldown_seconds: args.notify_cooldown_seconds,
        state_path,
        once: args.once,
        dry_run: args.dry_run,
    };

    if args.doctor {
        if let Err(e) = pulse::doctor(&cfg) {
            eprintln!("\x1b[31m[ERROR]\x1b[0m pulse doctor failed: {e}");
            std::process::exit(1);
        }
        return;
    }

    if let Err(e) = pulse::run(cfg) {
        eprintln!("\x1b[31m[ERROR]\x1b[0m pulse failed: {e}");
        std::process::exit(1);
    }
}

fn print_help() {
    println!("\x1b[1memergency-room\x1b[0m — Emergency recovery orchestrator");
    println!();
    println!("\x1b[1mCOMMANDS:\x1b[0m");
    println!("    trigger           Create incident bundle and capture diagnostics");
    println!("    boot-guardian     Detect boot loops, record boot events");
    println!("    shutdown-marshal  Orchestrate graceful shutdown");
    println!("    pulse             Watch for OOM kills and memory pressure");
    println!("                      Alias: oom-watch");
}
