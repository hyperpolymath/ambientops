// SPDX-License-Identifier: PMPL-1.0-or-later
//! mustorch - Mustfile Orchestrator CLI
//!
//! Command-line interface for the Mustfile orchestration engine

use mustfile_orchestrator::{
    orchestrate, MustfileParser, PlatformAdapter,
};
use std::env;
use std::process;

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        process::exit(1);
    }

    let command = &args[1];

    let result = match command.as_str() {
        "deploy" => deploy_command(&args[2..]).await,
        "validate" => validate_command(&args[2..]),
        "info" => info_command(),
        "help" | "--help" | "-h" => {
            print_usage();
            Ok(())
        }
        _ => {
            eprintln!("Unknown command: {}", command);
            print_usage();
            process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        process::exit(1);
    }
}

async fn deploy_command(args: &[String]) -> mustfile_orchestrator::Result<()> {
    let mustfile_path = args.first()
        .map(|s| s.as_str())
        .unwrap_or("./Mustfile");

    println!("🚀 Starting deployment from: {}", mustfile_path);
    orchestrate(mustfile_path).await?;
    Ok(())
}

fn validate_command(args: &[String]) -> mustfile_orchestrator::Result<()> {
    let mustfile_path = args.first()
        .map(|s| s.as_str())
        .unwrap_or("./Mustfile");

    println!("Validating Mustfile: {}", mustfile_path);

    let mustfile = MustfileParser::parse_file(mustfile_path)?;

    println!("✓ Syntax valid");
    println!("  Project: {} v{}", mustfile.project.name, mustfile.project.version);
    println!("  Tasks: {}", mustfile.tasks.len());

    // Validate requirements
    mustfile.validate_requirements()?;
    println!("✓ Requirements met");

    println!("\n✅ Mustfile is valid");
    Ok(())
}

fn info_command() -> mustfile_orchestrator::Result<()> {
    println!("Platform Information:");

    let platform = PlatformAdapter::detect()?;

    println!("  OS: {}", platform.os);
    println!("  Architecture: {}", platform.arch);
    println!("  Target Type: {:?}", platform.target_type);
    println!("  Immutable: {}", platform.is_immutable);
    println!("  Package Manager: {}", platform.package_manager());
    println!("  Deployment Priority: {}", platform.deployment_priority);

    Ok(())
}

fn print_usage() {
    println!(r#"mustorch - Mustfile Orchestrator CLI

USAGE:
    mustorch <COMMAND> [OPTIONS]

COMMANDS:
    deploy [PATH]     Deploy a Mustfile (default: ./Mustfile)
    validate [PATH]   Validate a Mustfile (default: ./Mustfile)
    info              Show platform detection information
    help              Show this help message

EXAMPLES:
    mustorch deploy
    mustorch deploy ./my-project/Mustfile
    mustorch validate
    mustorch info

INTEGRATION:
    mustorch bridges nicaug (platform detection) with the must binary
    (deployment execution) to provide unified orchestration.

RELATIONSHIP:
    mustorch:Mustfile :: just:Justfile
    (orchestrator reads specification and executes it)
"#);
}
