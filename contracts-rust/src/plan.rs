// SPDX-License-Identifier: PMPL-1.0-or-later
//! Procedure Plan - Operating Theatre workflow with ordered steps.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Operating Theatre plan representation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcedurePlan {
    pub version: String,
    pub plan_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub envelope_ref: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overall_risk: Option<RiskLevel>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overall_reversibility: Option<Reversibility>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub estimated_duration_seconds: Option<u64>,
    #[serde(default)]
    pub requires_reboot: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requires_privileges: Vec<Privilege>,
    pub steps: Vec<PlanStep>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub prerequisites: Vec<Prerequisite>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warnings: Vec<String>,
    #[serde(default = "default_approval")]
    pub approval_required: bool,
}

fn default_approval() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    Safe,
    Guided,
    Expert,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Reversibility {
    Full,
    Partial,
    None,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Privilege {
    User,
    Admin,
    Root,
    System,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub step_id: String,
    pub order: u32,
    pub action: StepAction,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub risk: Option<RiskLevel>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reversibility: Option<Reversibility>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub undo_instruction: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<StepTarget>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parameters: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub finding_refs: Vec<String>,
    #[serde(default)]
    pub requires_confirmation: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub estimated_duration_seconds: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepAction {
    DeleteFile,
    DeleteDirectory,
    MoveFile,
    CopyFile,
    ModifyRegistry,
    StopService,
    StartService,
    RestartService,
    DisableService,
    EnableService,
    UninstallProgram,
    RunCommand,
    ClearCache,
    ClearTemp,
    Defragment,
    UpdateDriver,
    RepairPermissions,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepTarget {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub service: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub registry_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub program: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prerequisite {
    pub check: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default = "default_blocking")]
    pub blocking: bool,
}

fn default_blocking() -> bool {
    true
}

impl ProcedurePlan {
    /// Create a new plan from an envelope reference and steps.
    pub fn new(envelope_ref: Uuid, steps: Vec<PlanStep>) -> Self {
        Self {
            version: "1.0.0".to_string(),
            plan_id: Uuid::new_v4(),
            created_at: Utc::now(),
            envelope_ref,
            title: None,
            description: None,
            overall_risk: None,
            overall_reversibility: None,
            estimated_duration_seconds: None,
            requires_reboot: false,
            requires_privileges: Vec::new(),
            steps,
            prerequisites: Vec::new(),
            warnings: Vec::new(),
            approval_required: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plan_serialization() {
        let plan = ProcedurePlan::new(
            Uuid::new_v4(),
            vec![PlanStep {
                step_id: "step-1".to_string(),
                order: 1,
                action: StepAction::RunCommand,
                title: "Bind zombie GPU to pci-stub".to_string(),
                description: Some("Add kernel parameter to claim device at boot".to_string()),
                preview: Some("rpm-ostree kargs --append=pci-stub.ids=10de:13b0".to_string()),
                risk: Some(RiskLevel::Guided),
                reversibility: Some(Reversibility::Full),
                undo_instruction: Some("rpm-ostree kargs --delete=pci-stub.ids=10de:13b0".to_string()),
                target: None,
                parameters: None,
                finding_refs: Vec::new(),
                requires_confirmation: true,
                estimated_duration_seconds: Some(5),
            }],
        );

        let json = serde_json::to_string_pretty(&plan).unwrap();
        assert!(json.contains("pci-stub"));

        let parsed: ProcedurePlan = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.steps.len(), 1);
    }
}
