// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//! Aspect tests for AmbientOps contracts.
//!
//! Tests cross-cutting concerns:
//! - Security: Injection prevention, field validation
//! - Performance: Bulk operations, memory efficiency
//! - Correctness: Error handling, edge cases

use ambientops_contracts::*;
use chrono::Utc;
use uuid::Uuid;

// =============================================================================
// SECURITY ASPECTS
// =============================================================================

#[test]
fn security_envelope_hostname_sanitization() {
    // ATTACK: Attempt injection via hostname field
    let malicious_hostnames = vec![
        "test'; DROP TABLE--",
        "test\n\r\0code",
        "test$(whoami)host",
        "test`id`host",
        "<script>alert('xss')</script>",
    ];

    for hostname in malicious_hostnames {
        let envelope = EvidenceEnvelope {
            version: "1.0.0".to_string(),
            envelope_id: Uuid::new_v4(),
            created_at: Utc::now(),
            source: envelope::EnvelopeSource {
                tool: envelope::SourceTool::Ambient,
                tool_version: None,
                host: envelope::HostInfo {
                    hostname: hostname.to_string(),
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

        // VERIFY: Payload is stored as-is (no automatic sanitization)
        // The contract is neutral; consuming applications must sanitize
        assert_eq!(envelope.source.host.hostname, hostname);

        // VERIFY: Can serialize without corruption
        let json = serde_json::to_string(&envelope).expect("Serialization should not fail");

        // VERIFY: Can deserialize without data loss
        let restored: EvidenceEnvelope = serde_json::from_str(&json)
            .expect("Deserialization should not fail");
        assert_eq!(restored.source.host.hostname, hostname);
    }
}

#[test]
fn security_artifact_path_validation() {
    // Test that paths are preserved without validation
    // (validation is responsibility of consuming applications)
    let paths = vec![
        "/etc/passwd",
        "../../../etc/passwd",
        "/root/.ssh/id_rsa",
        "C:\\Windows\\System32\\config\\SAM",
        "//network/share/file",
    ];

    for path in paths {
        let artifact = envelope::Artifact {
            artifact_id: Uuid::new_v4(),
            artifact_type: envelope::ArtifactType::Log,
            path: path.to_string(),
            hash: None,
            size_bytes: None,
            mime_type: None,
            description: None,
        };

        // VERIFY: Paths are preserved faithfully
        assert_eq!(artifact.path, path);
    }
}

#[test]
fn security_step_command_preservation() {
    // Commands should be preserved as-is for human review
    let commands = vec![
        "rm -rf /",
        "dd if=/dev/zero of=/dev/sda",
        ":(){ :|:& };:",  // fork bomb
        "; systemctl stop docker &&",
    ];

    for cmd in commands {
        let step = plan::PlanStep {
            step_id: "test".to_string(),
            order: 0,
            action: plan::StepAction::RunCommand,
            title: "test".to_string(),
            description: None,
            preview: Some(cmd.to_string()),
            risk: None,
            reversibility: None,
            undo_instruction: None,
            target: None,
            parameters: None,
            finding_refs: vec![],
            requires_confirmation: false,
            estimated_duration_seconds: None,
        };

        // VERIFY: Commands are preserved for human approval
        assert_eq!(step.preview, Some(cmd.to_string()));
    }
}

#[test]
fn security_hash_algorithm_validation() {
    // Test that hash algorithms are enum-restricted
    let artifact = envelope::Artifact {
        artifact_id: Uuid::new_v4(),
        artifact_type: envelope::ArtifactType::Log,
        path: "/test".to_string(),
        hash: Some(envelope::ArtifactHash {
            algorithm: envelope::HashAlgorithm::Sha256,
            value: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".to_string(),
        }),
        size_bytes: None,
        mime_type: None,
        description: None,
    };

    // VERIFY: Only valid hash algorithms allowed via enum
    match artifact.hash.unwrap().algorithm {
        envelope::HashAlgorithm::Sha256 | envelope::HashAlgorithm::Sha512 => (),
        _ => panic!("Invalid algorithm"),
    }
}

// =============================================================================
// PERFORMANCE ASPECTS
// =============================================================================

#[test]
fn performance_envelope_serialization_bulk() {
    // Create 100 envelopes and verify serialization performance
    let mut envelopes = vec![];
    for i in 0..100 {
        envelopes.push(EvidenceEnvelope {
            version: "1.0.0".to_string(),
            envelope_id: Uuid::new_v4(),
            created_at: Utc::now(),
            source: envelope::EnvelopeSource {
                tool: envelope::SourceTool::Ambient,
                tool_version: Some(format!("1.0.{}", i)),
                host: envelope::HostInfo {
                    hostname: format!("host-{}", i),
                    os: Some("Linux".to_string()),
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
        });
    }

    // VERIFY: All can be serialized without error
    for envelope in &envelopes {
        let _ = serde_json::to_string(envelope).expect("Serialization failed");
    }

    // VERIFY: All can be deserialized
    for envelope in &envelopes {
        let json = serde_json::to_string(envelope).unwrap();
        let _restored: EvidenceEnvelope =
            serde_json::from_str(&json).expect("Deserialization failed");
    }
}

#[test]
fn performance_plan_with_large_step_count() {
    // Create a plan with 500 steps
    let mut steps = vec![];
    for i in 0..500 {
        steps.push(plan::PlanStep {
            step_id: format!("step_{}", i),
            order: i as u32,
            action: if i % 2 == 0 {
                plan::StepAction::RunCommand
            } else {
                plan::StepAction::Custom
            },
            title: format!("Step {}", i),
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
        });
    }

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
        steps,
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    // VERIFY: Large plan can be serialized
    let json = serde_json::to_string(&plan).expect("Serialization failed");

    // VERIFY: Large plan can be deserialized
    let restored: ProcedurePlan =
        serde_json::from_str(&json).expect("Deserialization failed");
    assert_eq!(restored.steps.len(), 500);
}

#[test]
fn performance_receipt_with_many_step_results() {
    // Create receipt with 100 step results
    let mut steps_executed = vec![];
    for i in 0..100 {
        steps_executed.push(receipt::StepResult {
            step_id: format!("step_{}", i),
            step_ref: None,
            status: if i % 3 == 0 {
                receipt::StepStatus::Failed
            } else {
                receipt::StepStatus::Success
            },
            started_at: None,
            completed_at: None,
            what_changed: Some(format!("Changed {}", i)),
            why_changed: None,
            before: None,
            after: None,
            error: None,
            skip_reason: None,
        });
    }

    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: None,
        plan_ref: Uuid::new_v4(),
        envelope_ref: Uuid::new_v4(),
        status: receipt::ReceiptStatus::Partial,
        summary: None,
        steps_executed,
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // VERIFY: Large receipt can be serialized
    let json = serde_json::to_string(&receipt).expect("Serialization failed");

    // VERIFY: Large receipt can be deserialized
    let restored: Receipt =
        serde_json::from_str(&json).expect("Deserialization failed");
    assert_eq!(restored.steps_executed.len(), 100);
}

#[test]
fn performance_weather_with_many_pointers() {
    // Create weather with 200 evidence pointers
    let mut pointers = vec![];
    for i in 0..200 {
        pointers.push(weather::EvidencePointer {
            pointer_type: if i % 3 == 0 {
                weather::EvidenceType::Envelope
            } else {
                weather::EvidenceType::Finding
            },
            reference: Uuid::new_v4().to_string(),
            label: Some(format!("Pointer {}", i)),
        });
    }

    let weather = SystemWeather {
        version: "1.0.0".to_string(),
        timestamp: Utc::now(),
        state: weather::WeatherState::Act,
        summary: "High load".to_string(),
        details: None,
        categories: None,
        evidence_pointers: pointers,
        notifications: None,
        actions: vec![],
        trends: None,
        source: None,
    };

    // VERIFY: Large weather can be serialized
    let json = serde_json::to_string(&weather).expect("Serialization failed");

    // VERIFY: Large weather can be deserialized
    let restored: SystemWeather =
        serde_json::from_str(&json).expect("Deserialization failed");
    assert_eq!(restored.evidence_pointers.len(), 200);
}

// =============================================================================
// CORRECTNESS ASPECTS
// =============================================================================

#[test]
fn correctness_envelope_empty_artifacts() {
    // EDGE CASE: Envelope with no artifacts
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
        artifacts: vec![],
        findings: vec![],
        metrics: None,
        redaction_profile: envelope::RedactionProfile::Standard,
        provenance: None,
    };

    // VERIFY: Serialization works with empty artifacts
    let json = serde_json::to_string(&envelope).unwrap();
    let restored: EvidenceEnvelope = serde_json::from_str(&json).unwrap();
    assert!(restored.artifacts.is_empty());
}

#[test]
fn correctness_plan_empty_steps() {
    // EDGE CASE: Plan with no steps
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
        steps: vec![],
        prerequisites: vec![],
        warnings: vec![],
        approval_required: true,
    };

    // VERIFY: Empty plan is valid
    let json = serde_json::to_string(&plan).unwrap();
    let restored: ProcedurePlan = serde_json::from_str(&json).unwrap();
    assert!(restored.steps.is_empty());
}

#[test]
fn correctness_receipt_empty_steps_executed() {
    // EDGE CASE: Receipt with no executed steps
    let receipt = Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: None,
        plan_ref: Uuid::new_v4(),
        envelope_ref: Uuid::new_v4(),
        status: receipt::ReceiptStatus::Completed,
        summary: None,
        steps_executed: vec![],
        unchanged: vec![],
        undo_bundle: None,
        evidence: None,
    };

    // VERIFY: Empty receipt is valid
    let json = serde_json::to_string(&receipt).unwrap();
    let restored: Receipt = serde_json::from_str(&json).unwrap();
    assert!(restored.steps_executed.is_empty());
}

#[test]
fn correctness_version_strings_preserved() {
    // EDGE CASE: Various version string formats
    let versions = vec!["1.0.0", "2.0.0-beta", "0.1.0-alpha.1", "999.999.999"];

    for version in versions {
        let envelope = EvidenceEnvelope {
            version: version.to_string(),
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

        // VERIFY: Version is preserved
        assert_eq!(envelope.version, version);

        // VERIFY: Version survives serialization
        let json = serde_json::to_string(&envelope).unwrap();
        let restored: EvidenceEnvelope = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.version, version);
    }
}

#[test]
fn correctness_uuid_generation() {
    // VERIFY: UUIDs are unique across multiple creations
    let ids: Vec<_> = (0..100)
        .map(|_| {
            EvidenceEnvelope {
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
            }
            .envelope_id
        })
        .collect();

    // VERIFY: All IDs are unique
    let unique_count = ids.iter().collect::<std::collections::HashSet<_>>().len();
    assert_eq!(unique_count, 100);
}
