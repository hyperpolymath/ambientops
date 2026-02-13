// SPDX-License-Identifier: PMPL-1.0-or-later
//! hypatia + gitbot-fleet integration
//!
//! Thin wrappers around hypatia's neurosymbolic pattern matching
//! and gitbot-fleet bot status checks.

use anyhow::Result;
use super::{FleetStatus, BotStatus};

/// Trigger hypatia pattern matching for a given pattern
pub async fn dispatch(pattern: &str) -> Result<()> {
    println!("Dispatching to hypatia: {}", pattern);
    println!("{}", "-".repeat(50));

    // Check if mix is available and hypatia is local
    let hypatia_path = find_hypatia().await;

    match hypatia_path {
        Some(path) => {
            let result = tokio::process::Command::new("mix")
                .args(["run", "-e", &format!("Hypatia.dispatch(\"{}\")", pattern)])
                .current_dir(&path)
                .output()
                .await?;

            if result.status.success() {
                let stdout = String::from_utf8_lossy(&result.stdout);
                println!("{}", stdout);
            } else {
                let stderr = String::from_utf8_lossy(&result.stderr);
                println!("  Dispatch failed: {}", stderr);
            }
        }
        None => {
            println!("  Hypatia not found locally.");
            println!("  Expected at: ~/Documents/hyperpolymath-repos/hypatia");
            println!("  Clone: git clone https://github.com/hyperpolymath/hypatia");
        }
    }

    Ok(())
}

/// Check gitbot-fleet status
pub async fn fleet_status() -> Result<()> {
    println!("Gitbot Fleet Status");
    println!("{}", "=".repeat(50));

    // Known bots in the fleet
    let known_bots = [
        "rhodibot",
        "echidnabot",
        "sustainabot",
        "glambot",
        "seambot",
        "finishbot",
    ];

    // Check if gh CLI is available for fleet status via GitHub Actions
    let gh_check = tokio::process::Command::new("which")
        .arg("gh")
        .output()
        .await;

    let has_gh = matches!(gh_check, Ok(w) if w.status.success());

    let mut bots: Vec<BotStatus> = Vec::new();
    let mut active_count = 0;

    for bot_name in &known_bots {
        let status = if has_gh {
            check_bot_via_gh(bot_name).await
        } else {
            "unknown (gh CLI not available)".to_string()
        };

        let is_active = status.contains("active") || status.contains("running");
        if is_active {
            active_count += 1;
        }

        bots.push(BotStatus {
            name: bot_name.to_string(),
            status: status.clone(),
            last_run: None,
        });

        println!("  {:12} — {}", bot_name, status);
    }

    println!("\n  Active: {}/{}", active_count, known_bots.len());

    let fleet = FleetStatus {
        bots,
        total_active: active_count,
    };

    tracing::debug!("Fleet status: {:?}", fleet);

    Ok(())
}

async fn check_bot_via_gh(bot_name: &str) -> String {
    let result = tokio::process::Command::new("gh")
        .args([
            "api",
            &format!("repos/hyperpolymath/gitbot-fleet/actions/workflows/{}.yml/runs", bot_name),
            "--jq",
            ".workflow_runs[0].status",
        ])
        .output()
        .await;

    match result {
        Ok(output) if output.status.success() => {
            let status = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if status.is_empty() {
                "no runs found".to_string()
            } else {
                status
            }
        }
        _ => "unavailable".to_string(),
    }
}

async fn find_hypatia() -> Option<String> {
    let paths = [
        format!(
            "{}/Documents/hyperpolymath-repos/hypatia",
            std::env::var("HOME").unwrap_or_default()
        ),
        "/var/mnt/eclipse/repos/hypatia".to_string(),
    ];

    for path in &paths {
        let mix_path = format!("{}/mix.exs", path);
        if tokio::fs::metadata(&mix_path).await.is_ok() {
            return Some(path.clone());
        }
    }

    None
}
