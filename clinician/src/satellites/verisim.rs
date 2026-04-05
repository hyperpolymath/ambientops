// SPDX-License-Identifier: PMPL-1.0-or-later
//! verisim integration — similarity database for security patterns
//!
//! Invokes ingest-scan.sh and verisim-query CLI for VCL queries.

use anyhow::{bail, Result};

/// Ingest a scan result into verisim
pub async fn ingest(repo: &str, scan_path: &str) -> Result<()> {
    println!("Ingesting scan for '{}' into verisim...", repo);
    println!("{}", "-".repeat(50));

    // Check if verisim-data repo with ingest script exists
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
            println!("  verisim-data ingest script not found.");
            println!("  Expected at: ~/Documents/hyperpolymath-repos/verisim-data/scripts/ingest-scan.sh");
            println!("  Clone: git clone https://github.com/hyperpolymath/verisimdb-data");
        }
    }

    Ok(())
}

/// Query verisim with VCL
pub async fn query(vcl: &str) -> Result<()> {
    println!("Querying verisim: {}", vcl);
    println!("{}", "-".repeat(50));

    // Check for verisim-query CLI
    let which = tokio::process::Command::new("which")
        .arg("verisim-query")
        .output()
        .await;

    match which {
        Ok(w) if w.status.success() => {
            let result = tokio::process::Command::new("verisim-query")
                .args(["--vcl", vcl])
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
            println!("  Build: cd ~/Documents/hyperpolymath-repos/verisim && cargo build -p verisim-api");
            println!("\n  Alternative: query verisim-data git repo directly:");
            println!("    ls ~/Documents/hyperpolymath-repos/verisim-data/scans/");
        }
    }

    Ok(())
}

async fn find_ingest_script() -> Option<String> {
    let repos_dir = std::env::var("AMBIENTOPS_REPOS_DIR")
        .or_else(|_| std::env::var("HOME").map(|h| format!("{h}/Documents/hyperpolymath-repos")))
        .unwrap_or_default();
    let paths = [
        format!("{repos_dir}/verisim-data/scripts/ingest-scan.sh"),
    ];

    for path in &paths {
        if tokio::fs::metadata(path).await.is_ok() {
            return Some(path.clone());
        }
    }

    None
}
