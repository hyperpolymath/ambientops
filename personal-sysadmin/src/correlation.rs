// SPDX-License-Identifier: PMPL-1.0-or-later
//! Correlation ID support for cross-tool distributed tracing
//!
//! Correlation IDs allow tracking operations that span multiple tools:
//! - system-emergency-room → psa crisis
//! - psa diagnose → forum search → AI reasoning
//! - psa mesh sync across devices
//!
//! Format: corr-XXXXXXXXXXXXXXXX (corr- prefix + 16 hex chars)

use std::sync::OnceLock;

/// Global correlation ID for the current session
static CORRELATION_ID: OnceLock<String> = OnceLock::new();

/// Generate a new correlation ID
pub fn generate() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);

    // Use timestamp + random component for uniqueness
    let random: u64 = rand_simple();
    format!("corr-{:08x}{:08x}", (timestamp & 0xFFFFFFFF) as u32, random as u32)
}

/// Simple random number generator (no external deps)
fn rand_simple() -> u64 {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};

    let state = RandomState::new();
    let mut hasher = state.build_hasher();
    hasher.write_u64(std::process::id() as u64);
    hasher.finish()
}

/// Initialize the global correlation ID
/// Uses provided ID or generates a new one
pub fn init(provided: Option<String>) -> &'static str {
    CORRELATION_ID.get_or_init(|| {
        provided.unwrap_or_else(generate)
    })
}

/// Get the current correlation ID
pub fn get() -> Option<&'static str> {
    CORRELATION_ID.get().map(|s| s.as_str())
}

/// Create a tracing span with correlation ID
#[macro_export]
macro_rules! correlated_span {
    ($level:ident, $name:expr) => {
        tracing::$level!(
            correlation_id = %$crate::correlation::get().unwrap_or("none"),
            $name
        )
    };
    ($level:ident, $name:expr, $($field:tt)*) => {
        tracing::$level!(
            correlation_id = %$crate::correlation::get().unwrap_or("none"),
            $name,
            $($field)*
        )
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_format() {
        let id = generate();
        assert!(id.starts_with("corr-"));
        assert_eq!(id.len(), 21); // corr- (5) + 16 hex chars
    }

    #[test]
    fn test_generate_uniqueness() {
        let id1 = generate();
        std::thread::sleep(std::time::Duration::from_millis(1));
        let id2 = generate();
        assert_ne!(id1, id2);
    }
}
