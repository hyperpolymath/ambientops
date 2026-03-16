// SPDX-License-Identifier: PMPL-1.0-or-later
//! Input validation for security
//!
//! Provides validation functions to prevent command injection and path traversal attacks.

use std::path::Path;

/// Characters that are dangerous in shell contexts
const SHELL_DANGEROUS_CHARS: &[char] = &[
    ';', '|', '&', '$', '`', '(', ')', '{', '}', '[', ']',
    '<', '>', '\n', '\r', '*', '?', '~', '!', '#', '\'', '"', '\\',
];

/// Validate a path is safe for use in shell commands
/// Returns error if path contains dangerous characters or traversal attempts
pub fn validate_safe_path(path: &str) -> Result<&str, &'static str> {
    if path.is_empty() {
        return Err("Empty path not allowed");
    }

    // Check for shell metacharacters
    for c in SHELL_DANGEROUS_CHARS {
        if path.contains(*c) {
            return Err("Path contains dangerous shell character");
        }
    }

    // Check for path traversal beyond expected scope
    if path.contains("..") {
        // Allow .. only within home directory
        let home = std::env::var("HOME").unwrap_or_default();
        let canonical = Path::new(path);
        if !canonical.starts_with(&home) && !canonical.starts_with("/tmp") {
            return Err("Path traversal not allowed outside home/tmp");
        }
    }

    Ok(path)
}

/// Validate a service name (alphanumeric, dash, underscore, dot)
pub fn validate_service_name(name: &str) -> Result<&str, &'static str> {
    if name.is_empty() {
        return Err("Empty service name not allowed");
    }

    for c in name.chars() {
        let is_safe = c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '@';
        if !is_safe {
            return Err("Service name contains invalid character");
        }
    }

    Ok(name)
}

/// Validate a process name pattern
/// Used by rules module for process matching
#[allow(dead_code)]
pub fn validate_pattern(pattern: &str) -> Result<&str, &'static str> {
    if pattern.is_empty() {
        return Err("Empty pattern not allowed");
    }

    // Allow alphanumeric, dash, underscore, dot, and safe glob chars
    for c in pattern.chars() {
        let is_safe = c.is_ascii_alphanumeric()
            || c == '-' || c == '_' || c == '.' || c == '*' || c == '?';
        if !is_safe {
            return Err("Pattern contains invalid character");
        }
    }

    Ok(pattern)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_safe_path() {
        assert!(validate_safe_path("/home/user/file.txt").is_ok());
        assert!(validate_safe_path("/tmp/test").is_ok());
        assert!(validate_safe_path("relative/path").is_ok());
    }

    #[test]
    fn test_dangerous_path() {
        assert!(validate_safe_path("/tmp/test; rm -rf /").is_err());
        assert!(validate_safe_path("/tmp/test | cat /etc/passwd").is_err());
        assert!(validate_safe_path("/tmp/$(whoami)").is_err());
        assert!(validate_safe_path("/tmp/`id`").is_err());
        assert!(validate_safe_path("").is_err());
    }

    #[test]
    fn test_service_name() {
        assert!(validate_service_name("nginx").is_ok());
        assert!(validate_service_name("systemd-resolved").is_ok());
        assert!(validate_service_name("user@1000").is_ok());
        assert!(validate_service_name("nginx; rm -rf /").is_err());
    }

    #[test]
    fn test_pattern() {
        assert!(validate_pattern("nginx*").is_ok());
        assert!(validate_pattern("*.service").is_ok());
        assert!(validate_pattern("test_process").is_ok());
        assert!(validate_pattern("bad$(id)").is_err());
    }
}
