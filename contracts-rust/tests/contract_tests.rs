// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//! Contract/invariant tests for AmbientOps data structures.
//!
//! These tests verify that contracts maintain their invariants
//! throughout various operations and transformations.

use ambientops_contracts::*;
use chrono::Utc;
use uuid::Uuid;

// =============================================================================
// EVIDENCE ENVELOPE INVARIANTS
// =============================================================================

#[test]
fn invariant_envelope_has_unique_id() {
    let e1 = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: None,
            host: envelope::HostInfo {
                hostname: "test".to_string(),
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

    let e2 = EvidenceEnvelope {
        envelope_id: Uuid::new_v4(),
        ..e1.clone()
    };

    // INVARIANT: Different envelopes have different IDs
    assert_ne!(e1.envelope_id, e2.envelope_id);
}

#[test]
fn invariant_envelope_has_valid_hostname() {
    let envelope = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: None,
            host: envelope::HostInfo {
                hostname: "workstation.local".to_string(),
                os: Some("Linux".to_string()),
                os_version: Some("6.19".to_string()),
                arch: Some("x86_64".to_string()),
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

    // INVARIANT: Hostname is non-empty
    assert!(!envelope.source.host.hostname.is_empty());
    assert!(envelope.source.host.hostname.len() > 0);
}

#[test]
fn invariant_envelope_artifacts_preserved() {
    let artifact_id = Uuid::new_v4();
    let envelope = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: None,
            host: envelope::HostInfo {
                hostname: "test".to_string(),
                os: None,
                os_version: None,
                arch: None,
            },
            profile: None,
            pack: None,
        },
        artifacts: vec![envelope::Artifact {
            artifact_id,
            artifact_type: envelope::ArtifactType::Log,
            path: "/var/log/test.log".to_string(),
            hash: None,
            size_bytes: Some(1024),
            mime_type: Some("text/plain".to_string()),
            description: None,
        }],
        findings: vec![],
        metrics: None,
        redaction_profile: envelope::RedactionProfile::Standard,
        provenance: None,
    };

    // INVARIANT: Artifacts are preserved after serialization
    let json = serde_json::to_string(&envelope).unwrap();
    let restored: EvidenceEnvelope = serde_json::from_str(&json).unwrap();

    assert_eq!(envelope.artifacts.len(), restored.artifacts.len());
    assert_eq!(
        envelope.artifacts[0].artifact_id,
        restored.artifacts[0].artifact_id
    );
}

// =============================================================================
// PROCEDURE PLAN INVARIANTS
// =============================================================================

#[test]
fn invariant_plan_step_ordering() {
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
                title: "First".to_string(),
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
                title: "Second".to_string(),
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
                title: "Third".to_string(),
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

    // INVARIANT: Steps have monotonic ordering
    for (i, step) in plan.steps.iter().enumerate() {
        assert_eq!(step.order as usize, i, "Step ordering is monotonic");
    }
}

#[test]
fn invariant_plan_references_envelope() {
    let envelope_ref = Uuid::new_v4();
    let plan = ProcedurePlan {
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
        requires_privileges: vec![],
        steps: vec![],
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    // INVARIANT: Plan's envelope reference is set
    assert_eq!(plan.envelope_ref, envelope_ref);
}

#[test]
fn invariant_plan_has_unique_id() {
    let p1 = ProcedurePlan {
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
        steps: vec![],
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    let p2 = ProcedurePlan {
        plan_id: Uuid::new_v4(),
        ..p1.clone()
    };

    // INVARIANT: Different plans have different IDs
    assert_ne!(p1.plan_id, p2.plan_id);
}

// =============================================================================
// RECEIPT INVARIANTS
// =============================================================================

#[test]
fn invariant_receipt_has_references() {
    let plan_id = Uuid::new_v4();
    let envelope_id = Uuid::new_v4();

    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: None,
        plan_ref: plan_id,
        envelope_ref: envelope_id,
        status: receipt::ReceiptStatus::Completed,
        summary: None,
        steps_executed: vec![],
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // INVARIANT: Receipt has valid references to plan and envelope
    assert_eq!(receipt.plan_ref, plan_id);
    assert_eq!(receipt.envelope_ref, envelope_id);
}

#[test]
fn invariant_receipt_status_is_valid() {
    for status in &[
        receipt::ReceiptStatus::Completed,
        receipt::ReceiptStatus::Partial,
        receipt::ReceiptStatus::Failed,
        receipt::ReceiptStatus::Cancelled,
        receipt::ReceiptStatus::RolledBack,
    ] {
        let receipt = Receipt {
            version: "1.0.0".to_string(),
            receipt_id: Uuid::new_v4(),
            created_at: Utc::now(),
            completed_at: None,
            plan_ref: Uuid::new_v4(),
            envelope_ref: Uuid::new_v4(),
            status: status.clone(),
            summary: None,
            steps_executed: vec![],
            unchanged: vec![],
            undo_bundle: None,
            evidence: None,
        };

        // INVARIANT: Status can be serialized and deserialized
        let json = serde_json::to_string(&receipt).unwrap();
        let _restored: Receipt = serde_json::from_str(&json).unwrap();
        // Status enum doesn't implement PartialEq, but serialization succeeds
    }
}

#[test]
fn invariant_receipt_step_execution_order() {
    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: None,
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
            receipt::StepResult {
                step_id: "step_2".to_string(),
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

    // INVARIANT: Steps preserve order
    assert_eq!(receipt.steps_executed.len(), 2);
    assert_eq!(receipt.steps_executed[0].step_id, "step_1");
    assert_eq!(receipt.steps_executed[1].step_id, "step_2");
}

// =============================================================================
// SYSTEM WEATHER INVARIANTS
// =============================================================================

#[test]
fn invariant_weather_state_is_valid() {
    for state in &[
        weather::WeatherState::Calm,
        weather::WeatherState::Watch,
        weather::WeatherState::Act,
    ] {
        let weather = SystemWeather {
            version: "1.0.0".to_string(),
            timestamp: Utc::now(),
            state: state.clone(),
            summary: "Test".to_string(),
            details: None,
            categories: None,
            evidence_pointers: vec![],
            notifications: None,
            actions: vec![],
            trends: None,
            source: None,
        };

        // INVARIANT: State can be serialized
        let json = serde_json::to_string(&weather).unwrap();
        let _restored: SystemWeather = serde_json::from_str(&json).unwrap();
        // State enum doesn't implement PartialEq, but serialization succeeds
    }
}

#[test]
fn invariant_weather_evidence_pointers_preserved() {
    let pointer1_ref = Uuid::new_v4().to_string();
    let pointer2_ref = Uuid::new_v4().to_string();

    let weather = SystemWeather {
        version: "1.0.0".to_string(),
        timestamp: Utc::now(),
        state: weather::WeatherState::Calm,
        summary: "Test".to_string(),
        details: None,
        categories: None,
        evidence_pointers: vec![
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: pointer1_ref.clone(),
                label: Some("First".to_string()),
            },
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Finding,
                reference: pointer2_ref.clone(),
                label: None,
            },
        ],
        notifications: None,
        actions: vec![],
        trends: None,
        source: None,
    };

    // INVARIANT: Evidence pointers are preserved
    assert_eq!(weather.evidence_pointers.len(), 2);
    assert_eq!(weather.evidence_pointers[0].reference, pointer1_ref);
    assert_eq!(weather.evidence_pointers[1].reference, pointer2_ref);

    // INVARIANT: Pointers survive serialization
    let json = serde_json::to_string(&weather).unwrap();
    let restored: SystemWeather = serde_json::from_str(&json).unwrap();
    assert_eq!(weather.evidence_pointers.len(), restored.evidence_pointers.len());
}

// =============================================================================
// CROSS-CONTRACT INVARIANTS
// =============================================================================

#[test]
fn invariant_cross_contract_referential_integrity() {
    let envelope_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();
    let receipt_id = Uuid::new_v4();

    // Create contracts with proper references
    let envelope = EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id,
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: None,
            host: envelope::HostInfo {
                hostname: "test".to_string(),
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

    let plan = ProcedurePlan {
        version: "1.0.0".to_string(),
        plan_id,
        created_at: Utc::now(),
        envelope_ref: envelope_id,
        title: None,
        description: None,
        overall_risk: None,
        overall_reversibility: None,
        estimated_duration_seconds: None,
        requires_reboot: false,
        requires_privileges: vec![],
        steps: vec![],
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id,
        created_at: Utc::now(),
        completed_at: None,
        plan_ref: plan_id,
        envelope_ref: envelope_id,
        status: receipt::ReceiptStatus::Completed,
        summary: None,
        steps_executed: vec![],
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // INVARIANT: All references are consistent
    assert_eq!(plan.envelope_ref, envelope.envelope_id);
    assert_eq!(receipt.plan_ref, plan.plan_id);
    assert_eq!(receipt.envelope_ref, envelope.envelope_id);
}
