// SPDX-License-Identifier: MPL-2.0
//! VeriSimDB-backed cache layer for fast key/value lookups.
//!
//! Replaces the previous Dragonfly/Redis stub.  Values are stored as
//! VeriSimDB hexads with the cache key in the `intentional` modality and
//! the serialised value in `contextual`.  TTL semantics are advisory: the
//! expiry timestamp is recorded in `temporal` but eviction depends on the
//! VeriSimDB instance's own TTL support; callers must not rely on hard
//! expiry guarantees.

use anyhow::{Context, Result};
use std::time::Duration;

// ── wire types ────────────────────────────────────────────────────────────────

/// Body for POST /api/v1/hexads.
#[derive(Debug, serde::Serialize)]
struct HexadRequest {
    modalities: CacheHexadModalities,
}

/// VeriSimDB modality slots used by the cache layer.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct CacheHexadModalities {
    /// Human-readable origin tag, always `"psa-cache"`.
    perceptual: String,
    /// Namespace-prefixed cache key, e.g. `psa:metrics:current`.
    conceptual: String,
    /// JSON-serialised cached value.
    contextual: String,
    /// ISO-8601 expiry timestamp (or `"never"`).
    temporal: String,
    /// TTL in seconds as a decimal string.
    procedural: String,
    /// Full cache key (same as `conceptual`) for direct lookup via VCL.
    intentional: String,
}

/// Minimal hexad response shape.
#[derive(Debug, serde::Deserialize)]
struct HexadResponse {
    id: String,
    modalities: CacheHexadModalities,
}

/// VCL query results wrapper.
#[derive(Debug, serde::Deserialize)]
struct QueryResponse {
    results: Vec<HexadResponse>,
}

// ── config ────────────────────────────────────────────────────────────────────

/// Configuration for the VeriSimDB cache client.
#[derive(Debug, Clone)]
pub struct CacheConfig {
    /// Base URL of the VeriSimDB instance, e.g. `http://localhost:8080`.
    pub base_url: String,
    /// Namespace prefix prepended to every key, e.g. `psa:`.
    pub prefix: String,
    /// Default TTL applied when callers pass `None`.
    pub default_ttl: Duration,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            base_url: "http://localhost:8080".to_string(),
            prefix: "psa:".to_string(),
            default_ttl: Duration::from_secs(3600), // 1 hour
        }
    }
}

// ── client ────────────────────────────────────────────────────────────────────

/// VeriSimDB HTTP cache client.
pub struct Cache {
    /// Shared reqwest client (keep-alive connection pool).
    client: reqwest::Client,
    config: CacheConfig,
}

impl Cache {
    /// Create a new cache client and verify the VeriSimDB instance is reachable.
    pub async fn new() -> Result<Self> {
        let config = CacheConfig::default();
        let client = reqwest::Client::new();

        let health_url = format!("{}/health", config.base_url);
        match client.get(&health_url).send().await {
            Ok(resp) if resp.status().is_success() => {
                tracing::info!("Cache connected to VeriSimDB at {}", config.base_url);
            }
            Ok(resp) => {
                tracing::warn!(
                    "VeriSimDB health check returned {}: cache may be unavailable",
                    resp.status()
                );
            }
            Err(err) => {
                tracing::warn!(
                    "Could not reach VeriSimDB at {} ({}): cache operating in degraded mode",
                    config.base_url,
                    err
                );
            }
        }

        Ok(Self { client, config })
    }

    // ── core operations ───────────────────────────────────────────────────────

    /// Retrieve and deserialise a cached value.
    ///
    /// Returns `Ok(None)` when the key is not present or the value cannot
    /// be deserialised (with a warning log rather than a hard error, so
    /// callers can fall through to a cold-path recompute).
    pub async fn get<T: serde::de::DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let full_key = format!("{}{}", self.config.prefix, key);
        tracing::trace!("Cache GET: {}", full_key);

        let url = format!("{}/api/v1/query", self.config.base_url);
        let resp = self
            .client
            .get(&url)
            .query(&[("q", format!("intentional:{}", full_key).as_str())])
            .send()
            .await
            .with_context(|| format!("Cache GET query for key {}", full_key))?;

        if !resp.status().is_success() {
            tracing::warn!(
                "Cache GET {}: VeriSimDB returned {}",
                full_key,
                resp.status()
            );
            return Ok(None);
        }

        let qr: QueryResponse = resp.json().await.context("decode cache GET response")?;

        // Use the most recently stored hexad for this key.
        let hexad = match qr.results.into_iter().next() {
            Some(h) => h,
            None => return Ok(None),
        };

        match serde_json::from_str::<T>(&hexad.modalities.contextual) {
            Ok(value) => Ok(Some(value)),
            Err(err) => {
                tracing::warn!(
                    "Cache GET {}: could not deserialise value ({}), treating as miss",
                    full_key,
                    err
                );
                Ok(None)
            }
        }
    }

    /// Serialise and store a value under a namespaced cache key.
    ///
    /// `ttl` defaults to `CacheConfig::default_ttl` when `None`.  The TTL
    /// and expiry are recorded in the hexad's temporal/procedural modalities
    /// for observability; hard eviction depends on the VeriSimDB server.
    pub async fn set<T: serde::Serialize>(
        &self,
        key: &str,
        value: &T,
        ttl: Option<Duration>,
    ) -> Result<()> {
        let full_key = format!("{}{}", self.config.prefix, key);
        let ttl = ttl.unwrap_or(self.config.default_ttl);
        tracing::trace!("Cache SET: {} (TTL: {:?})", full_key, ttl);

        let contextual =
            serde_json::to_string(value).context("serialise cached value")?;

        let expiry = chrono::Utc::now() + chrono::Duration::seconds(ttl.as_secs() as i64);

        let body = HexadRequest {
            modalities: CacheHexadModalities {
                perceptual: "psa-cache".to_string(),
                conceptual: full_key.clone(),
                contextual,
                temporal: expiry.to_rfc3339(),
                procedural: ttl.as_secs().to_string(),
                intentional: full_key.clone(),
            },
        };

        let url = format!("{}/api/v1/hexads", self.config.base_url);
        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .with_context(|| format!("Cache SET for key {}", full_key))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::warn!("Cache SET {}: VeriSimDB returned {}: {}", full_key, status, text);
        }

        Ok(())
    }

    /// Delete a cached entry by overwriting it with an immediately-expired
    /// tombstone hexad.
    ///
    /// VeriSimDB does not expose a DELETE endpoint in the base API, so we
    /// record an expired marker that signals a miss on next GET.  The
    /// `contextual` field is set to `"null"` so deserialisation will fail
    /// cleanly and return `None`.
    pub async fn delete(&self, key: &str) -> Result<()> {
        let full_key = format!("{}{}", self.config.prefix, key);
        tracing::trace!("Cache DEL: {}", full_key);

        // Write an expired tombstone so the next GET returns None.
        let body = HexadRequest {
            modalities: CacheHexadModalities {
                perceptual: "psa-cache-tombstone".to_string(),
                conceptual: full_key.clone(),
                contextual: "null".to_string(),
                temporal: chrono::Utc::now().to_rfc3339(), // already expired
                procedural: "0".to_string(),
                intentional: full_key.clone(),
            },
        };

        let url = format!("{}/api/v1/hexads", self.config.base_url);
        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .with_context(|| format!("Cache DEL tombstone for key {}", full_key))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::warn!("Cache DEL {}: VeriSimDB returned {}: {}", full_key, status, text);
        }

        Ok(())
    }

    // ── convenience helpers ───────────────────────────────────────────────────

    /// Cache current system metrics with a short 10-second TTL.
    pub async fn cache_metrics(&self, metrics: &SystemMetrics) -> Result<()> {
        self.set("metrics:current", metrics, Some(Duration::from_secs(10)))
            .await
    }

    /// Retrieve the most recently cached system metrics snapshot.
    pub async fn get_metrics(&self) -> Result<Option<SystemMetrics>> {
        self.get("metrics:current").await
    }

    /// Record a (problem_hash → solution_id) mapping for fast future lookups.
    pub async fn cache_solution_lookup(
        &self,
        problem_hash: &str,
        solution_id: &str,
    ) -> Result<()> {
        self.set(&format!("lookup:{}", problem_hash), &solution_id, None)
            .await
    }

    /// Retrieve a previously cached solution ID for a given problem hash.
    pub async fn get_solution_lookup(&self, problem_hash: &str) -> Result<Option<String>> {
        self.get(&format!("lookup:{}", problem_hash)).await
    }
}

// ── domain types ──────────────────────────────────────────────────────────────

/// Point-in-time system metrics snapshot cached for quick dashboard access.
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
