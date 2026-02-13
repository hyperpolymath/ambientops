// SPDX-License-Identifier: PMPL-1.0-or-later
//! Pack Manifest - diagnostic/maintenance pack definitions.

use serde::{Deserialize, Serialize};

/// Definition of a diagnostic/maintenance pack.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackManifest {
    pub version: String,
    pub pack_id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub platform: PackPlatform,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<PackAuthor>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub license: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repository: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub categories: Vec<PackCategory>,
    pub checks: Vec<PackCheck>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<PackAction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub modes: Option<PackModes>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ui: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependencies: Vec<PackDependency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub claims: Option<PackClaims>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackPlatform {
    pub os: Vec<PackOs>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub os_version_min: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub os_version_max: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub arch: Vec<PackArch>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PackOs {
    Windows,
    Linux,
    Macos,
    Bsd,
    Any,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PackArch {
    X86_64,
    Aarch64,
    X86,
    Arm,
    Any,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackAuthor {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PackCategory {
    Disk,
    Memory,
    Cpu,
    Network,
    Security,
    Privacy,
    Startup,
    Services,
    Updates,
    Drivers,
    Performance,
    Cleanup,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackCheck {
    pub check_id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub category: PackCategory,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub severity_if_found: Option<CheckSeverity>,
    #[serde(default = "default_true")]
    pub enabled_by_default: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requires_privileges: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub estimated_duration_seconds: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub implementation: Option<String>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckSeverity {
    Info,
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackAction {
    pub action_id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub risk: ActionRisk,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reversibility: Option<ActionReversibility>,
    #[serde(default = "default_true")]
    pub requires_confirmation: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub addresses_checks: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub implementation: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ActionRisk {
    Safe,
    Guided,
    Expert,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ActionReversibility {
    Full,
    Partial,
    None,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackModes {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quick: Option<PackMode>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub standard: Option<PackMode>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deep: Option<PackMode>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub custom: Vec<PackMode>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackMode {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub enabled_checks: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub disabled_checks: Vec<String>,
    #[serde(default)]
    pub auto_apply: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackDependency {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pack_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version_min: Option<String>,
    #[serde(default)]
    pub optional: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackClaims {
    #[serde(default = "default_true")]
    pub no_fake_counts: bool,
    #[serde(default = "default_true")]
    pub evidence_backed: bool,
    #[serde(default = "default_true")]
    pub user_controlled: bool,
    #[serde(default)]
    pub fully_reversible: bool,
    #[serde(default = "default_true")]
    pub open_source: bool,
}

impl PackManifest {
    /// Create a minimal pack manifest.
    pub fn new(pack_id: &str, name: &str, os: Vec<PackOs>) -> Self {
        Self {
            version: "1.0.0".to_string(),
            pack_id: pack_id.to_string(),
            name: name.to_string(),
            description: None,
            platform: PackPlatform {
                os,
                os_version_min: None,
                os_version_max: None,
                arch: Vec::new(),
            },
            author: None,
            license: None,
            repository: None,
            categories: Vec::new(),
            checks: Vec::new(),
            actions: Vec::new(),
            modes: None,
            ui: None,
            dependencies: Vec::new(),
            claims: Some(PackClaims {
                no_fake_counts: true,
                evidence_backed: true,
                user_controlled: true,
                fully_reversible: false,
                open_source: true,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pack_manifest_roundtrip() {
        let mut pack = PackManifest::new("linux-crash-team", "Linux Crash Team Pack", vec![PackOs::Linux]);
        pack.checks.push(PackCheck {
            check_id: "zombie-device".to_string(),
            name: "Zombie PCI Device Check".to_string(),
            description: Some("Detect PCI devices in D0 with no driver".to_string()),
            category: PackCategory::Drivers,
            severity_if_found: Some(CheckSeverity::High),
            enabled_by_default: true,
            requires_privileges: vec!["root".to_string()],
            estimated_duration_seconds: Some(5),
            implementation: None,
        });

        let json = serde_json::to_string_pretty(&pack).unwrap();
        assert!(json.contains("linux-crash-team"));

        let parsed: PackManifest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.pack_id, "linux-crash-team");
        assert_eq!(parsed.checks.len(), 1);
    }

    #[test]
    fn test_pack_claims_defaults() {
        let claims = PackClaims {
            no_fake_counts: true,
            evidence_backed: true,
            user_controlled: true,
            fully_reversible: false,
            open_source: true,
        };
        let json = serde_json::to_string(&claims).unwrap();
        let parsed: PackClaims = serde_json::from_str(&json).unwrap();
        assert!(parsed.no_fake_counts);
        assert!(!parsed.fully_reversible);
    }
}
