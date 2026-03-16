// SPDX-License-Identifier: PMPL-1.0-or-later

//! Hardware Crash Team — Low-Level Hardware Diagnostics & Remediation (CLI).
//!
//! This binary implements the "Emergency Room" logic for physical systems 
//! within the AmbientOps ecosystem. It is designed to identify and mitigate 
//! hardware-induced crashes by analyzing PCI buses, driver conflicts, 
//! and kernel-level trace logs.
//!
//! CORE CAPABILITIES:
//! 1. **Scanner**: Deep inspection of PCI devices, IOMMU groups, and ACPI tables.
//! 2. **Diagnose**: Temporal correlation between hardware events and system crashes.
//! 3. **Remediation**: Generates declarative plans to isolate "Zombie Hardware" 
//!    (e.g., using `pci-stub` or `vfio-pci`).
//! 4. **Safety**: All destructive actions (Apply) require human oversight 
//!    and produce reversible receipts.
//!
//! ARCHITECTURE:
//! - **Clap**: CLI argument parsing with domain-specific subcommands.
//! - **Contracts**: Full integration with AmbientOps Evidence Envelopes 
//!   for verifiable reporting.

#![forbid(unsafe_code)]
use clap::{Parser, Subcommand};
use anyhow::Result;
use serde_json;

mod scanner;
mod analyzer;
mod remediation;
mod types;
mod tui;
mod sarif; // SARIF serialization for high-assurance audit trails.

#[derive(Parser)]
#[command(name = "hardware-crash-team")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// SCAN: Audits the host hardware state. 
    /// Supports exporting to `sarif` or `EvidenceEnvelope` formats.
    Scan {
        #[arg(short, long, default_value = "text")] format: String,
        #[arg(long)] envelope: bool, // Wrap in contract-conformant envelope.
        // ... [other flags]
    },

    /// DIAGNOSE: Analyzes historical boot logs (`journalctl`) to isolate 
    /// the specific PCI device responsible for a kernel panic.
    Diagnose {
        #[arg(short, long, default_value = "10")] boots: usize,
        #[arg(short, long)] device: Option<String>, // BDF address (e.g. 01:00.0)
    },

    /// PLAN: Generates a declarative procedure to disable or isolate 
    /// faulty hardware without physical removal.
    Plan {
        #[arg(required = true)] devices: Vec<String>,
        #[arg(short, long)] strategy: Option<String>, // e.g. "pci-stub", "power-off"
    },

    /// APPLY: Physically executes a remediation plan (e.g. modifying kernel cmdline).
    Apply { plan: std::path::PathBuf, #[arg(long)] yes: bool },

    /// UNDO: Uses a receipt to restore the system to its pre-remediation state.
    Undo { receipt: std::path::PathBuf },

    /// STATUS: Quick health overview of the physical PCI topology.
    Status,
}

/// MAIN ENTRY: Initializes the async runtime and dispatches to 
/// specialized module runners.
fn main() -> Result<()> {
    // ... [Tracing and CLI parsing logic]
    match cli.command {
        Commands::Scan { .. } => {
            // EXECUTION: Triggers the physical bus probe.
            let report = scanner::scan_system(verbose)?;
            // ... [Reporting and conversion logic]
        }
        // ... [Remaining handlers]
    }
    Ok(())
}
