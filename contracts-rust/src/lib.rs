// SPDX-License-Identifier: PMPL-1.0-or-later
//! AmbientOps contract types matching JSON schemas.
//!
//! Provides Rust structs for the core hospital-model data flow:
//! EvidenceEnvelope → ProcedurePlan → Receipt → SystemWeather

pub mod envelope;
pub mod plan;
pub mod receipt;
pub mod weather;
pub mod conversions;

pub use envelope::EvidenceEnvelope;
pub use plan::ProcedurePlan;
pub use receipt::Receipt;
pub use weather::SystemWeather;
