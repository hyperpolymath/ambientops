// SPDX-License-Identifier: PMPL-1.0-or-later
//! Evidence Envelope - A&E intake and Operating Theatre scan output.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Core data contract for A&E intake and Operating Theatre scans.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidenceEnvelope {
    pub version: String,
    pub envelope_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub source: EnvelopeSource,
    pub artifacts: Vec<Artifact>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub findings: Vec<Finding>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metrics: Option<serde_json::Value>,
    #[serde(default = "default_redaction")]
    pub redaction_profile: RedactionProfile,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provenance: Option<Provenance>,
}

fn default_redaction() -> RedactionProfile {
    RedactionProfile::Standard
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvelopeSource {
    pub tool: SourceTool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_version: Option<String>,
    pub host: HostInfo,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pack: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SourceTool {
    BigUp,
    Ambient,
    AAndE,
    Sysobs,
    Psa,
    #[serde(rename = "hardware-crash-team")]
    HardwareCrashTeam,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostInfo {
    pub hostname: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub os: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub os_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub arch: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Artifact {
    pub artifact_id: Uuid,
    #[serde(rename = "type")]
    pub artifact_type: ArtifactType,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hash: Option<ArtifactHash>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ArtifactType {
    Snapshot,
    Log,
    Config,
    Metric,
    Screenshot,
    Report,
    Diff,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArtifactHash {
    pub algorithm: HashAlgorithm,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HashAlgorithm {
    Sha256,
    Sha384,
    Sha512,
    Blake3,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    pub finding_id: String,
    pub severity: FindingSeverity,
    pub category: FindingCategory,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub evidence_refs: Vec<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recommendation: Option<String>,
    #[serde(default)]
    pub auto_fixable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FindingSeverity {
    Info,
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FindingCategory {
    Disk,
    Memory,
    Cpu,
    Network,
    Security,
    Config,
    Performance,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RedactionProfile {
    None,
    Minimal,
    Standard,
    Maximum,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_envelope_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub signatures: Vec<Signature>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Signature {
    pub signer: String,
    pub algorithm: String,
    pub signature: String,
    pub timestamp: DateTime<Utc>,
}

impl EvidenceEnvelope {
    /// Create a new envelope with required fields.
    pub fn new(source: EnvelopeSource, artifacts: Vec<Artifact>) -> Self {
        Self {
            version: "1.0.0".to_string(),
            envelope_id: Uuid::new_v4(),
            created_at: Utc::now(),
            source,
            artifacts,
            findings: Vec::new(),
            metrics: None,
            redaction_profile: RedactionProfile::Standard,
            provenance: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_envelope_serialization() {
        let envelope = EvidenceEnvelope::new(
            EnvelopeSource {
                tool: SourceTool::HardwareCrashTeam,
                tool_version: Some("0.1.0".to_string()),
                host: HostInfo {
                    hostname: "test-host".to_string(),
                    os: Some("Linux".to_string()),
                    os_version: Some("6.18.8".to_string()),
                    arch: Some("x86_64".to_string()),
                },
                profile: Some("full".to_string()),
                pack: None,
            },
            vec![Artifact {
                artifact_id: Uuid::new_v4(),
                artifact_type: ArtifactType::Report,
                path: "scan-report.json".to_string(),
                hash: None,
                size_bytes: None,
                mime_type: Some("application/json".to_string()),
                description: Some("PCI device scan report".to_string()),
            }],
        );

        let json = serde_json::to_string_pretty(&envelope).unwrap();
        assert!(json.contains("hardware-crash-team"));
        assert!(json.contains("test-host"));

        // Round-trip
        let parsed: EvidenceEnvelope = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.envelope_id, envelope.envelope_id);
    }
}
