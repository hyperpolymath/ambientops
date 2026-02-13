// SPDX-License-Identifier: PMPL-1.0-or-later
//! AmbientOps contract types matching JSON schemas.
//!
//! Provides Rust structs for the core hospital-model data flow:
//! EvidenceEnvelope → ProcedurePlan → Receipt → SystemWeather
//!
//! Plus Ward/OR schemas:
//! MessageIntent, PackManifest, AmbientPayload, RunBundle

pub mod envelope;
pub mod plan;
pub mod receipt;
pub mod weather;
pub mod conversions;
pub mod message_intent;
pub mod pack_manifest;
pub mod ambient_payload;
pub mod run_bundle;

pub use envelope::EvidenceEnvelope;
pub use plan::ProcedurePlan;
pub use receipt::Receipt;
pub use weather::SystemWeather;
pub use message_intent::MessageIntent;
pub use pack_manifest::PackManifest;
pub use ambient_payload::AmbientPayload;
pub use run_bundle::RunBundle;
