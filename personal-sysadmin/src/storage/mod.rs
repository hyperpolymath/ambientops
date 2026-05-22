// SPDX-License-Identifier: MPL-2.0
//! VeriSimDB storage layer for knowledge base and solution graph.
//!
//! Replaces the previous ArangoDB stub with real HTTP calls to a local
//! VeriSimDB instance (default: http://localhost:8080).  Solutions are
//! stored as hexads whose modalities carry the structured fields.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

// ── domain types ────────────────────────────────────────────────────────────

/// Solution stored in the knowledge base.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Solution {
    pub id: String,
    pub category: String,
    pub problem: String,
    pub solution: String,
    pub commands: Vec<String>,
    pub tags: Vec<String>,
    pub success_count: u32,
    pub failure_count: u32,
    pub source: SolutionSource,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// Where a solution originated.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SolutionSource {
    Local,          // Learned locally on this machine
    Mesh(String),   // Shared from a mesh peer (peer ID)
    Forum(String),  // Scraped from an online forum (URL)
    Manual,         // Entered manually by the user
}

/// Problem-solution relationship (used by callers building relations).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProblemRelation {
    pub from_problem: String,
    pub to_solution: String,
    pub confidence: f32,
    pub context: Vec<String>,
}

// ── VeriSimDB wire types ─────────────────────────────────────────────────────

/// Request body sent to POST /api/v1/hexads.
///
/// VeriSimDB hexads carry six modalities; we use:
/// - `perceptual`  — category tag
/// - `conceptual`  — problem description
/// - `procedural`  — solution text (serialised commands/tags/source/counts)
/// - `temporal`    — ISO-8601 timestamps
/// - `contextual`  — the full Solution JSON for round-trip fidelity
/// - `intentional` — solution ID
#[derive(Debug, Serialize)]
struct HexadRequest {
    modalities: HexadModalities,
}

/// The six named modality slots VeriSimDB uses for storage and responses.
#[derive(Debug, Serialize, Deserialize)]
struct HexadModalities {
    perceptual: String,
    conceptual: String,
    procedural: String,
    temporal: String,
    contextual: String,
    intentional: String,
}

/// Minimal shape of a VeriSimDB hexad response.
#[derive(Debug, Deserialize)]
struct HexadResponse {
    id: String,
    modalities: HexadModalities,
}

/// Shape of a VCL query response from GET /api/v1/query.
#[derive(Debug, Deserialize)]
struct QueryResponse {
    results: Vec<HexadResponse>,
}

// ── config ────────────────────────────────────────────────────────────────────

/// Configuration for the VeriSimDB HTTP client.
#[derive(Debug, Clone)]
pub struct StorageConfig {
    /// Base URL of the VeriSimDB instance, e.g. `http://localhost:8080`.
    pub base_url: String,
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            base_url: "http://localhost:8080".to_string(),
        }
    }
}

// ── client ────────────────────────────────────────────────────────────────────

/// VeriSimDB HTTP storage client.
pub struct Storage {
    /// Shared reqwest client (keep-alive connection pool).
    client: reqwest::Client,
    config: StorageConfig,
}

impl Storage {
    /// Create a new storage client and verify the VeriSimDB instance is reachable.
    pub async fn new() -> Result<Self> {
        let config = StorageConfig::default();
        let client = reqwest::Client::new();

        // Verify the VeriSimDB instance is up before proceeding.
        let health_url = format!("{}/health", config.base_url);
        match client.get(&health_url).send().await {
            Ok(resp) if resp.status().is_success() => {
                tracing::info!("Storage connected to VeriSimDB at {}", config.base_url);
            }
            Ok(resp) => {
                tracing::warn!(
                    "VeriSimDB health check returned non-success status {}: continuing anyway",
                    resp.status()
                );
            }
            Err(err) => {
                tracing::warn!(
                    "Could not reach VeriSimDB at {} ({}): operating in degraded mode",
                    config.base_url,
                    err
                );
            }
        }

        Ok(Self { client, config })
    }

    // ── write path ────────────────────────────────────────────────────────────

    /// Store a new solution as a VeriSimDB hexad.
    ///
    /// Returns the VeriSimDB-assigned hexad ID (falls back to the solution's
    /// own ID if the server does not return one).
    pub async fn store_solution(&self, solution: &Solution) -> Result<String> {
        tracing::debug!("Storing solution: {}", solution.id);

        // Serialise procedural payload: commands + tags + source + counts.
        let procedural = serde_json::to_string(&serde_json::json!({
            "commands": solution.commands,
            "tags": solution.tags,
            "source": solution.source,
            "success_count": solution.success_count,
            "failure_count": solution.failure_count,
        }))
        .context("serialise procedural modality")?;

        // Store the full solution in `contextual` for lossless round-trips.
        let contextual =
            serde_json::to_string(solution).context("serialise contextual modality")?;

        let body = HexadRequest {
            modalities: HexadModalities {
                perceptual: solution.category.clone(),
                conceptual: solution.problem.clone(),
                procedural,
                temporal: format!(
                    "created={} updated={}",
                    solution.created_at.to_rfc3339(),
                    solution.updated_at.to_rfc3339()
                ),
                contextual,
                intentional: solution.id.clone(),
            },
        };

        let url = format!("{}/api/v1/hexads", self.config.base_url);
        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("POST /api/v1/hexads")?;

        if resp.status().is_success() {
            let hexad: HexadResponse = resp.json().await.context("decode hexad response")?;
            tracing::debug!("Stored solution {} as hexad {}", solution.id, hexad.id);
            Ok(hexad.id)
        } else {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::warn!("store_solution: VeriSimDB returned {}: {}", status, text);
            // Fall back to the solution's own ID so callers are not blocked.
            Ok(solution.id.clone())
        }
    }

    // ── read path ─────────────────────────────────────────────────────────────

    /// Retrieve a single hexad by ID and decode the embedded Solution.
    pub async fn get_solution(&self, hexad_id: &str) -> Result<Option<Solution>> {
        tracing::debug!("Fetching hexad: {}", hexad_id);

        let url = format!("{}/api/v1/hexads/{}", self.config.base_url, hexad_id);
        let resp = self
            .client
            .get(&url)
            .send()
            .await
            .context("GET /api/v1/hexads/{id}")?;

        if resp.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }

        let hexad: HexadResponse = resp.json().await.context("decode hexad response")?;
        let solution: Solution = serde_json::from_str(&hexad.modalities.contextual)
            .context("decode solution from contextual modality")?;
        Ok(Some(solution))
    }

    /// Find solutions whose `perceptual` modality matches the given category.
    ///
    /// Uses the VCL query endpoint with a perceptual-filter expression.
    pub async fn find_by_category(&self, category: &str) -> Result<Vec<Solution>> {
        tracing::debug!("Finding solutions in category: {}", category);
        self.vcl_query(&format!("perceptual:{}", category)).await
    }

    /// Full-text search across the `conceptual` and `procedural` modalities.
    pub async fn search(&self, query: &str) -> Result<Vec<Solution>> {
        tracing::debug!("Searching solutions: {}", query);
        // Search conceptual (problem) and procedural (solution/commands/tags).
        self.vcl_query(&format!("conceptual:{} OR procedural:{}", query, query))
            .await
    }

    /// Find solutions related to a given problem by searching the conceptual
    /// modality.  The `depth` hint is passed as a query parameter for
    /// VeriSimDB implementations that support graph-aware traversal.
    pub async fn find_related(&self, problem: &str, depth: u32) -> Result<Vec<Solution>> {
        tracing::debug!(
            "Finding related solutions for: {} (depth {})",
            problem,
            depth
        );

        let url = format!("{}/api/v1/query", self.config.base_url);
        let resp = self
            .client
            .get(&url)
            .query(&[
                ("q", format!("conceptual:{}", problem).as_str()),
                ("depth", &depth.to_string()),
            ])
            .send()
            .await
            .context("GET /api/v1/query (find_related)")?;

        self.decode_query_response(resp).await
    }

    // ── update path ───────────────────────────────────────────────────────────

    /// Record the outcome of applying a solution so future lookups can be
    /// ranked by confidence.
    ///
    /// Fetches the existing hexad, updates the counts, then re-stores it.
    pub async fn record_outcome(&self, solution_id: &str, success: bool) -> Result<()> {
        tracing::debug!("Recording outcome for {}: {}", solution_id, success);

        // Retrieve the existing solution by searching for its intentional ID.
        let results = self
            .vcl_query(&format!("intentional:{}", solution_id))
            .await?;

        if let Some(mut solution) = results.into_iter().next() {
            if success {
                solution.success_count = solution.success_count.saturating_add(1);
            } else {
                solution.failure_count = solution.failure_count.saturating_add(1);
            }
            solution.updated_at = chrono::Utc::now();
            self.store_solution(&solution).await?;
        } else {
            tracing::warn!(
                "record_outcome: solution {} not found in VeriSimDB — skipping update",
                solution_id
            );
        }

        Ok(())
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /// Issue a VCL query string against GET /api/v1/query and collect results.
    async fn vcl_query(&self, vcl: &str) -> Result<Vec<Solution>> {
        let url = format!("{}/api/v1/query", self.config.base_url);
        let resp = self
            .client
            .get(&url)
            .query(&[("q", vcl)])
            .send()
            .await
            .with_context(|| format!("GET /api/v1/query?q={}", vcl))?;

        self.decode_query_response(resp).await
    }

    /// Decode a VeriSimDB query response into a list of Solutions.
    ///
    /// Returns an empty list (rather than an error) on non-success HTTP
    /// status so callers can continue with degraded data.
    async fn decode_query_response(
        &self,
        resp: reqwest::Response,
    ) -> Result<Vec<Solution>> {
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            tracing::warn!("VeriSimDB query returned {}: {}", status, text);
            return Ok(vec![]);
        }

        let qr: QueryResponse = resp
            .json()
            .await
            .context("decode VeriSimDB query response")?;

        let solutions = qr
            .results
            .into_iter()
            .filter_map(|hexad| {
                match serde_json::from_str::<Solution>(&hexad.modalities.contextual) {
                    Ok(s) => Some(s),
                    Err(err) => {
                        tracing::warn!(
                            "Skipping hexad {}: could not decode solution ({})",
                            hexad.id,
                            err
                        );
                        None
                    }
                }
            })
            .collect();

        Ok(solutions)
    }

    /// Expose configuration for introspection and diagnostics.
    pub fn config(&self) -> &StorageConfig {
        &self.config
    }
}
