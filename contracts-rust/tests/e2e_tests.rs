// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//! End-to-end tests for the contract lifecycle.
//!
//! Simulates the complete workflow:
//! 1. Evidence scan → EvidenceEnvelope
//! 2. Plan creation → ProcedurePlan
//! 3. Plan execution → Receipt
//! 4. System health → SystemWeather

use ambientops_contracts::*;
use chrono::Utc;
use uuid::Uuid;

#[test]
fn e2e_full_contract_lifecycle() {
    // Step 1: Create evidence envelope (from scan)
    let envelope = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: Some("1.0.0".to_string()),
            host: envelope::HostInfo {
                hostname: "test-system".to_string(),
                os: Some("Linux".to_string()),
                os_version: Some("6.19".to_string()),
                arch: Some("x86_64".to_string()),
            },
            profile: Some("default".to_string()),
            pack: None,
        },
        artifacts: vec![
            envelope::Artifact {
                artifact_id: Uuid::new_v4(),
                artifact_type: envelope::ArtifactType::Log,
                path: "/var/log/system.log".to_string(),
                hash: Some(envelope::ArtifactHash {
                    algorithm: envelope::HashAlgorithm::Sha256,
                    value: "abc123def456".to_string(),
                }),
                size_bytes: Some(1024),
                mime_type: Some("text/plain".to_string()),
                description: Some("System log snapshot".to_string()),
            },
        ],
        findings: vec![],
        metrics: None,
        redaction_profile: envelope::RedactionProfile::Standard,
        provenance: None,
    };

    // Step 2: Create procedure plan referencing the envelope
    let plan = ProcedurePlan {
        version: "1.0.0".to_string(),
        plan_id: Uuid::new_v4(),
        created_at: Utc::now(),
        envelope_ref: envelope.envelope_id,
        title: Some("System Cleanup".to_string()),
        description: Some("Automated cleanup procedure".to_string()),
        overall_risk: Some(plan::RiskLevel::Safe),
        overall_reversibility: Some(plan::Reversibility::Full),
        estimated_duration_seconds: Some(300),
        requires_reboot: false,
        requires_privileges: vec![plan::Privilege::Admin],
        steps: vec![
            plan::PlanStep {
                step_id: "step_01".to_string(),
                order: 0,
                action: plan::StepAction::RunCommand,
                title: "Backup configuration".to_string(),
                description: Some("Create backup before changes".to_string()),
                preview: Some("mkdir -p /backup && tar czf /backup/config.tar.gz /etc".to_string()),
                risk: Some(plan::RiskLevel::Safe),
                reversibility: Some(plan::Reversibility::Full),
                undo_instruction: Some("rm -rf /backup/config.tar.gz".to_string()),
                target: None,
                parameters: None,
                finding_refs: vec![],
                requires_confirmation: false,
                estimated_duration_seconds: Some(10),
            },
            plan::PlanStep {
                step_id: "step_02".to_string(),
                order: 1,
                action: plan::StepAction::Custom,
                title: "Verify system health".to_string(),
                description: Some("Run health checks".to_string()),
                preview: Some("systemctl status".to_string()),
                risk: Some(plan::RiskLevel::Safe),
                reversibility: Some(plan::Reversibility::Full),
                undo_instruction: None,
                target: None,
                parameters: None,
                finding_refs: vec![],
                requires_confirmation: false,
                estimated_duration_seconds: Some(5),
            },
        ],
        prerequisites: vec![],
        warnings: vec!["This operation requires administrative privileges".to_string()],
        approval_required: true,
    };

    // Step 3: Create receipt from plan execution
    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: Some(Utc::now()),
        plan_ref: plan.plan_id,
        envelope_ref: envelope.envelope_id,
        status: receipt::ReceiptStatus::Completed,
        summary: Some(receipt::ReceiptSummary {
            title: Some("Cleanup completed successfully".to_string()),
            description: Some("All steps executed without errors".to_string()),
            items_checked: Some(2),
            items_changed: Some(1),
            items_unchanged: Some(1),
            items_failed: Some(0),
            space_recovered_bytes: Some(5242880), // 5MB
            duration_seconds: Some(15.5),
        }),
        steps_executed: vec![
            receipt::StepResult {
                step_id: "step_01".to_string(),
                step_ref: Some("step_01".to_string()),
                status: receipt::StepStatus::Success,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
                what_changed: Some("Created backup archive at /backup/config.tar.gz".to_string()),
                why_changed: Some("Preserving original configuration before modifications".to_string()),
                before: Some(serde_json::json!({"backup_exists": false})),
                after: Some(serde_json::json!({"backup_exists": true, "size_bytes": 2621440})),
                error: None,
                skip_reason: None,
            },
            receipt::StepResult {
                step_id: "step_02".to_string(),
                step_ref: Some("step_02".to_string()),
                status: receipt::StepStatus::Success,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
                what_changed: None,
                why_changed: None,
                before: Some(serde_json::json!({"status": "running"})),
                after: Some(serde_json::json!({"status": "running"})),
                error: None,
                skip_reason: None,
            },
        ],
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // Step 4: Create system weather reflecting overall health
    let weather = SystemWeather {
        version: "1.0.0".to_string(),
        timestamp: Utc::now(),
        state: weather::WeatherState::Calm,
        summary: "System health is optimal".to_string(),
        details: Some("All monitored systems are operating normally".to_string()),
        categories: None,
        evidence_pointers: vec![
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: envelope.envelope_id.to_string(),
                label: Some("Initial scan".to_string()),
            },
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: receipt.receipt_id.to_string(),
                label: Some("Remediation receipt".to_string()),
            },
        ],
        notifications: None,
        actions: vec![],
        trends: None,
        source: None,
    };

    // VERIFY: All contracts are created and valid
    assert!(!envelope.envelope_id.as_bytes().iter().all(|&b| b == 0));
    assert_eq!(plan.envelope_ref, envelope.envelope_id);
    assert_eq!(receipt.plan_ref, plan.plan_id);
    assert_eq!(receipt.envelope_ref, envelope.envelope_id);

    // VERIFY: Serialization works
    let envelope_json = serde_json::to_string(&envelope).expect("Envelope serialization failed");
    let plan_json = serde_json::to_string(&plan).expect("Plan serialization failed");
    let receipt_json = serde_json::to_string(&receipt).expect("Receipt serialization failed");
    let weather_json = serde_json::to_string(&weather).expect("Weather serialization failed");

    // VERIFY: Deserialization works
    let _restored_envelope: EvidenceEnvelope =
        serde_json::from_str(&envelope_json).expect("Envelope deserialization failed");
    let _restored_plan: ProcedurePlan =
        serde_json::from_str(&plan_json).expect("Plan deserialization failed");
    let _restored_receipt: Receipt =
        serde_json::from_str(&receipt_json).expect("Receipt deserialization failed");
    let _restored_weather: SystemWeather =
        serde_json::from_str(&weather_json).expect("Weather deserialization failed");

    // VERIFY: Plan has steps in order
    assert!(plan.steps.len() > 0);
    for window in plan.steps.windows(2) {
        assert!(window[0].order <= window[1].order);
    }

    // VERIFY: Receipt references match
    assert_eq!(receipt.steps_executed.len(), plan.steps.len());
}

#[test]
fn e2e_minimal_envelope_workflow() {
    // Minimal valid envelope creation
    let envelope = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::BigUp,
            tool_version: None,
            host: envelope::HostInfo {
                hostname: "host".to_string(),
                os: None,
                os_version: None,
                arch: None,
            },
            profile: None,
            pack: None,
        },
        artifacts: vec![],
        findings: vec![],
        metrics: None,
        redaction_profile: envelope::RedactionProfile::Standard,
        provenance: None,
    };

    let json = serde_json::to_string(&envelope).expect("Serialization failed");
    let restored: EvidenceEnvelope =
        serde_json::from_str(&json).expect("Deserialization failed");

    assert_eq!(envelope.envelope_id, restored.envelope_id);
    assert_eq!(envelope.version, restored.version);
}

#[test]
fn e2e_plan_with_multiple_steps() {
    let plan = ProcedurePlan {
        version: "1.0.0".to_string(),
        plan_id: Uuid::new_v4(),
        created_at: Utc::now(),
        envelope_ref: Uuid::new_v4(),
        title: None,
        description: None,
        overall_risk: None,
        overall_reversibility: None,
        estimated_duration_seconds: None,
        requires_reboot: false,
        requires_privileges: vec![],
        steps: vec![
            plan::PlanStep {
                step_id: "s1".to_string(),
                order: 0,
                action: plan::StepAction::RunCommand,
                title: "Step 1".to_string(),
                description: None,
                preview: None,
                risk: None,
                reversibility: None,
                undo_instruction: None,
                target: None,
                parameters: None,
                finding_refs: vec![],
                requires_confirmation: false,
                estimated_duration_seconds: None,
            },
            plan::PlanStep {
                step_id: "s2".to_string(),
                order: 1,
                action: plan::StepAction::Custom,
                title: "Step 2".to_string(),
                description: None,
                preview: None,
                risk: None,
                reversibility: None,
                undo_instruction: None,
                target: None,
                parameters: None,
                finding_refs: vec![],
                requires_confirmation: false,
                estimated_duration_seconds: None,
            },
            plan::PlanStep {
                step_id: "s3".to_string(),
                order: 2,
                action: plan::StepAction::RunCommand,
                title: "Step 3".to_string(),
                description: None,
                preview: None,
                risk: None,
                reversibility: None,
                undo_instruction: None,
                target: None,
                parameters: None,
                finding_refs: vec![],
                requires_confirmation: false,
                estimated_duration_seconds: None,
            },
        ],
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    // Verify step ordering
    for (i, step) in plan.steps.iter().enumerate() {
        assert_eq!(step.order as usize, i);
    }

    // Verify serialization
    let json = serde_json::to_string(&plan).expect("Serialization failed");
    let restored: ProcedurePlan =
        serde_json::from_str(&json).expect("Deserialization failed");

    assert_eq!(plan.steps.len(), restored.steps.len());
    for (orig, rest) in plan.steps.iter().zip(restored.steps.iter()) {
        assert_eq!(orig.step_id, rest.step_id);
        assert_eq!(orig.order, rest.order);
    }
}

#[test]
fn e2e_receipt_with_state_transitions() {
    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: Some(Utc::now()),
        plan_ref: Uuid::new_v4(),
        envelope_ref: Uuid::new_v4(),
        status: receipt::ReceiptStatus::Completed,
        summary: None,
        steps_executed: vec![
            receipt::StepResult {
                step_id: "step_1".to_string(),
                step_ref: None,
                status: receipt::StepStatus::Success,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
                what_changed: None,
                why_changed: None,
                before: None,
                after: None,
                error: None,
                skip_reason: None,
            },
        ],
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // Verify status is valid
    match receipt.status {
        receipt::ReceiptStatus::Completed => (),
        _ => panic!("Expected Completed status"),
    }

    // Verify can serialize with state
    let json = serde_json::to_string(&receipt).expect("Serialization failed");
    let restored: Receipt =
        serde_json::from_str(&json).expect("Deserialization failed");

    // Verify status survives round-trip via serialization
    match restored.status {
        receipt::ReceiptStatus::Completed => (),
        _ => panic!("Status not preserved after round-trip"),
    }
}

#[test]
fn e2e_weather_with_evidence_pointers() {
    let envelope_id = Uuid::new_v4();
    let receipt_id = Uuid::new_v4();

    let weather = SystemWeather {
        version: "1.0.0".to_string(),
        timestamp: Utc::now(),
        state: weather::WeatherState::Act,
        summary: "System requires attention".to_string(),
        details: None,
        categories: None,
        evidence_pointers: vec![
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: envelope_id.to_string(),
                label: Some("Initial scan".to_string()),
            },
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: receipt_id.to_string(),
                label: Some("Remediation".to_string()),
            },
        ],
        notifications: None,
        actions: vec![],
        trends: None,
        source: None,
    };

    // Verify pointers are preserved
    assert_eq!(weather.evidence_pointers.len(), 2);
    assert_eq!(
        weather.evidence_pointers[0].reference,
        envelope_id.to_string()
    );

    // Verify serialization preserves pointers
    let json = serde_json::to_string(&weather).expect("Serialization failed");
    let restored: SystemWeather =
        serde_json::from_str(&json).expect("Deserialization failed");

    assert_eq!(weather.evidence_pointers.len(), restored.evidence_pointers.len());
}
