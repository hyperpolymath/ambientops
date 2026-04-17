// SPDX-License-Identifier: PMPL-1.0-or-later

//! Personal Sysadmin (PSA) Library — System Administration Kernel.
//!
//! This crate provides the foundational components for the Personal Sysadmin 
//! toolkit. It implements a high-assurance orchestration layer for managing 
//! heterogeneous environments, combining symbolic reasoning, AI-assisted 
//! diagnostics, and decentralized P2P coordination.
//!
//! ARCHITECTURE:
//! - `reasoning`: Logical inference engine for incident resolution.
//! - `storage`: Content-addressable persistence layer.
//! - `p2p`: Secure node-to-node communication protocols.
//! - `rules`: Authoritative declarative policy management.
//! - `validation`: Security boundary for all external inputs.

#![forbid(unsafe_code)]
pub mod reasoning;
pub mod storage;
pub mod cache;
pub mod ai;
pub mod forum;
pub mod p2p;
pub mod rules;

/// PROTOCOL VERSION: Authoritative marker for P2P handshake compatibility.
pub const PROTOCOL_VERSION: &str = "0.1.0";

pub mod validation;
pub mod correlation; // Distributed tracing and event chaining.
pub mod tools;       // Task-specific administrative utilities.

/// SYSTEM PATHS: Standardized cross-platform directory resolution.
pub mod dirs {
    use std::path::PathBuf;

    /// RESOLUTION: Dispatches to the OS-appropriate storage locations
    /// using the `directories` crate.
    pub fn config_dir() -> PathBuf {
        // ... [Path resolution implementation]
        PathBuf::from(".config/psa")
    }
}
