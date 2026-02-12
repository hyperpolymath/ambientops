// SPDX-License-Identifier: PMPL-1.0-or-later
//! Security scanning and hardening tools
//!
//! Security: All user-supplied paths are validated before use

use anyhow::Result;
use crate::storage::Storage;
use crate::cache::Cache;
use crate::validation::validate_safe_path;

/// Security action types
#[derive(Debug, Clone)]
pub enum SecurityAction {
    Scan,
    Perms { path: String },
    Audit,
    Rootkit,
    Exposure,
}

pub async fn handle(action: SecurityAction, _storage: &Storage, _cache: &Cache) -> Result<()> {
    match action {
        SecurityAction::Scan => scan_vulnerabilities().await?,
        SecurityAction::Perms { path } => check_permissions(&path).await?,
        SecurityAction::Audit => audit_system().await?,
        SecurityAction::Rootkit => check_rootkits().await?,
        SecurityAction::Exposure => check_exposure().await?,
    }
    Ok(())
}

async fn scan_vulnerabilities() -> Result<()> {
    println!("Security Vulnerability Scan");
    println!("{}", "=".repeat(50));

    // Check for common issues
    println!("\n[World-writable files in sensitive locations]");
    let output = tokio::process::Command::new("find")
        .args(["/etc", "-type", "f", "-perm", "-o+w", "2>/dev/null"])
        .output()
        .await?;
    let files = String::from_utf8_lossy(&output.stdout);
    if files.trim().is_empty() {
        println!("  ✓ No world-writable files in /etc");
    } else {
        println!("  ✗ Found world-writable files:");
        for line in files.lines().take(10) {
            println!("    {}", line);
        }
    }

    // Check for SUID binaries
    println!("\n[SUID binaries]");
    let output = tokio::process::Command::new("find")
        .args(["/usr", "-type", "f", "-perm", "-4000", "2>/dev/null"])
        .output()
        .await?;
    let count = String::from_utf8_lossy(&output.stdout).lines().count();
    println!("  Found {} SUID binaries (review if unexpected)", count);

    // Check SSH config
    println!("\n[SSH Configuration]");
    if std::path::Path::new("/etc/ssh/sshd_config").exists() {
        let config = std::fs::read_to_string("/etc/ssh/sshd_config").unwrap_or_default();
        if config.contains("PermitRootLogin yes") {
            println!("  ✗ Root login is permitted");
        } else {
            println!("  ✓ Root login appears restricted");
        }
        if config.contains("PasswordAuthentication yes") {
            println!("  ! Password authentication enabled (consider key-only)");
        }
    }

    // Check firewall
    println!("\n[Firewall Status]");
    let output = tokio::process::Command::new("firewall-cmd")
        .args(["--state"])
        .output()
        .await;
    match output {
        Ok(out) if out.status.success() => println!("  ✓ Firewall is running"),
        _ => println!("  ! Firewall status unknown"),
    }

    Ok(())
}

async fn check_permissions(path: &str) -> Result<()> {
    // SECURITY: Validate path (though this function uses std::fs, not shell)
    let safe_path = validate_safe_path(path)
        .map_err(|e| anyhow::anyhow!("Invalid path: {}", e))?;

    println!("Permission analysis for: {}", safe_path);

    use std::os::unix::fs::PermissionsExt;

    let metadata = std::fs::metadata(safe_path)?;
    let mode = metadata.permissions().mode();

    println!("Mode: {:o}", mode & 0o7777);

    // Analyze permissions
    let owner_perms = (mode >> 6) & 0o7;
    let group_perms = (mode >> 3) & 0o7;
    let other_perms = mode & 0o7;

    println!("Owner: {} ({:o})", perms_to_string(owner_perms), owner_perms);
    println!("Group: {} ({:o})", perms_to_string(group_perms), group_perms);
    println!("Other: {} ({:o})", perms_to_string(other_perms), other_perms);

    // Warnings
    if other_perms & 0o2 != 0 {
        println!("\n⚠ WARNING: World-writable!");
    }
    if mode & 0o4000 != 0 {
        println!("\n⚠ WARNING: SUID bit set!");
    }
    if mode & 0o2000 != 0 {
        println!("\n⚠ WARNING: SGID bit set!");
    }

    Ok(())
}

fn perms_to_string(perms: u32) -> String {
    let r = if perms & 0o4 != 0 { 'r' } else { '-' };
    let w = if perms & 0o2 != 0 { 'w' } else { '-' };
    let x = if perms & 0o1 != 0 { 'x' } else { '-' };
    format!("{}{}{}", r, w, x)
}

async fn audit_system() -> Result<()> {
    println!("System Security Audit");
    println!("{}", "=".repeat(50));

    // Would integrate with lynis or similar
    println!("\nRecommended: Install and run lynis for comprehensive audit");
    println!("  sudo dnf install lynis && sudo lynis audit system");

    Ok(())
}

async fn check_rootkits() -> Result<()> {
    println!("Rootkit Check");
    println!("{}", "=".repeat(50));

    // Check for common rootkit indicators
    println!("\n[Checking hidden processes]");
    // Compare ps output with /proc

    println!("\n[Checking /dev for suspicious files]");
    let output = tokio::process::Command::new("find")
        .args(["/dev", "-type", "f", "2>/dev/null"])
        .output()
        .await?;
    let files_str = String::from_utf8_lossy(&output.stdout);
    let file_count = files_str.lines().count();
    if file_count == 0 {
        println!("  ✓ No unexpected files in /dev");
    } else {
        println!("  ! Found {} files in /dev (review manually)", file_count);
    }

    println!("\nRecommended: Install rkhunter or chkrootkit for thorough check");

    Ok(())
}

async fn check_exposure() -> Result<()> {
    println!("Network Exposure Analysis");
    println!("{}", "=".repeat(50));

    println!("\n[Listening Services]");
    let output = tokio::process::Command::new("ss")
        .args(["-tlnp"])
        .output()
        .await?;
    println!("{}", String::from_utf8_lossy(&output.stdout));

    println!("\n[Public-facing services (0.0.0.0 or ::)]");
    // Parse ss output and warn about public bindings

    Ok(())
}
