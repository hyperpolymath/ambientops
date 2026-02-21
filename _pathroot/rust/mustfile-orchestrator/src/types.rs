// SPDX-License-Identifier: PMPL-1.0-or-later
//! Core types for Mustfile orchestration

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Mustfile represents a complete deployment specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mustfile {
    /// Project metadata
    pub project: ProjectMetadata,

    /// Deployment tasks
    #[serde(default)]
    pub tasks: HashMap<String, Task>,

    /// Global requirements
    #[serde(default)]
    pub requirements: Requirements,

    /// Variables for templating
    #[serde(default)]
    pub variables: HashMap<String, String>,
}

impl Mustfile {
    /// Validate all requirements in the Mustfile
    pub fn validate_requirements(&self) -> crate::Result<()> {
        // Check must_have files exist
        for file in &self.requirements.must_have {
            if !std::path::Path::new(file).exists() {
                return Err(crate::MustfileError::RequirementError(
                    format!("Required file missing: {}", file)
                ));
            }
        }

        // Check must_not_have files don't exist
        for file in &self.requirements.must_not_have {
            if std::path::Path::new(file).exists() {
                return Err(crate::MustfileError::RequirementError(
                    format!("Forbidden file exists: {}", file)
                ));
            }
        }

        Ok(())
    }
}

/// Project metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMetadata {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub description: Option<String>,
}

/// Deployment task
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    /// Task description
    #[serde(default)]
    pub description: Option<String>,

    /// Commands to run
    pub run: Vec<String>,

    /// Task-specific requirements
    #[serde(default)]
    pub requirements: Requirements,

    /// Dependencies (other tasks that must run first)
    #[serde(default)]
    pub depends_on: Vec<String>,
}

/// Requirements for files and content
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Requirements {
    /// Files that must exist
    #[serde(default)]
    pub must_have: Vec<String>,

    /// Files that must not exist
    #[serde(default)]
    pub must_not_have: Vec<String>,

    /// Content requirements (file must contain string)
    #[serde(default)]
    pub content: Vec<ContentRequirement>,
}

/// Content requirement (file must contain specific text)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentRequirement {
    pub file: String,
    pub contains: String,
}

/// Platform detection result from nicaug
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Platform {
    pub os: String,
    pub arch: String,
    pub target_type: TargetType,
    pub is_immutable: bool,
    pub deployment_priority: String,
}

/// Target type from nicaug classification
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TargetType {
    EdgeAsic,
    KinoiteLayered,
    AppleDarwin,
    StandardPc,
}

impl Platform {
    /// Get the recommended package manager for this platform
    pub fn package_manager(&self) -> &'static str {
        match self.target_type {
            TargetType::EdgeAsic => "static",
            TargetType::KinoiteLayered => "rpm-ostree",
            TargetType::AppleDarwin => "brew",
            TargetType::StandardPc => {
                if self.os.contains("debian") || self.os.contains("ubuntu") {
                    "nala"
                } else if self.os.contains("fedora") {
                    "dnf"
                } else if self.os.contains("arch") {
                    "pacman"
                } else {
                    "unknown"
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_package_manager() {
        let platform = Platform {
            os: "linux".to_string(),
            arch: "x86_64".to_string(),
            target_type: TargetType::KinoiteLayered,
            is_immutable: true,
            deployment_priority: "rpm-ostree".to_string(),
        };

        assert_eq!(platform.package_manager(), "rpm-ostree");
    }
}
