// SPDX-License-Identifier: PMPL-1.0-or-later
//! Hardware Crash Team - diagnostic and remediation tool for hardware issues
//!
//! Part of the AmbientOps ecosystem (hospital model).
//! The crash team responds to hardware-induced system crashes by scanning
//! PCI devices, detecting zombie hardware, analyzing driver conflicts,
//! and presenting remediation options with human oversight.

use clap::{Parser, Subcommand};
use anyhow::Result;
use serde_json;

mod scanner;
mod analyzer;
mod remediation;
mod types;
mod tui;

/// Hardware Crash Team - diagnose and fix hardware-induced crashes
#[derive(Parser)]
#[command(name = "hardware-crash-team")]
#[command(about = "Diagnostic and remediation tool for zombie hardware, driver conflicts, and PCI bus issues")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Scan system for hardware issues (PCI devices, drivers, IOMMU, ACPI)
    Scan {
        /// Output format (text, json, sarif)
        #[arg(short, long, default_value = "text")]
        format: String,

        /// Save report to file
        #[arg(short, long)]
        output: Option<std::path::PathBuf>,

        /// Verbose output with per-device details
        #[arg(short, long)]
        verbose: bool,

        /// Output as contract-conformant EvidenceEnvelope JSON
        #[arg(long)]
        envelope: bool,
    },

    /// Analyze crash logs and correlate with hardware events
    Diagnose {
        /// Number of recent boots to analyze
        #[arg(short, long, default_value = "10")]
        boots: usize,

        /// Focus on specific PCI device (e.g., "01:00.0")
        #[arg(short, long)]
        device: Option<String>,
    },

    /// Present remediation options for identified issues
    Plan {
        /// Device(s) to remediate (PCI slot, e.g., "01:00.0"). Multiple devices supported.
        #[arg(required = true)]
        devices: Vec<String>,

        /// Strategy: pci-stub, vfio-pci, dual, power-off, disable, unbind
        #[arg(short, long)]
        strategy: Option<String>,

        /// Output as contract-conformant ProcedurePlan JSON
        #[arg(long)]
        procedure: bool,
    },

    /// Apply a remediation plan (requires confirmation)
    Apply {
        /// Plan file from `plan` command
        plan: std::path::PathBuf,

        /// Skip confirmation prompt
        #[arg(long)]
        yes: bool,
    },

    /// Undo a previously applied remediation
    Undo {
        /// Receipt file from `apply` command
        receipt: std::path::PathBuf,
    },

    /// Show system hardware overview
    Status,

    /// Launch interactive TUI (requires --features tui)
    Tui,
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Scan { format, output, verbose, envelope } => {
            println!("Scanning system hardware...");
            let report = scanner::scan_system(verbose)?;

            if envelope {
                let report_json = serde_json::to_value(&report)?;
                let hostname = gethostname();
                let env = ambientops_contracts::conversions::system_report_to_envelope(
                    &report_json,
                    &hostname,
                );
                let formatted = serde_json::to_string_pretty(&env)?;

                if let Some(output_path) = output {
                    std::fs::write(&output_path, &formatted)?;
                    println!("EvidenceEnvelope saved to: {}", output_path.display());
                } else {
                    println!("{}", formatted);
                }
            } else {
                let formatted = scanner::format_report(&report, &format)?;

                if let Some(output_path) = output {
                    std::fs::write(&output_path, &formatted)?;
                    println!("Report saved to: {}", output_path.display());
                } else {
                    println!("{}", formatted);
                }

                // Summary
                let issues = report.devices.iter()
                    .filter(|d| !d.issues.is_empty())
                    .count();
                if issues > 0 {
                    println!("\n{} device(s) with issues detected. Run `hardware-crash-team diagnose` for analysis.", issues);
                } else {
                    println!("\nNo hardware issues detected.");
                }
            }
        }

        Commands::Diagnose { boots, device } => {
            println!("Analyzing {} recent boot(s) for hardware-related crashes...", boots);
            let analysis = analyzer::diagnose(boots, device.as_deref())?;
            analyzer::print_diagnosis(&analysis);
        }

        Commands::Plan { devices, strategy, procedure } => {
            if devices.len() == 1 {
                let device = &devices[0];
                println!("Generating remediation plan for device {}...", device);
                let plan = remediation::create_plan(device, strategy.as_deref())?;

                if procedure {
                    let plan_json = serde_json::to_value(&plan)?;
                    let envelope_ref = uuid::Uuid::new_v4();
                    let proc_plan = ambientops_contracts::conversions::remediation_plan_to_procedure(
                        &plan_json,
                        envelope_ref,
                    );
                    println!("{}", serde_json::to_string_pretty(&proc_plan)?);
                } else {
                    remediation::print_plan(&plan);
                }
            } else {
                println!("Generating multi-device remediation plan for {} devices...", devices.len());
                let multi = remediation::create_multi_plan(&devices, strategy.as_deref())?;

                if procedure {
                    println!("{}", serde_json::to_string_pretty(&multi)?);
                } else {
                    remediation::print_multi_plan(&multi);
                }
            }
        }

        Commands::Apply { plan, yes } => {
            println!("Applying remediation plan from {}...", plan.display());
            if !yes {
                println!("This will modify kernel parameters. Continue? [y/N]");
                // In real implementation, read stdin
                println!("(Use --yes to skip this prompt)");
                return Ok(());
            }
            remediation::apply_plan(&plan)?;
        }

        Commands::Undo { receipt } => {
            println!("Undoing remediation from {}...", receipt.display());
            remediation::undo(&receipt)?;
        }

        Commands::Status => {
            println!("System Hardware Status");
            println!("=====================");
            let report = scanner::scan_system(false)?;
            scanner::print_status(&report);
        }

        Commands::Tui => {
            tui::run()?;
        }
    }

    Ok(())
}

fn gethostname() -> String {
    std::fs::read_to_string("/etc/hostname")
        .unwrap_or_else(|_| "unknown".to_string())
        .trim()
        .to_string()
}
