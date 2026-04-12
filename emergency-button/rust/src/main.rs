// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Emergency Button — offline-first, non-destructive, idempotent recovery launcher.
// Rust replacement for src/*.v (V-lang banned 2026-04-10).

mod backup;
mod capture;
mod handoff;
mod incident;

use clap::{Args, Parser, Subcommand};

#[derive(Parser)]
#[command(
    name    = "emergency-button",
    version = "0.2.0",
    about   = "Emergency system recovery launcher.\nOffline-first, non-destructive, idempotent."
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Create incident bundle and capture safe diagnostics
    Trigger(TriggerArgs),
}

#[derive(Args)]
struct TriggerArgs {
    /// Destination path for quick backup (opt-in)
    #[arg(short = 'b', long)]
    quick_backup: Option<String>,

    /// Preview actions without executing
    #[arg(short = 'n', long)]
    dry_run: bool,

    /// Verbose output
    #[arg(short = 'V', long)]
    verbose: bool,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Some(Command::Trigger(args)) => run_trigger(args),
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
    println!("\x1b[34m║\x1b[0m       \x1b[1mEMERGENCY BUTTON\x1b[0m                   \x1b[34m║\x1b[0m");
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

    println!("\x1b[32m[OK]\x1b[0m Created incident bundle: {}", inc.path);
    println!("\x1b[34m[INFO]\x1b[0m Correlation ID: {}", inc.correlation_id);
    println!();

    println!("\x1b[34m[INFO]\x1b[0m Capturing safe diagnostics…");
    capture::run_all(&mut inc, &cfg);

    if let Err(e) = incident::write_receipt(&inc, &cfg) {
        eprintln!("\x1b[33m[WARN]\x1b[0m Could not write receipt: {e}");
    }

    if let Some(dest) = &cfg.quick_backup_dest {
        println!();
        println!("\x1b[34m[INFO]\x1b[0m Quick backup requested to: {dest}");
        backup::run(&inc, &cfg);
    }

    println!();
    handoff::run(&inc, &cfg);

    println!();
    println!("\x1b[32m════════════════════════════════════════════\x1b[0m");
    println!("\x1b[32m[DONE]\x1b[0m Incident bundle ready: {}", inc.path);
    println!("\x1b[32m════════════════════════════════════════════\x1b[0m");
}

fn print_help() {
    println!("\x1b[1memergency-button\x1b[0m — Emergency system recovery launcher");
    println!();
    println!("\x1b[1mUSAGE:\x1b[0m");
    println!("    emergency-button trigger [OPTIONS]");
    println!();
    println!("\x1b[1mCOMMANDS:\x1b[0m");
    println!("    trigger     Create incident bundle and capture diagnostics");
    println!("    help        Show this help message");
    println!();
    println!("\x1b[1mOPTIONS (for trigger):\x1b[0m");
    println!("    -b, --quick-backup <path>   Run quick backup to destination (opt-in)");
    println!("    -n, --dry-run               Preview actions without executing");
    println!("    -V, --verbose               Verbose output");
    println!();
    println!("\x1b[1mSAFETY:\x1b[0m");
    println!("    Default action is non-destructive and offline-first");
    println!("    No silent downloads, no auto-fixes");
    println!("    Idempotent: pressing twice is safe");
    println!("    Everything logged to incident bundle");
}
