// SPDX-License-Identifier: PMPL-1.0-or-later

//! Personal Sysadmin (PSA) — AI-Assisted System Administration Toolkit (CLI).
//!
//! This binary implements the "Clinician" logic for Linux environments.
//! It provides a comprehensive suite of administrative tools combined with
//! neurosymbolic reasoning to automate problem detection and resolution.
//!
//! CORE CAPABILITIES:
//! 1. **Resource Auditing**: Real-time management of processes, networks,
//!    disks, and services.
//! 2. **AI-Diagnostics**: Uses local SLMs (Small Language Models) with
//!    cloud LLM fallback to diagnose complex system incidents.
//! 3. **Knowledge Ingestion**: Learns from solutions using miniKanren
//!    logical reasoning, building a verified administrative knowledge base.
//! 4. **Distributed Tracing**: Uses a global `correlation_id` to link
//!    events across the satellite tool fleet.
//! 5. **P2P Mesh**: Securely shares administrative insights and solutions
//!    across a decentralized mesh of PSA nodes.
//!
//! NOTE: This binary is a minimal dispatcher. The rich CLI surface described
//! in the module-level docs is scaffolded in `lib.rs`; wiring each
//! sub-command through clap is tracked as follow-up work.

use ambientops_clinician::{ai, cache, correlation, storage};
use clap::{Parser, Subcommand};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// CLI SCHEMA: Defines the subcommand space for the Personal Sysadmin.
#[derive(Parser)]
#[command(name = "psa", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// TRACING: Unique ID used to correlate logs across distributed PSA sessions.
    #[arg(long, global = true)]
    correlation_id: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// REASONING: AI-assisted diagnosis.
    Diagnose {
        /// Natural-language description of the problem.
        problem: String,
        /// Restrict diagnosis to the local SLM (no cloud fallback).
        #[arg(long)]
        local_only: bool,
    },
    /// REASONING: Record a solution under a category.
    Learn {
        /// Category label for the solution (e.g. "disk", "network").
        category: String,
        /// Optional free-form solution text.
        solution: Option<String>,
    },
    /// Show protocol and binary version.
    Version,
}

/// MAIN ENTRY: Boots the async runtime, initializes global state,
/// and dispatches to tool handlers.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "info".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    // PROVENANCE: Initialize the correlation context for distributed tracing.
    let _corr_id = correlation::init(cli.correlation_id.clone());

    // STORAGE: Establish links to the local knowledge base and state cache.
    let storage = storage::Storage::new().await?;
    let cache = cache::Cache::new().await?;

    match cli.command {
        Commands::Diagnose { problem, local_only } => {
            ai::diagnose(&problem, local_only, &storage, &cache).await?;
        }
        Commands::Learn { category, solution } => {
            println!(
                "learn: category={category} solution={}",
                solution.as_deref().unwrap_or("(none)")
            );
        }
        Commands::Version => {
            println!(
                "ambientops-clinician {} (protocol {})",
                env!("CARGO_PKG_VERSION"),
                ambientops_clinician::PROTOCOL_VERSION
            );
        }
    }
    Ok(())
}
