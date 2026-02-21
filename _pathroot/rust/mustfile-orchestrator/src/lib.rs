// SPDX-License-Identifier: PMPL-1.0-or-later
//! Mustfile Orchestration Engine
//!
//! Bridges nicaug (platform detection/command generation) with must (deployment execution).
//! Parses Mustfiles, validates requirements, and orchestrates multi-platform deployments.

pub mod parser;
pub mod platform;
pub mod executor;
pub mod types;

pub use parser::MustfileParser;
pub use platform::PlatformAdapter;
pub use executor::DeploymentExecutor;
pub use types::{Mustfile, Task, Requirements, Platform, TargetType};

use thiserror::Error;

#[derive(Error, Debug)]
pub enum MustfileError {
    #[error("Failed to parse Mustfile: {0}")]
    ParseError(String),

    #[error("Platform detection failed: {0}")]
    PlatformError(String),

    #[error("Requirement check failed: {0}")]
    RequirementError(String),

    #[error("Deployment failed: {0}")]
    DeploymentError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("TOML parse error: {0}")]
    TomlError(#[from] toml::de::Error),
}

pub type Result<T> = std::result::Result<T, MustfileError>;

/// Orchestrate a complete Mustfile deployment
pub async fn orchestrate(mustfile_path: &str) -> Result<()> {
    // 1. Parse Mustfile
    let mustfile = MustfileParser::parse_file(mustfile_path)?;

    // 2. Detect platform via nicaug
    let platform = PlatformAdapter::detect()?;

    // 3. Validate requirements
    mustfile.validate_requirements()?;

    // 4. Execute deployment
    let executor = DeploymentExecutor::new(platform);
    executor.deploy(&mustfile).await?;

    Ok(())
}
