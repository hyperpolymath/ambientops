// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
//! Benchmarks for AmbientOps contract types.
//!
//! Measures serialization, deserialization, and creation performance.

use ambientops_contracts::*;
use chrono::Utc;
use criterion::{black_box, criterion_group, criterion_main, Criterion};
use uuid::Uuid;

// =============================================================================
// FIXTURES
// =============================================================================

fn create_sample_envelope() -> EvidenceEnvelope {
    EvidenceEnvelope {
        version: "1.0.0".to_string(),
        envelope_id: Uuid::new_v4(),
        created_at: Utc::now(),
        source: envelope::EnvelopeSource {
            tool: envelope::SourceTool::Ambient,
            tool_version: Some("1.0.0".to_string()),
            host: envelope::HostInfo {
                hostname: "test-host".to_string(),
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
                    value: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                        .to_string(),
                }),
                size_bytes: Some(1024),
                mime_type: Some("text/plain".to_string()),
                description: Some("System log snapshot".to_string()),
            },
            envelope::Artifact {
                artifact_id: Uuid::new_v4(),
                artifact_type: envelope::ArtifactType::Config,
                path: "/etc/config".to_string(),
                hash: None,
                size_bytes: Some(2048),
                mime_type: None,
                description: None,
            },
        ],
        findings: vec![],
        metrics: None,
        redaction_profile: envelope::RedactionProfile::Standard,
        provenance: None,
    }
}

fn create_sample_plan(envelope_id: Uuid) -> ProcedurePlan {
    ProcedurePlan {
        version: "1.0.0".to_string(),
        plan_id: Uuid::new_v4(),
        created_at: Utc::now(),
        envelope_ref: envelope_id,
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
    }
}

fn create_sample_receipt(plan_id: Uuid, envelope_id: Uuid) -> Receipt {
    Receipt {
        version: "1.0.0".to_string(),
        receipt_id: Uuid::new_v4(),
        created_at: Utc::now(),
        completed_at: Some(Utc::now()),
        plan_ref: plan_id,
        envelope_ref: envelope_id,
        status: receipt::ReceiptStatus::Completed,
        summary: Some(receipt::ReceiptSummary {
            title: Some("Cleanup completed successfully".to_string()),
            description: Some("All steps executed without errors".to_string()),
            items_checked: Some(2),
            items_changed: Some(1),
            items_unchanged: Some(1),
            items_failed: Some(0),
            space_recovered_bytes: Some(5242880),
            duration_seconds: Some(15.5),
        }),
        steps_executed: vec![
            receipt::StepResult {
                step_id: "step_01".to_string(),
                step_ref: Some("step_01".to_string()),
                status: receipt::StepStatus::Success,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
                what_changed: Some("Created backup archive".to_string()),
                why_changed: Some("Preserving original configuration".to_string()),
                before: Some(serde_json::json!({"backup_exists": false})),
                after: Some(serde_json::json!({"backup_exists": true})),
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
    }
}

fn create_sample_weather() -> SystemWeather {
    SystemWeather {
        version: "1.0.0".to_string(),
        timestamp: Utc::now(),
        state: weather::WeatherState::Calm,
        summary: "System health is optimal".to_string(),
        details: Some("All monitored systems are operating normally".to_string()),
        categories: None,
        evidence_pointers: vec![
            weather::EvidencePointer {
                pointer_type: weather::EvidenceType::Envelope,
                reference: Uuid::new_v4().to_string(),
                label: Some("Initial scan".to_string()),
            },
        ],
        notifications: None,
        actions: vec![],
        trends: None,
        source: None,
    }
}

// =============================================================================
// ENVELOPE BENCHMARKS
// =============================================================================

fn bench_envelope_creation(c: &mut Criterion) {
    c.bench_function("envelope_creation", |b| {
        b.iter(|| {
            black_box(create_sample_envelope());
        });
    });
}

fn bench_envelope_serialization(c: &mut Criterion) {
    let envelope = black_box(create_sample_envelope());
    c.bench_function("envelope_serialization", |b| {
        b.iter(|| {
            serde_json::to_string(&envelope).unwrap();
        });
    });
}

fn bench_envelope_deserialization(c: &mut Criterion) {
    let envelope = create_sample_envelope();
    let json = serde_json::to_string(&envelope).unwrap();
    let json = black_box(json);

    c.bench_function("envelope_deserialization", |b| {
        b.iter(|| {
            let _: EvidenceEnvelope = serde_json::from_str(&json).unwrap();
        });
    });
}

// =============================================================================
// PLAN BENCHMARKS
// =============================================================================

fn bench_plan_creation(c: &mut Criterion) {
    let envelope_id = black_box(Uuid::new_v4());
    c.bench_function("plan_creation", |b| {
        b.iter(|| {
            black_box(create_sample_plan(envelope_id));
        });
    });
}

fn bench_plan_serialization(c: &mut Criterion) {
    let envelope_id = Uuid::new_v4();
    let plan = black_box(create_sample_plan(envelope_id));
    c.bench_function("plan_serialization", |b| {
        b.iter(|| {
            serde_json::to_string(&plan).unwrap();
        });
    });
}

fn bench_plan_deserialization(c: &mut Criterion) {
    let envelope_id = Uuid::new_v4();
    let plan = create_sample_plan(envelope_id);
    let json = serde_json::to_string(&plan).unwrap();
    let json = black_box(json);

    c.bench_function("plan_deserialization", |b| {
        b.iter(|| {
            let _: ProcedurePlan = serde_json::from_str(&json).unwrap();
        });
    });
}

// =============================================================================
// RECEIPT BENCHMARKS
// =============================================================================

fn bench_receipt_creation(c: &mut Criterion) {
    let plan_id = black_box(Uuid::new_v4());
    let envelope_id = black_box(Uuid::new_v4());
    c.bench_function("receipt_creation", |b| {
        b.iter(|| {
            black_box(create_sample_receipt(plan_id, envelope_id));
        });
    });
}

fn bench_receipt_serialization(c: &mut Criterion) {
    let plan_id = Uuid::new_v4();
    let envelope_id = Uuid::new_v4();
    let receipt = black_box(create_sample_receipt(plan_id, envelope_id));
    c.bench_function("receipt_serialization", |b| {
        b.iter(|| {
            serde_json::to_string(&receipt).unwrap();
        });
    });
}

fn bench_receipt_deserialization(c: &mut Criterion) {
    let plan_id = Uuid::new_v4();
    let envelope_id = Uuid::new_v4();
    let receipt = create_sample_receipt(plan_id, envelope_id);
    let json = serde_json::to_string(&receipt).unwrap();
    let json = black_box(json);

    c.bench_function("receipt_deserialization", |b| {
        b.iter(|| {
            let _: Receipt = serde_json::from_str(&json).unwrap();
        });
    });
}

// =============================================================================
// WEATHER BENCHMARKS
// =============================================================================

fn bench_weather_creation(c: &mut Criterion) {
    c.bench_function("weather_creation", |b| {
        b.iter(|| {
            black_box(create_sample_weather());
        });
    });
}

fn bench_weather_serialization(c: &mut Criterion) {
    let weather = black_box(create_sample_weather());
    c.bench_function("weather_serialization", |b| {
        b.iter(|| {
            serde_json::to_string(&weather).unwrap();
        });
    });
}

fn bench_weather_deserialization(c: &mut Criterion) {
    let weather = create_sample_weather();
    let json = serde_json::to_string(&weather).unwrap();
    let json = black_box(json);

    c.bench_function("weather_deserialization", |b| {
        b.iter(|| {
            let _: SystemWeather = serde_json::from_str(&json).unwrap();
        });
    });
}

// =============================================================================
// BULK OPERATION BENCHMARKS
// =============================================================================

fn bench_envelope_bulk_creation(c: &mut Criterion) {
    c.bench_function("envelope_bulk_creation_100", |b| {
        b.iter(|| {
            for _ in 0..100 {
                black_box(create_sample_envelope());
            }
        });
    });
}

fn bench_plan_bulk_creation(c: &mut Criterion) {
    c.bench_function("plan_bulk_creation_100", |b| {
        b.iter(|| {
            let envelope_id = Uuid::new_v4();
            for _ in 0..100 {
                black_box(create_sample_plan(envelope_id));
            }
        });
    });
}

// =============================================================================
// REGISTER BENCHMARKS
// =============================================================================

criterion_group!(
    envelope_benches,
    bench_envelope_creation,
    bench_envelope_serialization,
    bench_envelope_deserialization,
    bench_envelope_bulk_creation,
);

criterion_group!(
    plan_benches,
    bench_plan_creation,
    bench_plan_serialization,
    bench_plan_deserialization,
    bench_plan_bulk_creation,
);

criterion_group!(
    receipt_benches,
    bench_receipt_creation,
    bench_receipt_serialization,
    bench_receipt_deserialization,
);

criterion_group!(
    weather_benches,
    bench_weather_creation,
    bench_weather_serialization,
    bench_weather_deserialization,
);

criterion_main!(envelope_benches, plan_benches, receipt_benches, weather_benches);
