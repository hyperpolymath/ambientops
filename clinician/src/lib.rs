// SPDX-License-Identifier: PMPL-1.0-or-later
//! Personal Sysadmin library
//!
//! Core components for the PSA system administration toolkit.

pub mod reasoning;
pub mod storage;
pub mod cache;
pub mod ai;
pub mod forum;
pub mod p2p;
pub mod rules;

/// Version of the PSA protocol for P2P compatibility
pub const PROTOCOL_VERSION: &str = "0.1.0";

/// Input validation for security - re-exported from validation module
pub mod validation;

/// Correlation ID support for cross-tool distributed tracing
pub mod correlation;

// Tools declared after correlation so crisis.rs can import it
pub mod tools;

/// Application directories
pub mod dirs {
    use directories::ProjectDirs;
    use std::path::PathBuf;

    pub fn project_dirs() -> Option<ProjectDirs> {
        ProjectDirs::from("com", "hyperpolymath", "personal-sysadmin")
    }

    pub fn config_dir() -> PathBuf {
        project_dirs()
            .map(|d| d.config_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from(".config/psa"))
    }

    pub fn data_dir() -> PathBuf {
        project_dirs()
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from(".local/share/psa"))
    }

    pub fn cache_dir() -> PathBuf {
        project_dirs()
            .map(|d| d.cache_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from(".cache/psa"))
    }
}
