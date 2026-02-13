// SPDX-License-Identifier: PMPL-1.0-or-later
//! Run Bundle Layout - folder conventions for any run.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Folder conventions for any run: stable filenames, directory structure,
/// cross-platform naming rules.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunBundle {
    pub version: String,
    pub bundle_id: Uuid,
    pub created_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_tool: Option<BundleSourceTool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bundle_type: Option<BundleType>,
    pub layout: BundleLayout,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub naming_rules: Option<NamingRules>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub contents: Vec<BundleContent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retention: Option<BundleRetention>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub integrity: Option<BundleIntegrity>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum BundleSourceTool {
    BigUp,
    Ambient,
    AAndE,
    Sysobs,
    Psa,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BundleType {
    Scan,
    Plan,
    Execution,
    Export,
    Archive,
}

/// Directory structure specification.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleLayout {
    #[serde(default = "default_root_pattern")]
    pub root_dir_pattern: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub directories: Option<BundleDirectories>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub files: Option<BundleFiles>,
}

fn default_root_pattern() -> String {
    "{tool}-{timestamp}-{short_id}".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleDirectories {
    #[serde(default = "default_snapshots")]
    pub snapshots: String,
    #[serde(default = "default_logs")]
    pub logs: String,
    #[serde(default = "default_diffs")]
    pub diffs: String,
    #[serde(default = "default_exports")]
    pub exports: String,
    #[serde(default = "default_undo")]
    pub undo: String,
    #[serde(default = "default_temp")]
    pub temp: String,
}

fn default_snapshots() -> String { "snapshots/".to_string() }
fn default_logs() -> String { "logs/".to_string() }
fn default_diffs() -> String { "diffs/".to_string() }
fn default_exports() -> String { "exports/".to_string() }
fn default_undo() -> String { "undo/".to_string() }
fn default_temp() -> String { ".temp/".to_string() }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleFiles {
    #[serde(default = "default_manifest")]
    pub manifest: String,
    #[serde(default = "default_envelope")]
    pub envelope: String,
    #[serde(default = "default_plan")]
    pub plan: String,
    #[serde(default = "default_receipt")]
    pub receipt: String,
    #[serde(default = "default_receipt_human")]
    pub receipt_human: String,
    #[serde(default = "default_summary")]
    pub summary: String,
}

fn default_manifest() -> String { "manifest.json".to_string() }
fn default_envelope() -> String { "envelope.json".to_string() }
fn default_plan() -> String { "plan.json".to_string() }
fn default_receipt() -> String { "receipt.json".to_string() }
fn default_receipt_human() -> String { "receipt.txt".to_string() }
fn default_summary() -> String { "SUMMARY.md".to_string() }

/// Cross-platform file naming rules.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamingRules {
    #[serde(default = "default_max_filename")]
    pub max_filename_length: u32,
    #[serde(default = "default_max_path")]
    pub max_path_length: u32,
    #[serde(default = "default_allowed_chars")]
    pub allowed_chars: String,
    #[serde(default = "default_timestamp_format")]
    pub timestamp_format: String,
    #[serde(default = "default_reserved_names")]
    pub reserved_names: Vec<String>,
}

fn default_max_filename() -> u32 { 200 }
fn default_max_path() -> u32 { 260 }
fn default_allowed_chars() -> String { "a-zA-Z0-9._-".to_string() }
fn default_timestamp_format() -> String { "YYYYMMDD-HHmmss".to_string() }
fn default_reserved_names() -> Vec<String> {
    vec!["CON", "PRN", "AUX", "NUL", "COM1", "LPT1"]
        .into_iter().map(String::from).collect()
}

/// Inventory entry for bundle contents.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleContent {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "type")]
    pub content_type: Option<ContentType>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hash: Option<ContentHash>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContentType {
    Manifest,
    Envelope,
    Plan,
    Receipt,
    Snapshot,
    Log,
    Diff,
    Export,
    Undo,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentHash {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub algorithm: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}

/// Retention policy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleRetention {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub keep_until: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy: Option<RetentionPolicy>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compress_after_days: Option<u32>,
    #[serde(default = "default_true")]
    pub delete_temp_after_completion: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RetentionPolicy {
    Permanent,
    Timed,
    UntilUndoExpires,
    Manual,
}

/// Bundle integrity verification.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleIntegrity {
    #[serde(default = "default_checksum_file")]
    pub checksum_file: String,
    #[serde(default = "default_sig_file")]
    pub signature_file: String,
}

fn default_checksum_file() -> String { "SHA256SUMS".to_string() }
fn default_sig_file() -> String { "SHA256SUMS.sig".to_string() }

impl RunBundle {
    /// Create a minimal run bundle.
    pub fn new(bundle_type: BundleType) -> Self {
        Self {
            version: "1.0.0".to_string(),
            bundle_id: Uuid::new_v4(),
            created_at: Utc::now(),
            source_tool: None,
            bundle_type: Some(bundle_type),
            layout: BundleLayout {
                root_dir_pattern: default_root_pattern(),
                directories: Some(BundleDirectories {
                    snapshots: default_snapshots(),
                    logs: default_logs(),
                    diffs: default_diffs(),
                    exports: default_exports(),
                    undo: default_undo(),
                    temp: default_temp(),
                }),
                files: Some(BundleFiles {
                    manifest: default_manifest(),
                    envelope: default_envelope(),
                    plan: default_plan(),
                    receipt: default_receipt(),
                    receipt_human: default_receipt_human(),
                    summary: default_summary(),
                }),
            },
            naming_rules: None,
            contents: Vec::new(),
            retention: None,
            integrity: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_run_bundle_roundtrip() {
        let bundle = RunBundle::new(BundleType::Scan);
        let json = serde_json::to_string_pretty(&bundle).unwrap();
        assert!(json.contains("scan"));
        assert!(json.contains("snapshots/"));

        let parsed: RunBundle = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.bundle_id, bundle.bundle_id);
    }

    #[test]
    fn test_run_bundle_with_contents() {
        let mut bundle = RunBundle::new(BundleType::Execution);
        bundle.contents.push(BundleContent {
            path: Some("envelope.json".to_string()),
            content_type: Some(ContentType::Envelope),
            hash: Some(ContentHash {
                algorithm: Some("sha256".to_string()),
                value: Some("abc123".to_string()),
            }),
            size_bytes: Some(4096),
            created_at: Some(Utc::now()),
        });

        let json = serde_json::to_string_pretty(&bundle).unwrap();
        let parsed: RunBundle = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.contents.len(), 1);
    }
}
