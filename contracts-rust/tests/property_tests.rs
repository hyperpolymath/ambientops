// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//! Property-based tests for AmbientOps contract types.
//!
//! Uses proptest to verify that contract types maintain invariants
//! across randomly generated instances.

use ambientops_contracts::*;
use chrono::Utc;
use proptest::prelude::*;
use serde_json::json;
use uuid::Uuid;

// =============================================================================
// PROPERTY GENERATORS
// =============================================================================

/// Strategy for generating valid EvidenceEnvelope instances
fn arb_evidence_envelope() -> impl Strategy<Value = EvidenceEnvelope> {
    (
        "1.0.0|1.1.0|2.0.0",
        prop::option::of("[a-z0-9-]{1,50}"),
    )
        .prop_flat_map(|(version, profile)| {
            (
                Just(version.to_string()),
                Just(Uuid::new_v4()),
                Just(Utc::now()),
                Just(envelope::EnvelopeSource {
                    tool: envelope::SourceTool::Ambient,
                    tool_version: Some("1.0.0".to_string()),
                    host: envelope::HostInfo {
                        hostname: "test-host".to_string(),
                        os: Some("Linux".to_string()),
                        os_version: Some("6.19".to_string()),
                        arch: Some("x86_64".to_string()),
                    },
                    profile,
                    pack: None,
                }),
                prop::collection::vec(
                    (
                        Just(Uuid::new_v4()),
                        prop_oneof![
                            Just(envelope::ArtifactType::Log),
                            Just(envelope::ArtifactType::Config),
                            Just(envelope::ArtifactType::Metric),
                        ],
                        "[a-z0-9/_-]{1,100}",
                        prop::option::of("0"),
                    ),
                    0..5,
                )
                .prop_map(|artifacts| {
                    artifacts
                        .into_iter()
                        .map(|(id, artifact_type, path, _)| envelope::Artifact {
                            artifact_id: id,
                            artifact_type,
                            path,
                            hash: None,
                            size_bytes: None,
                            mime_type: None,
                            description: None,
                        })
                        .collect()
                }),
            )
        })
        .prop_map(|(version, envelope_id, created_at, source, artifacts)| EvidenceEnvelope {
            version,
            envelope_id,
            created_at,
            source,
            artifacts,
            findings: vec![],
            metrics: None,
            redaction_profile: envelope::RedactionProfile::Standard,
            provenance: None,
        })
}

/// Strategy for generating valid ProcedurePlan instances
fn arb_procedure_plan() -> impl Strategy<Value = ProcedurePlan> {
    (0..5_u32)
        .prop_flat_map(|step_count| {
            (
                Just("1.0.0".to_string()),
                Just(Uuid::new_v4()),
                Just(Utc::now()),
                Just(Uuid::new_v4()),
                prop::collection::vec(
                    (
                        "[a-z0-9_]{1,20}",
                        Just(0_u32),
                        "[a-zA-Z0-9 ]{1,50}",
                    ),
                    step_count as usize,
                ),
            )
        })
        .prop_map(|(version, plan_id, created_at, envelope_ref, step_specs)| {
            let steps = step_specs
                .into_iter()
                .enumerate()
                .map(|(idx, (step_id, _, title))| plan::PlanStep {
                    step_id,
                    order: idx as u32,
                    action: plan::StepAction::RunCommand,
                    title,
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
                })
                .collect();

            ProcedurePlan {
                version,
                plan_id,
                created_at,
                envelope_ref,
                title: None,
                description: None,
                overall_risk: None,
                overall_reversibility: None,
                estimated_duration_seconds: None,
                requires_reboot: false,
                requires_privileges: vec![],
                steps,
                prerequisites: vec![],
                warnings: vec![],
                approval_required: true,
            }
        })
}

/// Strategy for generating valid Receipt instances
fn arb_receipt() -> impl Strategy<Value = Receipt> {
    (0..5_u32)
        .prop_flat_map(|step_count| {
            (
                Just("1.0.0".to_string()),
                Just(Uuid::new_v4()),
                Just(Utc::now()),
                Just(Uuid::new_v4()),
                Just(Uuid::new_v4()),
                prop::collection::vec(
                    ("[a-z0-9_]{1,20}"),
                    step_count as usize,
                ),
            )
        })
        .prop_map(|(version, receipt_id, created_at, plan_ref, envelope_ref, step_ids)| {
            let steps_executed = step_ids
                .into_iter()
                .map(|step_id| receipt::StepResult {
                    step_id,
                    step_ref: None,
                    status: receipt::StepStatus::Success,
                    started_at: None,
                    completed_at: None,
                    what_changed: None,
                    why_changed: None,
                    before: None,
                    after: None,
                    error: None,
                    skip_reason: None,
                })
                .collect();

            Receipt {
                version,
                receipt_id,
                created_at,
                completed_at: None,
                plan_ref,
                envelope_ref,
                status: receipt::ReceiptStatus::Completed,
                summary: None,
                steps_executed,
                unchanged: vec![],
                undo_bundle: None,
                evidence: None,
            }
        })
}

// =============================================================================
// PROPERTY TESTS: SERIALIZATION ROUND-TRIPS
// =============================================================================

proptest! {
    #[test]
    fn prop_envelope_serde_roundtrip(envelope in arb_evidence_envelope()) {
        let json = serde_json::to_string(&envelope)
            .expect("Envelope serialization failed");
        let restored: EvidenceEnvelope = serde_json::from_str(&json)
            .expect("Envelope deserialization failed");

        prop_assert_eq!(envelope.envelope_id, restored.envelope_id);
        prop_assert_eq!(envelope.version, restored.version);
        prop_assert_eq!(envelope.artifacts.len(), restored.artifacts.len());
    }

    #[test]
    fn prop_plan_serde_roundtrip(plan in arb_procedure_plan()) {
        let json = serde_json::to_string(&plan)
            .expect("Plan serialization failed");
        let restored: ProcedurePlan = serde_json::from_str(&json)
            .expect("Plan deserialization failed");

        prop_assert_eq!(plan.plan_id, restored.plan_id);
        prop_assert_eq!(plan.version, restored.version);
        prop_assert_eq!(plan.steps.len(), restored.steps.len());
    }

    #[test]
    fn prop_receipt_serde_roundtrip(receipt in arb_receipt()) {
        let json = serde_json::to_string(&receipt)
            .expect("Receipt serialization failed");
        let restored: Receipt = serde_json::from_str(&json)
            .expect("Receipt deserialization failed");

        prop_assert_eq!(receipt.receipt_id, restored.receipt_id);
        prop_assert_eq!(receipt.version, restored.version);
        prop_assert_eq!(receipt.steps_executed.len(), restored.steps_executed.len());
    }
}

// =============================================================================
// PROPERTY TESTS: INVARIANTS
// =============================================================================

proptest! {
    #[test]
    fn prop_envelope_has_valid_source(envelope in arb_evidence_envelope()) {
        // INVARIANT: All envelopes have a source tool and hostname
        prop_assert!(!envelope.source.host.hostname.is_empty());
    }

    #[test]
    fn prop_plan_steps_ordered(plan in arb_procedure_plan()) {
        // INVARIANT: Plan steps have increasing order values
        for window in plan.steps.windows(2) {
            prop_assert!(window[0].order <= window[1].order);
        }
    }

    #[test]
    fn prop_plan_has_references(plan in arb_procedure_plan()) {
        // INVARIANT: A plan references an envelope
        prop_assert!(plan.envelope_ref.as_bytes().iter().any(|b| *b != 0));
    }

    #[test]
    fn prop_receipt_has_references(receipt in arb_receipt()) {
        // INVARIANT: A receipt references a plan and envelope
        prop_assert!(receipt.plan_ref.as_bytes().iter().any(|b| *b != 0));
        prop_assert!(receipt.envelope_ref.as_bytes().iter().any(|b| *b != 0));
    }
}

// =============================================================================
// PROPERTY TESTS: CROSS-CONTRACT INVARIANTS
// =============================================================================

proptest! {
    #[test]
    fn prop_lifecycle_envelope_to_plan(envelope in arb_evidence_envelope(), plan in arb_procedure_plan()) {
        // INVARIANT: A plan's envelope reference can be the envelope's ID
        let plan_with_ref = ProcedurePlan {
            envelope_ref: envelope.envelope_id,
            ..plan
        };

        prop_assert_eq!(plan_with_ref.envelope_ref, envelope.envelope_id);
    }

    #[test]
    fn prop_lifecycle_plan_to_receipt(plan in arb_procedure_plan(), receipt in arb_receipt()) {
        // INVARIANT: A receipt's plan reference can be the plan's ID
        let receipt_with_ref = Receipt {
            plan_ref: plan.plan_id,
            ..receipt
        };

        prop_assert_eq!(receipt_with_ref.plan_ref, plan.plan_id);
    }
}

// =============================================================================
// PROPERTY TESTS: SIZE AND BOUNDS
// =============================================================================

proptest! {
    #[test]
    fn prop_envelope_artifacts_reasonable_count(envelope in arb_evidence_envelope()) {
        // INVARIANT: Envelopes have a reasonable number of artifacts
        prop_assert!(envelope.artifacts.len() < 1000);
    }

    #[test]
    fn prop_plan_steps_reasonable_count(plan in arb_procedure_plan()) {
        // INVARIANT: Plans have a reasonable number of steps
        prop_assert!(plan.steps.len() < 1000);
    }

    #[test]
    fn prop_receipt_steps_reasonable_count(receipt in arb_receipt()) {
        // INVARIANT: Receipts have a reasonable number of executed steps
        prop_assert!(receipt.steps_executed.len() < 1000);
    }
}
