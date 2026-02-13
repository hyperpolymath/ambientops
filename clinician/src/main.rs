// SPDX-License-Identifier: PMPL-1.0-or-later
//! Personal Sysadmin (PSA) - AI-assisted Linux system administration toolkit
//!
//! A learning system administration tool that:
//! - Monitors and manages system resources (Sysinternals-like)
//! - Learns from solutions via miniKanren reasoning
//! - Searches forums and documentation for fixes
//! - Shares solutions across device mesh via P2P
//! - Uses local SLM with Claude fallback for complex issues

use clap::{Parser, Subcommand};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod reasoning;
mod storage;
mod cache;
mod tools;
mod ai;
mod forum;
mod p2p;
mod satellites;
mod validation;
mod correlation;

// Re-use action enums from tool modules
use tools::process::ProcessAction;
use tools::network::NetworkAction;
use tools::disk::DiskAction;
use tools::service::ServiceAction;
use tools::security::SecurityAction;
use p2p::MeshAction;

#[derive(Parser)]
#[command(name = "psa")]
#[command(author = "hyperpolymath")]
#[command(version)]
#[command(about = "Personal Sysadmin - AI-assisted system administration")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Verbosity level (-v, -vv, -vvv)
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    /// Correlation ID for cross-tool tracing (auto-generated if not provided)
    #[arg(long, global = true)]
    correlation_id: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Process management (like Process Explorer)
    #[command(alias = "ps")]
    Process {
        #[command(subcommand)]
        action: ProcessActionCli,
    },

    /// Network diagnostics (like TCPView)
    #[command(alias = "net")]
    Network {
        #[command(subcommand)]
        action: NetworkActionCli,
    },

    /// Disk and storage management
    #[command(alias = "df")]
    Disk {
        #[command(subcommand)]
        action: DiskActionCli,
    },

    /// Service management (like Autoruns)
    #[command(alias = "svc")]
    Service {
        #[command(subcommand)]
        action: ServiceActionCli,
    },

    /// Security scanning and hardening
    #[command(alias = "sec")]
    Security {
        #[command(subcommand)]
        action: SecurityActionCli,
    },

    /// Diagnose a problem (AI-assisted)
    Diagnose {
        /// Problem description
        problem: String,
        /// Use only local SLM (no Claude)
        #[arg(long)]
        local_only: bool,
    },

    /// Search for solutions in knowledge base and forums
    Search {
        /// Search query
        query: String,
        /// Search online forums too
        #[arg(long)]
        online: bool,
    },

    /// Learn from a solution (store in knowledge base)
    Learn {
        /// Problem category
        #[arg(short, long)]
        category: String,
        /// Solution file or stdin
        solution: Option<String>,
    },

    /// P2P mesh commands
    Mesh {
        #[command(subcommand)]
        action: MeshActionCli,
    },

    /// Interactive monitoring dashboard
    Monitor,

    /// Show system health summary
    Health,

    /// Satellite tool integration (panic-attacker, verisimdb, hypatia, echidna)
    #[command(alias = "sat")]
    Satellite {
        #[command(subcommand)]
        action: SatelliteActionCli,
    },

    /// Crisis mode - analyze incident bundle from emergency-room
    Crisis {
        /// Path to incident bundle from system-emergency-room
        #[arg(long)]
        incident: String,
        /// Correlation ID for cross-tool tracing
        #[arg(long)]
        correlation_id: Option<String>,
    },
}

// Action enums with clap derive for CLI parsing
#[derive(Subcommand, Clone)]
enum ProcessActionCli {
    /// List all processes with resource usage
    List {
        /// Sort by (cpu, mem, pid, name)
        #[arg(short, long, default_value = "cpu")]
        sort: String,
        /// Show only top N processes
        #[arg(short = 'n', long)]
        top: Option<usize>,
    },
    /// Show process tree
    Tree,
    /// Find processes by name or pattern
    Find { pattern: String },
    /// Show detailed info for a process
    Info { pid: u32 },
    /// Kill a process
    Kill { pid: u32 },
    /// Watch a process for anomalies (uses ESN/LSM)
    Watch { pid: u32 },
}

#[derive(Subcommand, Clone)]
enum NetworkActionCli {
    /// Show all connections (like TCPView)
    Connections {
        /// Filter by state (LISTEN, ESTABLISHED, etc.)
        #[arg(short, long)]
        state: Option<String>,
    },
    /// Show listening ports
    Listen,
    /// Show bandwidth usage per process
    Bandwidth,
    /// Test connectivity
    Ping { host: String },
    /// DNS diagnostics
    Dns { domain: String },
    /// Watch for suspicious connections (anomaly detection)
    Watch,
}

#[derive(Subcommand, Clone)]
enum DiskActionCli {
    /// Show disk usage summary
    Usage,
    /// Find large files
    Large {
        /// Minimum size (e.g., "100M", "1G")
        #[arg(short, long, default_value = "100M")]
        min_size: String,
        /// Path to search
        #[arg(default_value = ".")]
        path: String,
    },
    /// Show disk I/O per process
    Io,
    /// Find duplicate files
    Duplicates { path: String },
    /// Analyze disk health (SMART)
    Health,
}

#[derive(Subcommand, Clone)]
enum ServiceActionCli {
    /// List all services
    List {
        /// Show only failed
        #[arg(long)]
        failed: bool,
    },
    /// Show service status
    Status { name: String },
    /// List startup items (like Autoruns)
    Startup,
    /// Analyze service dependencies
    Deps { name: String },
}

#[derive(Subcommand, Clone)]
enum SecurityActionCli {
    /// Scan for common vulnerabilities
    Scan,
    /// Check file permissions
    Perms { path: String },
    /// Audit system configuration
    Audit,
    /// Check for rootkits
    Rootkit,
    /// List open ports and assess exposure
    Exposure,
}

#[derive(Subcommand, Clone)]
enum MeshActionCli {
    /// Discover other PSA instances on network
    Discover,
    /// Join a mesh network
    Join { peer: String },
    /// Share a solution with the mesh
    Share { solution_id: String },
    /// Sync knowledge base with peers
    Sync,
    /// Show mesh status
    Status,
}

#[derive(Subcommand, Clone)]
enum SatelliteActionCli {
    /// Scan target with panic-attacker
    Scan {
        /// Target path to scan
        target: String,
        /// Output JSON path
        #[arg(short, long)]
        output: Option<String>,
    },
    /// Ingest scan results into verisimdb
    Ingest {
        /// Repository name
        repo: String,
        /// Path to scan JSON
        scan_path: String,
    },
    /// Query verisimdb with VQL
    Query {
        /// VQL query string
        vql: String,
    },
    /// Verify procedure reversibility with echidna
    Verify {
        /// Path to procedure plan JSON
        procedure_path: String,
    },
    /// Check gitbot-fleet status
    FleetStatus,
}

impl From<SatelliteActionCli> for satellites::SatelliteAction {
    fn from(cli: SatelliteActionCli) -> Self {
        match cli {
            SatelliteActionCli::Scan { target, output } => {
                satellites::SatelliteAction::Scan { target, output }
            }
            SatelliteActionCli::Ingest { repo, scan_path } => {
                satellites::SatelliteAction::Ingest { repo, scan_path }
            }
            SatelliteActionCli::Query { vql } => {
                satellites::SatelliteAction::Query { vql }
            }
            SatelliteActionCli::Verify { procedure_path } => {
                satellites::SatelliteAction::Verify { procedure_path }
            }
            SatelliteActionCli::FleetStatus => {
                satellites::SatelliteAction::FleetStatus
            }
        }
    }
}

// Conversion helpers
impl From<ProcessActionCli> for ProcessAction {
    fn from(cli: ProcessActionCli) -> Self {
        match cli {
            ProcessActionCli::List { sort, top } => ProcessAction::List { sort, top },
            ProcessActionCli::Tree => ProcessAction::Tree,
            ProcessActionCli::Find { pattern } => ProcessAction::Find { pattern },
            ProcessActionCli::Info { pid } => ProcessAction::Info { pid },
            ProcessActionCli::Kill { pid } => ProcessAction::Kill { pid },
            ProcessActionCli::Watch { pid } => ProcessAction::Watch { pid },
        }
    }
}

impl From<NetworkActionCli> for NetworkAction {
    fn from(cli: NetworkActionCli) -> Self {
        match cli {
            NetworkActionCli::Connections { state } => NetworkAction::Connections { state },
            NetworkActionCli::Listen => NetworkAction::Listen,
            NetworkActionCli::Bandwidth => NetworkAction::Bandwidth,
            NetworkActionCli::Ping { host } => NetworkAction::Ping { host },
            NetworkActionCli::Dns { domain } => NetworkAction::Dns { domain },
            NetworkActionCli::Watch => NetworkAction::Watch,
        }
    }
}

impl From<DiskActionCli> for DiskAction {
    fn from(cli: DiskActionCli) -> Self {
        match cli {
            DiskActionCli::Usage => DiskAction::Usage,
            DiskActionCli::Large { min_size, path } => DiskAction::Large { min_size, path },
            DiskActionCli::Io => DiskAction::Io,
            DiskActionCli::Duplicates { path } => DiskAction::Duplicates { path },
            DiskActionCli::Health => DiskAction::Health,
        }
    }
}

impl From<ServiceActionCli> for ServiceAction {
    fn from(cli: ServiceActionCli) -> Self {
        match cli {
            ServiceActionCli::List { failed } => ServiceAction::List { failed },
            ServiceActionCli::Status { name } => ServiceAction::Status { name },
            ServiceActionCli::Startup => ServiceAction::Startup,
            ServiceActionCli::Deps { name } => ServiceAction::Deps { name },
        }
    }
}

impl From<SecurityActionCli> for SecurityAction {
    fn from(cli: SecurityActionCli) -> Self {
        match cli {
            SecurityActionCli::Scan => SecurityAction::Scan,
            SecurityActionCli::Perms { path } => SecurityAction::Perms { path },
            SecurityActionCli::Audit => SecurityAction::Audit,
            SecurityActionCli::Rootkit => SecurityAction::Rootkit,
            SecurityActionCli::Exposure => SecurityAction::Exposure,
        }
    }
}

impl From<MeshActionCli> for MeshAction {
    fn from(cli: MeshActionCli) -> Self {
        match cli {
            MeshActionCli::Discover => MeshAction::Discover,
            MeshActionCli::Join { peer } => MeshAction::Join { peer },
            MeshActionCli::Share { solution_id } => MeshAction::Share { solution_id },
            MeshActionCli::Sync => MeshAction::Sync,
            MeshActionCli::Status => MeshAction::Status,
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Initialize correlation ID for distributed tracing
    let corr_id = correlation::init(cli.correlation_id.clone());

    // Initialize logging
    let log_level = match cli.verbose {
        0 => "info",
        1 => "debug",
        _ => "trace",
    };

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| log_level.into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!(correlation_id = %corr_id, "Starting PSA session");

    // Initialize storage and cache connections
    let storage = storage::Storage::new().await?;
    let cache = cache::Cache::new().await?;

    match cli.command {
        Commands::Process { action } => {
            tools::process::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Network { action } => {
            tools::network::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Disk { action } => {
            tools::disk::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Service { action } => {
            tools::service::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Security { action } => {
            tools::security::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Diagnose { problem, local_only } => {
            ai::diagnose(&problem, local_only, &storage, &cache).await?;
        }
        Commands::Search { query, online } => {
            forum::search(&query, online, &storage, &cache).await?;
        }
        Commands::Learn { category, solution } => {
            reasoning::learn(&category, solution, &storage).await?;
        }
        Commands::Mesh { action } => {
            p2p::handle(action.into(), &storage, &cache).await?;
        }
        Commands::Satellite { action } => {
            satellites::handle(action.into()).await?;
        }
        Commands::Monitor => {
            tools::monitor::run(&storage, &cache).await?;
        }
        Commands::Health => {
            tools::health::show(&storage, &cache).await?;
        }
        Commands::Crisis { incident, correlation_id } => {
            tools::crisis::analyze(&incident, correlation_id.as_deref(), &storage, &cache).await?;
        }
    }

    Ok(())
}
