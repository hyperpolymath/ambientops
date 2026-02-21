// SPDX-License-Identifier: PMPL-1.0-or-later
//! Mustfile parser (TOML format)

use crate::{Mustfile, MustfileError, Result};
use std::fs;
use std::path::Path;

pub struct MustfileParser;

impl MustfileParser {
    /// Parse a Mustfile from a file path
    pub fn parse_file<P: AsRef<Path>>(path: P) -> Result<Mustfile> {
        let path = path.as_ref();

        if !path.exists() {
            return Err(MustfileError::ParseError(
                format!("Mustfile not found: {}", path.display())
            ));
        }

        let content = fs::read_to_string(path)?;
        Self::parse_str(&content)
    }

    /// Parse a Mustfile from a string
    pub fn parse_str(content: &str) -> Result<Mustfile> {
        toml::from_str(content).map_err(|e| {
            MustfileError::ParseError(format!("Invalid TOML: {}", e))
        })
    }

    /// Find Mustfile in current directory or parent directories
    pub fn find_mustfile() -> Result<Mustfile> {
        let candidates = vec![
            "Mustfile",
            "mustfile.toml",
            "Mustfile.toml",
        ];

        let mut current_dir = std::env::current_dir()?;

        loop {
            for candidate in &candidates {
                let path = current_dir.join(candidate);
                if path.exists() {
                    return Self::parse_file(&path);
                }
            }

            // Move to parent directory
            if !current_dir.pop() {
                break;
            }
        }

        Err(MustfileError::ParseError(
            "No Mustfile found in current directory or parents".to_string()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_basic_mustfile() {
        let toml = r#"
[project]
name = "test-project"
version = "1.0.0"

[tasks.build]
run = ["cargo build --release"]

[requirements]
must_have = ["Cargo.toml"]
"#;

        let mustfile = MustfileParser::parse_str(toml).unwrap();
        assert_eq!(mustfile.project.name, "test-project");
        assert_eq!(mustfile.project.version, "1.0.0");
        assert!(mustfile.tasks.contains_key("build"));
        assert_eq!(mustfile.requirements.must_have.len(), 1);
    }

    #[test]
    fn test_parse_with_dependencies() {
        let toml = r#"
[project]
name = "test"
version = "0.1.0"

[tasks.test]
run = ["cargo test"]
depends_on = ["build"]

[tasks.build]
run = ["cargo build"]
"#;

        let mustfile = MustfileParser::parse_str(toml).unwrap();
        let test_task = mustfile.tasks.get("test").unwrap();
        assert_eq!(test_task.depends_on, vec!["build"]);
    }
}
