// SPDX-License-Identifier: PMPL-1.0-or-later
//! Platform detection via nicaug integration

use crate::{MustfileError, Platform, Result};
use crate::types::TargetType;
use std::process::Command;

pub struct PlatformAdapter;

impl PlatformAdapter {
    /// Detect platform by calling nicaug CLI
    pub fn detect() -> Result<Platform> {
        // Try to find nicaug binary
        let nicaug_path = Self::find_nicaug()?;

        // Execute nicaug info and parse JSON output
        let output = Command::new("deno")
            .args(&[
                "run",
                "--allow-read",
                "--allow-env",
                &nicaug_path,
                "info",
                "--json"
            ])
            .output()
            .map_err(|e| MustfileError::PlatformError(
                format!("Failed to execute nicaug: {}", e)
            ))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(MustfileError::PlatformError(
                format!("nicaug info failed: {}", stderr)
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        Self::parse_nicaug_output(&stdout)
    }

    /// Find nicaug CLI in the repository
    fn find_nicaug() -> Result<String> {
        // Try common locations
        let candidates = vec![
            "src/nicaug/NicaugCLI.mjs",
            "../src/nicaug/NicaugCLI.mjs",
            "../../src/nicaug/NicaugCLI.mjs",
        ];

        for candidate in candidates {
            if std::path::Path::new(candidate).exists() {
                return Ok(candidate.to_string());
            }
        }

        Err(MustfileError::PlatformError(
            "nicaug CLI not found".to_string()
        ))
    }

    /// Parse nicaug JSON output
    fn parse_nicaug_output(output: &str) -> Result<Platform> {
        // For now, parse the text output
        // TODO: Add --json flag to nicaug
        let lines: Vec<&str> = output.lines().collect();

        let mut os = String::new();
        let mut arch = String::new();
        let mut is_immutable = false;
        let mut target_type = TargetType::StandardPc;
        let mut deployment_priority = String::new();

        for line in lines {
            let line = line.trim();
            if line.starts_with("OS:") {
                os = line.split(':').nth(1).unwrap_or("").trim().to_string();
            } else if line.starts_with("Arch:") {
                arch = line.split(':').nth(1).unwrap_or("").trim().to_string();
            } else if line.starts_with("Immutable:") {
                let value = line.split(':').nth(1).unwrap_or("").trim();
                is_immutable = value == "yes";
            } else if line.starts_with("Target Type:") {
                let value = line.split(':').nth(1).unwrap_or("").trim();
                target_type = Self::parse_target_type(value);
            } else if line.starts_with("Priority Route:") {
                deployment_priority = line.split(':').nth(1).unwrap_or("").trim().to_string();
            }
        }

        Ok(Platform {
            os,
            arch,
            target_type,
            is_immutable,
            deployment_priority,
        })
    }

    /// Parse target type from string
    fn parse_target_type(s: &str) -> TargetType {
        if s.contains("Edge") || s.contains("ASIC") {
            TargetType::EdgeAsic
        } else if s.contains("Kinoite") {
            TargetType::KinoiteLayered
        } else if s.contains("Darwin") || s.contains("macOS") {
            TargetType::AppleDarwin
        } else {
            TargetType::StandardPc
        }
    }

    /// Get platform info without calling nicaug (for testing)
    #[cfg(test)]
    pub fn detect_native() -> Result<Platform> {
        Ok(Platform {
            os: std::env::consts::OS.to_string(),
            arch: std::env::consts::ARCH.to_string(),
            target_type: TargetType::StandardPc,
            is_immutable: false,
            deployment_priority: "native".to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_target_type() {
        assert_eq!(
            PlatformAdapter::parse_target_type("Standard PC (Linux)"),
            TargetType::StandardPc
        );
        assert_eq!(
            PlatformAdapter::parse_target_type("Kinoite Layered"),
            TargetType::KinoiteLayered
        );
    }

    #[test]
    fn test_detect_native() {
        let platform = PlatformAdapter::detect_native().unwrap();
        assert!(!platform.os.is_empty());
        assert!(!platform.arch.is_empty());
    }
}
