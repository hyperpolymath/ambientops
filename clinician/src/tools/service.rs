// SPDX-License-Identifier: PMPL-1.0-or-later
//! Service management tools (like Autoruns)
//!
//! Security: All user-supplied service names are validated before use

use anyhow::Result;
use crate::storage::Storage;
use crate::cache::Cache;
use crate::validation::validate_service_name;

/// Service action types
#[derive(Debug, Clone)]
pub enum ServiceAction {
    List { failed: bool },
    Status { name: String },
    Startup,
    Deps { name: String },
}

pub async fn handle(action: ServiceAction, _storage: &Storage, _cache: &Cache) -> Result<()> {
    match action {
        ServiceAction::List { failed } => list_services(failed).await?,
        ServiceAction::Status { name } => show_status(&name).await?,
        ServiceAction::Startup => list_startup().await?,
        ServiceAction::Deps { name } => show_deps(&name).await?,
    }
    Ok(())
}

async fn list_services(failed_only: bool) -> Result<()> {
    let args = if failed_only {
        vec!["--user", "--failed"]
    } else {
        vec!["--user", "list-units", "--type=service"]
    };

    let output = tokio::process::Command::new("systemctl")
        .args(&args)
        .output()
        .await?;

    println!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

async fn show_status(name: &str) -> Result<()> {
    // SECURITY: Validate service name to prevent command injection
    let safe_name = validate_service_name(name)
        .map_err(|e| anyhow::anyhow!("Invalid service name: {}", e))?;

    let output = tokio::process::Command::new("systemctl")
        .args(["--user", "status", safe_name])
        .output()
        .await?;

    println!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

async fn list_startup() -> Result<()> {
    println!("Startup items (Autoruns equivalent):");
    println!("{}", "=".repeat(50));

    // XDG autostart
    println!("\n[XDG Autostart]");
    for dir in &[
        "/etc/xdg/autostart",
        &format!("{}/.config/autostart", std::env::var("HOME").unwrap_or_default()),
    ] {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                println!("  {}", entry.path().display());
            }
        }
    }

    // Systemd user units
    println!("\n[Systemd User Units]");
    let output = tokio::process::Command::new("systemctl")
        .args(["--user", "list-unit-files", "--state=enabled"])
        .output()
        .await?;
    println!("{}", String::from_utf8_lossy(&output.stdout));

    // Profile scripts
    println!("\n[Shell Profile Scripts]");
    let home = std::env::var("HOME").unwrap_or_default();
    for script in &[
        format!("{}/.profile", home),
        format!("{}/.bashrc", home),
        format!("{}/.bash_profile", home),
        format!("{}/.zshrc", home),
    ] {
        if std::path::Path::new(script).exists() {
            println!("  {} (exists)", script);
        }
    }

    Ok(())
}

async fn show_deps(name: &str) -> Result<()> {
    // SECURITY: Validate service name to prevent command injection
    let safe_name = validate_service_name(name)
        .map_err(|e| anyhow::anyhow!("Invalid service name: {}", e))?;

    println!("Dependencies for {}:", safe_name);

    let output = tokio::process::Command::new("systemctl")
        .args(["--user", "list-dependencies", safe_name])
        .output()
        .await?;

    println!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}
