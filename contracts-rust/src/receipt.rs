// SPDX-License-Identifier: PMPL-1.0-or-later
//! Receipt - trust anchor for what was checked, changed, and undoable.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// The trust anchor: what was checked, what changed, undo guidance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Receipt {
    pub version: String,
    pub receipt_id: Uuid,
    pub created_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<DateTime<Utc>>,
    pub plan_ref: Uuid,
    pub envelope_ref: Uuid,
    pub status: ReceiptStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<ReceiptSummary>,
    pub steps_executed: Vec<StepResult>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub unchanged: Vec<UnchangedItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub undo_bundle: Option<UndoBundle>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evidence: Option<ReceiptEvidence>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReceiptStatus {
    Completed,
    Partial,
    Failed,
    Cancelled,
    RolledBack,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReceiptSummary {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items_checked: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items_changed: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items_unchanged: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items_failed: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub space_recovered_bytes: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepResult {
    pub step_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step_ref: Option<String>,
    pub status: StepStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub what_changed: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub why_changed: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub after: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<StepError>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub skip_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Success,
    Skipped,
    Failed,
    RolledBack,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepError {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(default)]
    pub recoverable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnchangedItem {
    pub item: String,
    pub reason: UnchangedReason,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub explanation: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UnchangedReason {
    AlreadyOptimal,
    UserSkipped,
    PrerequisiteFailed,
    NotApplicable,
    SafeToKeep,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoBundle {
    pub available: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub steps: Vec<UndoStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoStep {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub step_ref: Option<String>,
    pub reversible: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub undo_command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReceiptEvidence {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before_snapshot: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub after_snapshot: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub logs: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub diffs: Vec<String>,
}

impl Receipt {
    /// Create a new receipt from a plan execution.
    pub fn new(plan_ref: Uuid, envelope_ref: Uuid, status: ReceiptStatus, steps: Vec<StepResult>) -> Self {
        Self {
            version: "1.0.0".to_string(),
            receipt_id: Uuid::new_v4(),
            created_at: Utc::now(),
            completed_at: Some(Utc::now()),
            plan_ref,
            envelope_ref,
            status,
            summary: None,
            steps_executed: steps,
            unchanged: Vec::new(),
            undo_bundle: None,
            evidence: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_receipt_serialization() {
        let receipt = Receipt::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            ReceiptStatus::Completed,
            vec![StepResult {
                step_id: "step-1".to_string(),
                step_ref: Some("step-1".to_string()),
                status: StepStatus::Success,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
                what_changed: Some("Bound GPU to pci-stub".to_string()),
                why_changed: Some("Zombie device consuming power".to_string()),
                before: None,
                after: None,
                error: None,
                skip_reason: None,
            }],
        );

        let json = serde_json::to_string_pretty(&receipt).unwrap();
        assert!(json.contains("completed"));

        let parsed: Receipt = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.steps_executed.len(), 1);
    }
}
