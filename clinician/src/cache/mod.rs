// SPDX-License-Identifier: PMPL-1.0-or-later
//! Dragonfly (Redis-compatible) cache layer for fast lookups
//!
//! When `cache` feature is enabled, connects to Redis/Dragonfly.
//! Falls back to no-op mode when unavailable or feature disabled.

#![allow(dead_code)]
#![allow(unused_variables)]

use anyhow::Result;
use std::time::Duration;

/// Cache client wrapping Dragonfly/Redis
pub struct Cache {
    config: CacheConfig,
    connected: bool,
    #[cfg(feature = "cache")]
    conn: Option<redis::aio::MultiplexedConnection>,
}

#[derive(Debug, Clone)]
pub struct CacheConfig {
    pub host: String,
    pub port: u16,
    pub prefix: String,
    pub default_ttl: Duration,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            host: "localhost".to_string(),
            port: 6379,
            prefix: "psa:".to_string(),
            default_ttl: Duration::from_secs(3600),
        }
    }
}

impl Cache {
    /// Create new cache connection.
    /// With `cache` feature: attempts Redis/Dragonfly, falls back to no-op.
    /// Without: always no-op mode.
    pub async fn new() -> Result<Self> {
        let config = CacheConfig::default();

        #[cfg(feature = "cache")]
        {
            let url = format!("redis://{}:{}", config.host, config.port);
            match redis::Client::open(url.as_str()) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(conn) => {
                            tracing::info!("Cache: Redis/Dragonfly connected at {}:{}", config.host, config.port);
                            return Ok(Self { config, connected: true, conn: Some(conn) });
                        }
                        Err(e) => {
                            tracing::warn!("Cache: Redis connection failed: {}, no-op fallback", e);
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!("Cache: Redis client error: {}, no-op fallback", e);
                }
            }

            return Ok(Self { config, connected: false, conn: None });
        }

        #[cfg(not(feature = "cache"))]
        {
            tracing::info!("Cache initialized (no-op mode)");
            Ok(Self { config, connected: false })
        }
    }

    /// Get cached value
    pub async fn get<T: serde::de::DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let full_key = format!("{}{}", self.config.prefix, key);
        tracing::trace!("Cache GET: {}", full_key);

        #[cfg(feature = "cache")]
        if let Some(ref conn) = self.conn {
            use redis::AsyncCommands;
            let mut conn = conn.clone();
            let val: Option<String> = conn.get(&full_key).await.unwrap_or(None);
            if let Some(json_str) = val {
                return Ok(serde_json::from_str(&json_str).ok());
            }
        }

        Ok(None)
    }

    /// Set cached value with TTL
    pub async fn set<T: serde::Serialize>(&self, key: &str, value: &T, ttl: Option<Duration>) -> Result<()> {
        let full_key = format!("{}{}", self.config.prefix, key);
        let ttl = ttl.unwrap_or(self.config.default_ttl);
        tracing::trace!("Cache SET: {} (TTL: {:?})", full_key, ttl);

        #[cfg(feature = "cache")]
        if let Some(ref conn) = self.conn {
            use redis::AsyncCommands;
            let mut conn = conn.clone();
            let json_str = serde_json::to_string(value)?;
            let _: () = conn.set_ex(&full_key, json_str, ttl.as_secs()).await
                .unwrap_or_default();
        }

        Ok(())
    }

    /// Delete cached value
    pub async fn delete(&self, key: &str) -> Result<()> {
        let full_key = format!("{}{}", self.config.prefix, key);
        tracing::trace!("Cache DEL: {}", full_key);

        #[cfg(feature = "cache")]
        if let Some(ref conn) = self.conn {
            use redis::AsyncCommands;
            let mut conn = conn.clone();
            let _: () = conn.del(&full_key).await.unwrap_or_default();
        }

        Ok(())
    }

    /// Cache system metrics for quick access
    pub async fn cache_metrics(&self, metrics: &SystemMetrics) -> Result<()> {
        self.set("metrics:current", metrics, Some(Duration::from_secs(10))).await
    }

    /// Get cached system metrics
    pub async fn get_metrics(&self) -> Result<Option<SystemMetrics>> {
        self.get("metrics:current").await
    }

    /// Cache solution lookup for fast retrieval
    pub async fn cache_solution_lookup(&self, problem_hash: &str, solution_id: &str) -> Result<()> {
        self.set(&format!("lookup:{}", problem_hash), &solution_id, None).await
    }

    /// Get cached solution lookup
    pub async fn get_solution_lookup(&self, problem_hash: &str) -> Result<Option<String>> {
        self.get(&format!("lookup:{}", problem_hash)).await
    }

    /// Check if connected to Redis
    pub fn is_connected(&self) -> bool {
        self.connected
    }
}

/// Cached system metrics
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SystemMetrics {
    pub cpu_usage: f32,
    pub memory_used: u64,
    pub memory_total: u64,
    pub disk_used: u64,
    pub disk_total: u64,
    pub load_avg: [f64; 3],
    pub timestamp: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_cache_noop_fallback() {
        let cache = Cache::new().await.unwrap();
        assert!(!cache.is_connected());

        // Get returns None in no-op mode
        let val: Option<String> = cache.get("nonexistent").await.unwrap();
        assert!(val.is_none());

        // Set and delete don't error
        cache.set("key", &"value", None).await.unwrap();
        cache.delete("key").await.unwrap();
    }
}
