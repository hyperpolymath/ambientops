// SPDX-License-Identifier: PMPL-1.0-or-later
//! Satellite tool integration for the AmbientOps ecosystem
//!
//! Provides CLI wrappers for external AmbientOps tools:
//! - panic-attacker: Vulnerability/weak-point scanning
//! - verisimdb: Similarity database for security patterns
//! - hypatia: Neurosymbolic pattern matching
//! - echidna: Formal verification of procedure reversibility

pub mod panic_attacker;
pub mod verisimdb;
pub mod hypatia;
pub mod echidna;

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// Satellite action types
#[derive(Debug, Clone)]
pub enum SatelliteAction {
    /// Scan a target with panic-attacker
    Scan { target: String, output: Option<String> },
    /// Ingest scan results into verisimdb
    Ingest { repo: String, scan_path: String },
    /// Query verisimdb with VQL
    Query { vql: String },
    /// Verify procedure reversibility with echidna
    Verify { procedure_path: String },
    /// Check gitbot-fleet status
    FleetStatus,
}

/// Handle satellite subcommands
pub async fn handle(action: SatelliteAction) -> Result<()> {
    match action {
        SatelliteAction::Scan { target, output } => {
            panic_attacker::scan(&target, output.as_deref()).await?;
        }
        SatelliteAction::Ingest { repo, scan_path } => {
            verisimdb::ingest(&repo, &scan_path).await?;
        }
        SatelliteAction::Query { vql } => {
            verisimdb::query(&vql).await?;
        }
        SatelliteAction::Verify { procedure_path } => {
            echidna::verify(&procedure_path).await?;
        }
        SatelliteAction::FleetStatus => {
            hypatia::fleet_status().await?;
        }
    }
    Ok(())
}

/// Result from a panic-attacker scan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanResult {
    pub target: String,
    pub weak_points: Vec<WeakPoint>,
    pub scan_time_ms: u64,
}

/// A single weak point from panic-attacker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeakPoint {
    pub id: String,
    pub severity: String,
    pub category: String,
    pub description: String,
    pub location: String,
    pub remediation: Option<String>,
}

/// Result from echidna verification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    pub procedure: String,
    pub reversible: bool,
    pub proof_status: String,
    pub details: Vec<String>,
}

/// Status of gitbot-fleet bots
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FleetStatus {
    pub bots: Vec<BotStatus>,
    pub total_active: usize,
}

/// Individual bot status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BotStatus {
    pub name: String,
    pub status: String,
    pub last_run: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_weak_point_deserialize() {
        let json = r#"{
            "id": "WP-001",
            "severity": "medium",
            "category": "config",
            "description": "Missing HTTPS redirect",
            "location": "nginx.conf:42",
            "remediation": "Add return 301 https://$host$request_uri;"
        }"#;
        let wp: WeakPoint = serde_json::from_str(json).unwrap();
        assert_eq!(wp.id, "WP-001");
        assert_eq!(wp.severity, "medium");
        assert!(wp.remediation.is_some());
    }

    #[test]
    fn test_scan_result_deserialize() {
        let json = r#"{
            "target": "/var/mnt/eclipse/repos/echidna",
            "weak_points": [],
            "scan_time_ms": 1234
        }"#;
        let result: ScanResult = serde_json::from_str(json).unwrap();
        assert_eq!(result.target, "/var/mnt/eclipse/repos/echidna");
        assert!(result.weak_points.is_empty());
    }

    #[test]
    fn test_verification_result_serialize() {
        let result = VerificationResult {
            procedure: "power-off".to_string(),
            reversible: true,
            proof_status: "proven".to_string(),
            details: vec!["Step 1 invertible".to_string()],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("\"reversible\":true"));
    }
}
