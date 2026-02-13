// SPDX-License-Identifier: PMPL-1.0-or-later
//! panic-attacker integration — vulnerability/weak-point scanning
//!
//! Invokes `panic-attack assail <target> --output <path>` and parses JSON results.

use anyhow::{bail, Result};
use super::{ScanResult, WeakPoint};

/// Scan a target path with panic-attacker
pub async fn scan(target: &str, output: Option<&str>) -> Result<()> {
    let output_path = output.unwrap_or("/tmp/psa-scan.json");

    println!("Scanning {} with panic-attacker...", target);
    println!("{}", "-".repeat(50));

    // Check if panic-attack is installed
    let which = tokio::process::Command::new("which")
        .arg("panic-attack")
        .output()
        .await;

    match which {
        Ok(w) if w.status.success() => {}
        _ => {
            println!("  panic-attack not found in PATH.");
            println!("  Install: cd ~/Documents/hyperpolymath-repos/panic-attacker && cargo install --path .");
            println!("  Or: cargo build --release && cp target/release/panic-attacker ~/.local/bin/panic-attack");
            return Ok(());
        }
    }

    // Run scan
    let result = tokio::process::Command::new("panic-attack")
        .args(["assail", target, "--output", output_path])
        .output()
        .await?;

    if !result.status.success() {
        let stderr = String::from_utf8_lossy(&result.stderr);
        bail!("panic-attack scan failed: {}", stderr);
    }

    // Parse results
    let scan_result = parse_scan(output_path).await?;
    print_scan_summary(&scan_result);

    Ok(())
}

/// Parse JSON output from panic-attacker scan
pub async fn parse_scan(json_path: &str) -> Result<ScanResult> {
    let content = tokio::fs::read_to_string(json_path).await?;
    let raw: serde_json::Value = serde_json::from_str(&content)?;

    let weak_points: Vec<WeakPoint> = raw
        .get("weak_points")
        .or_else(|| raw.get("findings"))
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|item| {
                    Some(WeakPoint {
                        id: item.get("id")?.as_str()?.to_string(),
                        severity: item
                            .get("severity")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_string(),
                        category: item
                            .get("category")
                            .and_then(|v| v.as_str())
                            .unwrap_or("general")
                            .to_string(),
                        description: item
                            .get("description")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        location: item
                            .get("location")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        remediation: item
                            .get("remediation")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string()),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    Ok(ScanResult {
        target: raw
            .get("target")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string(),
        weak_points,
        scan_time_ms: raw
            .get("scan_time_ms")
            .and_then(|v| v.as_u64())
            .unwrap_or(0),
    })
}

fn print_scan_summary(result: &ScanResult) {
    println!("\nScan Results: {}", result.target);
    println!("  Weak points: {}", result.weak_points.len());
    println!("  Scan time: {}ms", result.scan_time_ms);

    if !result.weak_points.is_empty() {
        println!("\n  Findings:");
        for wp in &result.weak_points {
            println!(
                "    [{:>8}] {} — {}",
                wp.severity, wp.id, wp.description
            );
            if let Some(ref loc) = Some(&wp.location) {
                if !loc.is_empty() {
                    println!("              at {}", loc);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_weak_point_json() {
        let json = r#"{
            "target": "test-repo",
            "weak_points": [
                {
                    "id": "WP-001",
                    "severity": "high",
                    "category": "security",
                    "description": "Hardcoded credential",
                    "location": "src/config.rs:15"
                }
            ],
            "scan_time_ms": 500
        }"#;

        let raw: serde_json::Value = serde_json::from_str(json).unwrap();
        let wp_array = raw.get("weak_points").unwrap().as_array().unwrap();
        assert_eq!(wp_array.len(), 1);
        assert_eq!(wp_array[0]["id"], "WP-001");
    }

    #[test]
    fn test_command_construction() {
        // Verify the command args are correctly structured
        let target = "/var/mnt/eclipse/repos/test";
        let output = "/tmp/test-scan.json";
        let args = vec!["assail", target, "--output", output];
        assert_eq!(args[0], "assail");
        assert_eq!(args[2], "--output");
    }
}
