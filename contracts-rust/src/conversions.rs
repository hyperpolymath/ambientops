// SPDX-License-Identifier: PMPL-1.0-or-later
//! Conversions between hardware-crash-team types and contract types.
//!
//! These are kept here rather than in hardware-crash-team to avoid circular
//! dependencies. Hardware-crash-team depends on contracts-rust and uses these
//! conversions to emit schema-conformant output.

use crate::envelope::*;
use crate::plan::*;
use crate::receipt::*;
use chrono::Utc;
use uuid::Uuid;

/// Convert a hardware-crash-team SystemReport into an EvidenceEnvelope.
///
/// This produces a fully schema-conformant envelope from raw scan output.
pub fn system_report_to_envelope(
    report_json: &serde_json::Value,
    hostname: &str,
) -> EvidenceEnvelope {
    let artifact_id = Uuid::new_v4();

    // Extract findings from the report's devices' issues
    let mut findings = Vec::new();
    if let Some(devices) = report_json.get("devices").and_then(|d| d.as_array()) {
        for device in devices {
            if let Some(issues) = device.get("issues").and_then(|i| i.as_array()) {
                for issue in issues {
                    let severity = match issue.get("severity").and_then(|s| s.as_str()) {
                        Some("Critical") => FindingSeverity::Critical,
                        Some("High") => FindingSeverity::High,
                        Some("Warning") => FindingSeverity::Medium,
                        Some("Info") => FindingSeverity::Info,
                        _ => FindingSeverity::Low,
                    };

                    let category = match issue.get("issue_type").and_then(|t| t.as_str()) {
                        Some("AcpiError") => FindingCategory::Config,
                        Some("NoIommuIsolation") | Some("UnmanagedMemory") => FindingCategory::Security,
                        _ => FindingCategory::Performance,
                    };

                    findings.push(Finding {
                        finding_id: Uuid::new_v4().to_string(),
                        severity,
                        category,
                        title: issue
                            .get("description")
                            .and_then(|d| d.as_str())
                            .unwrap_or("Hardware issue detected")
                            .to_string(),
                        description: issue.get("remediation").and_then(|r| r.as_str()).map(String::from),
                        evidence_refs: vec![artifact_id],
                        recommendation: issue.get("remediation").and_then(|r| r.as_str()).map(String::from),
                        auto_fixable: true,
                    });
                }
            }
        }
    }

    let report_bytes = serde_json::to_vec_pretty(report_json).unwrap_or_default();

    EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: EnvelopeSource {
            tool: SourceTool::HardwareCrashTeam,
            tool_version: Some("0.1.0".to_string()),
            host: HostInfo {
                hostname: hostname.to_string(),
                os: Some("Linux".to_string()),
                os_version: None,
                arch: Some(std::env::consts::ARCH.to_string()),
            },
            profile: Some("full".to_string()),
            pack: None,
        },
        artifacts: vec![Artifact {
            artifact_id,
            artifact_type: ArtifactType::Report,
            path: "scan-report.json".to_string(),
            hash: None,
            size_bytes: Some(report_bytes.len() as u64),
            mime_type: Some("application/json".to_string()),
            description: Some("Hardware crash team PCI scan report".to_string()),
        }],
        findings,
        metrics: None,
        redaction_profile: RedactionProfile::Standard,
        provenance: None,
    }
}

/// Convert a hardware-crash-team RemediationPlan into a ProcedurePlan.
pub fn remediation_plan_to_procedure(
    plan_json: &serde_json::Value,
    envelope_ref: Uuid,
) -> ProcedurePlan {
    let mut steps = Vec::new();

    if let Some(plan_steps) = plan_json.get("steps").and_then(|s| s.as_array()) {
        for (i, step) in plan_steps.iter().enumerate() {
            let description = step
                .get("description")
                .and_then(|d| d.as_str())
                .unwrap_or("Execute remediation step")
                .to_string();
            let command = step
                .get("command")
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string();
            let needs_sudo = step
                .get("needs_sudo")
                .and_then(|n| n.as_bool())
                .unwrap_or(false);

            steps.push(PlanStep {
                step_id: format!("step-{}", i + 1),
                order: (i + 1) as u32,
                action: StepAction::RunCommand,
                title: description.clone(),
                description: Some(description),
                preview: Some(command),
                risk: Some(RiskLevel::Guided),
                reversibility: Some(Reversibility::Full),
                undo_instruction: None,
                target: None,
                parameters: None,
                finding_refs: Vec::new(),
                requires_confirmation: true,
                estimated_duration_seconds: Some(5),
            });
        }
    }

    let requires_reboot = plan_json
        .get("requires_reboot")
        .and_then(|r| r.as_bool())
        .unwrap_or(false);

    let device = plan_json
        .get("device")
        .and_then(|d| d.as_str())
        .unwrap_or("unknown");
    let strategy = plan_json
        .get("strategy")
        .and_then(|s| s.as_str())
        .unwrap_or("unknown");

    let mut plan = ProcedurePlan::new(envelope_ref, steps);
    plan.title = Some(format!("Hardware remediation for device {}", device));
    plan.description = Some(format!(
        "Remediate hardware issue on device {} using {} strategy",
        device, strategy
    ));
    plan.overall_risk = Some(RiskLevel::Guided);
    plan.overall_reversibility = Some(Reversibility::Full);
    plan.requires_reboot = requires_reboot;
    if requires_reboot {
        plan.requires_privileges = vec![Privilege::Root];
    }
    plan.warnings = vec![
        "This plan modifies kernel boot parameters.".to_string(),
        "A reboot will be required for changes to take effect.".to_string(),
    ];

    plan
}

/// Convert a hardware-crash-team RemediationReceipt into a contract Receipt.
pub fn remediation_receipt_to_contract(
    receipt_json: &serde_json::Value,
    plan_ref: Uuid,
    envelope_ref: Uuid,
) -> Receipt {
    let mut step_results = Vec::new();

    // The hardware-crash-team receipt contains the original plan steps
    if let Some(plan) = receipt_json.get("plan") {
        if let Some(plan_steps) = plan.get("steps").and_then(|s| s.as_array()) {
            for (i, _step) in plan_steps.iter().enumerate() {
                step_results.push(StepResult {
                    step_id: format!("step-{}", i + 1),
                    step_ref: Some(format!("step-{}", i + 1)),
                    status: StepStatus::Success,
                    started_at: Some(Utc::now()),
                    completed_at: Some(Utc::now()),
                    what_changed: None,
                    why_changed: None,
                    before: None,
                    after: None,
                    error: None,
                    skip_reason: None,
                });
            }
        }

        // Build undo bundle from undo_steps
        let undo_steps: Vec<UndoStep> = plan
            .get("undo_steps")
            .and_then(|s| s.as_array())
            .map(|steps| {
                steps
                    .iter()
                    .enumerate()
                    .map(|(i, step)| UndoStep {
                        step_ref: Some(format!("step-{}", i + 1)),
                        reversible: true,
                        undo_command: step.get("command").and_then(|c| c.as_str()).map(String::from),
                        backup_path: None,
                    })
                    .collect()
            })
            .unwrap_or_default();

        let mut receipt = Receipt::new(plan_ref, envelope_ref, ReceiptStatus::Completed, step_results);
        receipt.undo_bundle = Some(UndoBundle {
            available: !undo_steps.is_empty(),
            path: None,
            expires_at: None,
            steps: undo_steps,
        });
        receipt.summary = Some(ReceiptSummary {
            title: Some("Hardware remediation applied".to_string()),
            description: Some("Kernel boot parameters modified for hardware isolation".to_string()),
            items_checked: None,
            items_changed: Some(receipt.steps_executed.len() as u32),
            items_unchanged: Some(0),
            items_failed: Some(0),
            space_recovered_bytes: None,
            duration_seconds: None,
        });

        return receipt;
    }

    Receipt::new(plan_ref, envelope_ref, ReceiptStatus::Failed, step_results)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_system_report_to_envelope() {
        let report = serde_json::json!({
            "timestamp": "2026-02-12T10:00:00Z",
            "kernel_version": "6.18.8",
            "devices": [{
                "slot": "01:00.0",
                "pci_id": "10de:13b0",
                "description": "NVIDIA Quadro M2000M",
                "vendor": "NVIDIA",
                "class": "VGA compatible controller",
                "driver": null,
                "power_state": "D0",
                "issues": [{
                    "severity": "Critical",
                    "issue_type": "ZombieDevice",
                    "description": "GPU powered on with no driver",
                    "remediation": "Bind to pci-stub or vfio-pci"
                }]
            }],
            "iommu": { "enabled": true },
            "acpi_errors": [],
            "risk_level": "Critical"
        });

        let envelope = system_report_to_envelope(&report, "test-host");
        assert_eq!(envelope.artifacts.len(), 1);
        assert_eq!(envelope.findings.len(), 1);
        assert!(matches!(envelope.findings[0].severity, FindingSeverity::Critical));
    }

    #[test]
    fn test_remediation_plan_to_procedure() {
        let plan = serde_json::json!({
            "id": "plan-123",
            "device": "01:00.0",
            "strategy": "DualNullDriver",
            "steps": [
                {
                    "description": "Add pci-stub.ids kernel parameter",
                    "command": "rpm-ostree kargs --append=pci-stub.ids=10de:13b0",
                    "needs_sudo": true,
                    "needs_reboot": true
                }
            ],
            "undo_steps": [
                {
                    "description": "Remove pci-stub.ids kernel parameter",
                    "command": "rpm-ostree kargs --delete=pci-stub.ids=10de:13b0",
                    "needs_sudo": true,
                    "needs_reboot": true
                }
            ],
            "requires_reboot": true,
            "risk": "Medium"
        });

        let procedure = remediation_plan_to_procedure(&plan, Uuid::new_v4());
        assert_eq!(procedure.steps.len(), 1);
        assert!(procedure.requires_reboot);
        assert!(procedure.title.unwrap().contains("01:00.0"));
    }

    #[test]
    fn test_remediation_receipt_to_contract() {
        let receipt = serde_json::json!({
            "plan": {
                "steps": [
                    { "description": "step 1", "command": "cmd1", "needs_sudo": true, "needs_reboot": false }
                ],
                "undo_steps": [
                    { "description": "undo step 1", "command": "undo-cmd1", "needs_sudo": true, "needs_reboot": false }
                ]
            },
            "applied_at": "2026-02-12T10:00:00Z",
            "reboot_pending": true,
            "pre_state": "active"
        });

        let plan_ref = Uuid::new_v4();
        let envelope_ref = Uuid::new_v4();
        let contract_receipt = remediation_receipt_to_contract(&receipt, plan_ref, envelope_ref);

        assert!(matches!(contract_receipt.status, ReceiptStatus::Completed));
        assert_eq!(contract_receipt.steps_executed.len(), 1);
        assert!(contract_receipt.undo_bundle.is_some());
        assert!(contract_receipt.undo_bundle.as_ref().unwrap().available);
    }
}
