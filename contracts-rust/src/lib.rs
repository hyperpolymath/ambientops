// SPDX-License-Identifier: PMPL-1.0-or-later

//! AmbientOps Contracts — High-Assurance Domain Schemas.
//!
//! This crate provides the authoritative Rust implementations of the 
//! AmbientOps "Hospital Model" data protocols. It ensures that 
//! administrative and operational data maintains structural integrity 
//! as it flows through the ecosystem.
//!
//! DATA FLOW ARCHITECTURE:
//! 1. **EvidenceEnvelope**: Sealed container for raw audit data (The "Scan").
//! 2. **ProcedurePlan**: Declarative blueprint for remediation (The "Prescription").
//! 3. **Receipt**: Verified record of an applied procedure (The "Surgery").
//! 4. **SystemWeather**: Aggregate health signal for the entire fleet (The "Vitals").
//!
//! ADDITIONAL SCHEMAS:
//! - `MessageIntent`: Semantic intent markers for inter-service communication.
//! - `PackManifest`: Specification for verified artifact containers.
//! - `RunBundle`: Self-contained execution packages for nomadic deployment.

pub mod envelope;
pub mod plan;
pub mod receipt;
pub mod weather;
pub mod conversions; // Logic for transforming between different contract stages.
pub mod message_intent;
pub mod pack_manifest;
pub mod ambient_payload;
pub mod run_bundle;

// RE-EXPORTS: Canonical types for consuming AmbientOps services.
pub use envelope::EvidenceEnvelope;
pub use plan::ProcedurePlan;
pub use receipt::Receipt;
pub use weather::SystemWeather;
pub use message_intent::MessageIntent;
pub use pack_manifest::PackManifest;
pub use ambient_payload::AmbientPayload;
pub use run_bundle::RunBundle;
