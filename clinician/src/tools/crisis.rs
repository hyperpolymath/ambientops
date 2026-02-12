// SPDX-License-Identifier: PMPL-1.0-or-later
//! Crisis mode - analyze incident bundles from system-emergency-room
//!
//! Integration with system-emergency-room for escalated diagnostics.
//! Reads incident bundles, analyzes captured logs, and provides
//! AI-assisted recommendations.
//!
//! Security: All paths are validated before use.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::cache::Cache;
use crate::correlation;
use crate::storage::Storage;
use crate::validation::validate_safe_path;

use ambientops_contracts::EvidenceEnvelope;

/// Incident envelope from system-emergency-room
/// Some fields are kept for JSON schema compatibility even if not currently used
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct IncidentEnvelope {
    schema_version: String,
    id: String,
    correlation_id: String,
    created_at: String,
    hostname: String,
    username: String,
    working_dir: String,
    platform: PlatformInfo,
    trigger: TriggerInfo,
    commands: Vec<CommandLog>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct PlatformInfo {
    os: String,
    arch: String,
    kernel: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct TriggerInfo {
    version: String,
    dry_run: bool,
    args: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct CommandLog {
    name: String,
    command: String,
    started_at: String,
    ended_at: String,
    exit_code: i32,
    output_len: i32,
}

/// Crisis analysis result (used for future API responses)
#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub struct CrisisAnalysis {
    pub incident_id: String,
    pub correlation_id: String,
    pub severity: CrisisSeverity,
    pub findings: Vec<Finding>,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub enum CrisisSeverity {
    Critical,
    High,
    Medium,
    Low,
    Unknown,
}

#[derive(Debug, Serialize)]
pub struct Finding {
    pub category: String,
    pub description: String,
    pub evidence: String,
    pub severity: CrisisSeverity,
}

/// Analyze an incident bundle from system-emergency-room
pub async fn analyze(
    incident_path: &str,
    correlation_id: Option<&str>,
    _storage: &Storage,
    _cache: &Cache,
) -> Result<()> {
    // SECURITY: Validate incident path
    let safe_path = validate_safe_path(incident_path)
        .map_err(|e| anyhow::anyhow!("Invalid incident path: {}", e))?;

    println!("Crisis Mode Analysis");
    println!("{}", "=".repeat(50));
    println!();

    // Check if incident directory exists
    let incident_dir = Path::new(safe_path);
    if !incident_dir.exists() {
        return Err(anyhow::anyhow!(
            "Incident directory not found: {}",
            safe_path
        ));
    }

    // Read incident.json
    let incident_json_path = incident_dir.join("incident.json");
    if !incident_json_path.exists() {
        return Err(anyhow::anyhow!(
            "incident.json not found in bundle: {}",
            incident_json_path.display()
        ));
    }

    let incident_content = std::fs::read_to_string(&incident_json_path)?;
    let envelope: IncidentEnvelope = serde_json::from_str(&incident_content)?;

    // Use: command-line arg > global correlation ID > envelope's ID
    let corr_id: &str = match correlation_id {
        Some(id) => id,
        None => correlation::get().unwrap_or(&envelope.correlation_id),
    };

    println!("[Incident Info]");
    println!("  ID:             {}", envelope.id);
    println!("  Correlation ID: {}", corr_id);
    println!("  Created:        {}", envelope.created_at);
    println!("  Hostname:       {}", envelope.hostname);
    println!("  Platform:       {} ({})", envelope.platform.os, envelope.platform.arch);
    println!("  Kernel:         {}", envelope.platform.kernel);
    println!();

    // Analyze captured command outputs
    println!("[Command Analysis]");
    let mut failed_commands = Vec::new();

    for cmd in &envelope.commands {
        let status = if cmd.exit_code == 0 { "OK" } else { "FAIL" };
        println!("  {} [{}]: {}", cmd.name, status, cmd.command);

        if cmd.exit_code != 0 {
            failed_commands.push(cmd);
        }
    }
    println!();

    // Read and analyze logs
    let logs_dir = incident_dir.join("logs");
    if logs_dir.exists() {
        println!("[Log Analysis]");
        analyze_logs(&logs_dir).await?;
        println!();
    }

    // Generate findings and recommendations
    println!("[Findings]");
    let findings = generate_findings(&envelope, &failed_commands);
    for finding in &findings {
        println!("  [{:?}] {}: {}", finding.severity, finding.category, finding.description);
    }
    println!();

    println!("[Recommendations]");
    let recommendations = generate_recommendations(&findings);
    for (i, rec) in recommendations.iter().enumerate() {
        println!("  {}. {}", i + 1, rec);
    }
    println!();

    // Summary
    let severity = determine_overall_severity(&findings);
    println!("[Summary]");
    println!("  Overall Severity: {:?}", severity);
    println!("  Total Findings:   {}", findings.len());
    println!("  Failed Commands:  {}", failed_commands.len());
    println!();

    // Suggest next steps based on severity
    match severity {
        CrisisSeverity::Critical => {
            println!("[!] CRITICAL: Immediate action required!");
            println!("    Consider escalating to system-operating-theatre for surgical intervention.");
        }
        CrisisSeverity::High => {
            println!("[!] HIGH: Prompt attention needed.");
            println!("    Review recommendations and apply fixes systematically.");
        }
        _ => {
            println!("[*] Situation appears manageable.");
            println!("    Follow recommendations to resolve issues.");
        }
    }

    Ok(())
}

async fn analyze_logs(logs_dir: &Path) -> Result<()> {
    let entries = std::fs::read_dir(logs_dir)?;

    for entry in entries {
        let entry = entry?;
        let path = entry.path();

        if path.is_file() {
            let filename = path.file_name().unwrap_or_default().to_string_lossy();
            let size = std::fs::metadata(&path)?.len();
            println!("  {} ({} bytes)", filename, size);

            // Check for common error patterns in log content
            if let Ok(content) = std::fs::read_to_string(&path) {
                let error_count = content.matches("error").count()
                    + content.matches("Error").count()
                    + content.matches("ERROR").count();
                let warning_count = content.matches("warning").count()
                    + content.matches("Warning").count()
                    + content.matches("WARN").count();

                if error_count > 0 || warning_count > 0 {
                    println!("    -> {} errors, {} warnings detected", error_count, warning_count);
                }
            }
        }
    }

    Ok(())
}

fn generate_findings(envelope: &IncidentEnvelope, failed_commands: &[&CommandLog]) -> Vec<Finding> {
    let mut findings = Vec::new();

    // Failed commands indicate problems
    for cmd in failed_commands {
        findings.push(Finding {
            category: "Command Failure".to_string(),
            description: format!("{} exited with code {}", cmd.name, cmd.exit_code),
            evidence: cmd.command.clone(),
            severity: CrisisSeverity::Medium,
        });
    }

    // Check for known problematic patterns
    if envelope.platform.kernel.contains("DEBUG") {
        findings.push(Finding {
            category: "Kernel".to_string(),
            description: "Running debug kernel - may have performance issues".to_string(),
            evidence: envelope.platform.kernel.clone(),
            severity: CrisisSeverity::Low,
        });
    }

    findings
}

fn generate_recommendations(findings: &[Finding]) -> Vec<String> {
    let mut recommendations = Vec::new();

    for finding in findings {
        match finding.category.as_str() {
            "Command Failure" => {
                recommendations.push(format!(
                    "Investigate why '{}' failed - check logs for details",
                    finding.evidence
                ));
            }
            "Kernel" => {
                recommendations.push(
                    "Consider switching to production kernel for better performance".to_string(),
                );
            }
            _ => {
                recommendations.push(format!("Review: {}", finding.description));
            }
        }
    }

    if recommendations.is_empty() {
        recommendations.push("No immediate issues detected - continue monitoring".to_string());
    }

    recommendations
}

/// Analyze an EvidenceEnvelope from hardware-crash-team or other AmbientOps tools.
///
/// This is the contract-based intake path, complementing the legacy incident bundle path.
pub async fn analyze_envelope(
    envelope_path: &str,
    _storage: &Storage,
    _cache: &Cache,
) -> Result<()> {
    let safe_path = validate_safe_path(envelope_path)
        .map_err(|e| anyhow::anyhow!("Invalid envelope path: {}", e))?;

    let content = std::fs::read_to_string(safe_path)?;
    let envelope: EvidenceEnvelope = serde_json::from_str(&content)?;

    println!("Crisis Mode - Evidence Envelope Analysis");
    println!("{}", "=".repeat(50));
    println!();
    println!("[Envelope Info]");
    println!("  ID:        {}", envelope.envelope_id);
    println!("  Created:   {}", envelope.created_at);
    println!("  Host:      {}", envelope.source.host.hostname);
    println!("  Artifacts: {}", envelope.artifacts.len());
    println!("  Findings:  {}", envelope.findings.len());
    println!();

    if !envelope.findings.is_empty() {
        println!("[Findings from Evidence]");
        for finding in &envelope.findings {
            println!(
                "  [{:?}] {:?}: {}",
                finding.severity, finding.category, finding.title
            );
            if let Some(ref rec) = finding.recommendation {
                println!("    -> Recommendation: {}", rec);
            }
        }
        println!();
    }

    let severity = if envelope.findings.iter().any(|f| {
        matches!(
            f.severity,
            ambientops_contracts::envelope::FindingSeverity::Critical
        )
    }) {
        CrisisSeverity::Critical
    } else if envelope.findings.iter().any(|f| {
        matches!(
            f.severity,
            ambientops_contracts::envelope::FindingSeverity::High
        )
    }) {
        CrisisSeverity::High
    } else {
        CrisisSeverity::Medium
    };

    println!("[Summary]");
    println!("  Overall Severity: {:?}", severity);
    println!("  Auto-fixable: {}", envelope.findings.iter().filter(|f| f.auto_fixable).count());
    println!();

    match severity {
        CrisisSeverity::Critical => {
            println!("[!] CRITICAL: Immediate action required!");
            println!("    Consider escalating to Operating Theatre for surgical intervention.");
        }
        CrisisSeverity::High => {
            println!("[!] HIGH: Prompt attention needed.");
            println!("    Review findings and apply auto-fixable remediations.");
        }
        _ => {
            println!("[*] Situation appears manageable.");
        }
    }

    Ok(())
}

fn determine_overall_severity(findings: &[Finding]) -> CrisisSeverity {
    let mut max_severity = CrisisSeverity::Unknown;

    for finding in findings {
        max_severity = match (&max_severity, &finding.severity) {
            (_, CrisisSeverity::Critical) => CrisisSeverity::Critical,
            (CrisisSeverity::Critical, _) => CrisisSeverity::Critical,
            (_, CrisisSeverity::High) => CrisisSeverity::High,
            (CrisisSeverity::High, _) => CrisisSeverity::High,
            (_, CrisisSeverity::Medium) => CrisisSeverity::Medium,
            (CrisisSeverity::Medium, _) => CrisisSeverity::Medium,
            (_, CrisisSeverity::Low) => CrisisSeverity::Low,
            (CrisisSeverity::Low, _) => CrisisSeverity::Low,
            _ => CrisisSeverity::Unknown,
        };
    }

    max_severity
}
