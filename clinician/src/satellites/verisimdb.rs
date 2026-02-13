// SPDX-License-Identifier: PMPL-1.0-or-later
//! verisimdb integration — similarity database for security patterns
//!
//! Invokes ingest-scan.sh and verisim-query CLI for VQL queries.

use anyhow::{bail, Result};

/// Ingest a scan result into verisimdb
pub async fn ingest(repo: &str, scan_path: &str) -> Result<()> {
    println!("Ingesting scan for '{}' into verisimdb...", repo);
    println!("{}", "-".repeat(50));

    // Check if verisimdb-data repo with ingest script exists
    let script = find_ingest_script().await;

    match script {
        Some(script_path) => {
            let result = tokio::process::Command::new("bash")
                .args([&script_path, repo, scan_path])
                .output()
                .await?;

            if result.status.success() {
                let stdout = String::from_utf8_lossy(&result.stdout);
                println!("  Ingestion successful.");
                if !stdout.is_empty() {
                    println!("{}", stdout);
                }
            } else {
                let stderr = String::from_utf8_lossy(&result.stderr);
                bail!("Ingestion failed: {}", stderr);
            }
        }
        None => {
            println!("  verisimdb-data ingest script not found.");
            println!("  Expected at: ~/Documents/hyperpolymath-repos/verisimdb-data/scripts/ingest-scan.sh");
            println!("  Clone: git clone https://github.com/hyperpolymath/verisimdb-data");
        }
    }

    Ok(())
}

/// Query verisimdb with VQL
pub async fn query(vql: &str) -> Result<()> {
    println!("Querying verisimdb: {}", vql);
    println!("{}", "-".repeat(50));

    // Check for verisim-query CLI
    let which = tokio::process::Command::new("which")
        .arg("verisim-query")
        .output()
        .await;

    match which {
        Ok(w) if w.status.success() => {
            let result = tokio::process::Command::new("verisim-query")
                .args(["--vql", vql])
                .output()
                .await?;

            if result.status.success() {
                let stdout = String::from_utf8_lossy(&result.stdout);
                println!("{}", stdout);
            } else {
                let stderr = String::from_utf8_lossy(&result.stderr);
                println!("  Query failed: {}", stderr);
            }
        }
        _ => {
            println!("  verisim-query not found in PATH.");
            println!("  Build: cd ~/Documents/hyperpolymath-repos/verisimdb && cargo build -p verisim-api");
            println!("\n  Alternative: query verisimdb-data git repo directly:");
            println!("    ls ~/Documents/hyperpolymath-repos/verisimdb-data/scans/");
        }
    }

    Ok(())
}

async fn find_ingest_script() -> Option<String> {
    let paths = [
        format!(
            "{}/Documents/hyperpolymath-repos/verisimdb-data/scripts/ingest-scan.sh",
            std::env::var("HOME").unwrap_or_default()
        ),
        "/var/mnt/eclipse/repos/verisimdb-data/scripts/ingest-scan.sh".to_string(),
    ];

    for path in &paths {
        if tokio::fs::metadata(path).await.is_ok() {
            return Some(path.clone());
        }
    }

    None
}
