// SPDX-License-Identifier: PMPL-1.0-or-later
//! ArangoDB storage layer for knowledge base and solution graph
//!
//! When `storage` feature is enabled, connects to ArangoDB for persistent
//! storage with graph traversal capabilities.
//! Falls back to local no-op mode when ArangoDB is unavailable or feature disabled.

#![allow(dead_code)]
#![allow(unused_variables)]

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// ArangoDB collection for solutions
const SOLUTIONS_COLLECTION: &str = "solutions";

/// ArangoDB edge collection for problem-solution relationships
const RELATIONS_COLLECTION: &str = "problem_relations";

/// ArangoDB named graph for traversal
const KNOWLEDGE_GRAPH: &str = "knowledge";

// ── AQL Query Constants ────────────────────────────────────────────────

/// Find solutions by category, ordered by success rate
pub const AQL_FIND_BY_CATEGORY: &str =
    "FOR s IN solutions FILTER s.category == @cat SORT s.success_count DESC RETURN s";

/// Search solutions by text in problem/solution fields (case-insensitive)
pub const AQL_SEARCH: &str =
    "FOR s IN solutions FILTER CONTAINS(LOWER(s.problem), LOWER(@q)) OR CONTAINS(LOWER(s.solution), LOWER(@q)) SORT s.success_count DESC LIMIT 50 RETURN s";

/// Find starting nodes for graph traversal (solutions matching problem text)
pub const AQL_FIND_STARTS: &str =
    "FOR s IN solutions FILTER CONTAINS(LOWER(s.problem), LOWER(@q)) LIMIT 5 RETURN s._id";

/// Graph traversal from a starting solution node
pub const AQL_TRAVERSE: &str =
    "FOR v IN 1..@depth OUTBOUND @start GRAPH 'knowledge' RETURN DISTINCT v";

// ── Data Types ─────────────────────────────────────────────────────────

/// Solution stored in the knowledge base
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SolutionSource {
    Local,
    Mesh(String),
    Forum(String),
    Manual,
}

/// Problem-solution relationship for graph queries
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProblemRelation {
    pub from_problem: String,
    pub to_solution: String,
    pub confidence: f32,
    pub context: Vec<String>,
}

// ── Storage Client ─────────────────────────────────────────────────────

/// ArangoDB storage client (or local fallback)
pub struct Storage {
    config: StorageConfig,
    connected: bool,
    #[cfg(feature = "storage")]
    db: Option<arangors::Database<arangors::client::reqwest::ReqwestClient>>,
}

#[derive(Debug, Clone)]
pub struct StorageConfig {
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: String,
    pub password: String,
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            host: "localhost".to_string(),
            port: 8529,
            database: "psa".to_string(),
            username: "root".to_string(),
            password: String::new(),
        }
    }
}

impl Storage {
    /// Create new storage connection.
    /// With `storage` feature: attempts ArangoDB, falls back to local.
    /// Without: always local mode.
    pub async fn new() -> Result<Self> {
        let config = StorageConfig::default();

        #[cfg(feature = "storage")]
        {
            let url = format!("http://{}:{}", config.host, config.port);
            match arangors::Connection::establish_basic_auth(&url, &config.username, &config.password).await {
                Ok(conn) => {
                    match conn.db(&config.database).await {
                        Ok(db) => {
                            tracing::info!("Storage: ArangoDB connected at {}:{}", config.host, config.port);
                            return Ok(Self { config, connected: true, db: Some(db) });
                        }
                        Err(e) => {
                            tracing::warn!("Storage: ArangoDB db '{}' error: {}, local fallback", config.database, e);
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!("Storage: ArangoDB unavailable: {}, local fallback", e);
                }
            }

            return Ok(Self { config, connected: false, db: None });
        }

        #[cfg(not(feature = "storage"))]
        {
            tracing::info!("Storage initialized (local mode)");
            Ok(Self { config, connected: false })
        }
    }

    /// Store a new solution
    pub async fn store_solution(&self, solution: &Solution) -> Result<String> {
        tracing::debug!("Storing solution: {}", solution.id);

        #[cfg(feature = "storage")]
        if let Some(ref db) = self.db {
            let doc = serde_json::to_value(solution)?;
            let aql = arangors::AqlQuery::builder()
                .query("INSERT @doc INTO solutions OPTIONS { overwriteMode: 'replace' } RETURN NEW._key")
                .bind_var("doc", doc)
                .build();
            let _result: Vec<serde_json::Value> = db.aql_query(aql).await
                .map_err(|e| anyhow::anyhow!("ArangoDB store error: {}", e))?;
            return Ok(solution.id.clone());
        }

        Ok(solution.id.clone())
    }

    /// Find solutions by category
    pub async fn find_by_category(&self, category: &str) -> Result<Vec<Solution>> {
        tracing::debug!("Finding solutions in category: {}", category);

        #[cfg(feature = "storage")]
        if let Some(ref db) = self.db {
            let aql = arangors::AqlQuery::builder()
                .query(AQL_FIND_BY_CATEGORY)
                .bind_var("cat", serde_json::Value::String(category.to_string()))
                .build();
            let results: Vec<Solution> = db.aql_query(aql).await
                .map_err(|e| anyhow::anyhow!("ArangoDB query error: {}", e))?;
            return Ok(results);
        }

        Ok(vec![])
    }

    /// Search solutions by text
    pub async fn search(&self, query: &str) -> Result<Vec<Solution>> {
        tracing::debug!("Searching solutions: {}", query);

        #[cfg(feature = "storage")]
        if let Some(ref db) = self.db {
            let aql = arangors::AqlQuery::builder()
                .query(AQL_SEARCH)
                .bind_var("q", serde_json::Value::String(query.to_string()))
                .build();
            let results: Vec<Solution> = db.aql_query(aql).await
                .map_err(|e| anyhow::anyhow!("ArangoDB search error: {}", e))?;
            return Ok(results);
        }

        Ok(vec![])
    }

    /// Get related solutions via graph traversal
    ///
    /// Two-step process:
    /// 1. Find solutions matching the problem text
    /// 2. Traverse the knowledge graph from those nodes up to `depth` edges
    pub async fn find_related(&self, problem: &str, depth: u32) -> Result<Vec<Solution>> {
        tracing::debug!("Finding related solutions for: {} (depth {})", problem, depth);

        #[cfg(feature = "storage")]
        if let Some(ref db) = self.db {
            // Step 1: find starting nodes
            let find_aql = arangors::AqlQuery::builder()
                .query(AQL_FIND_STARTS)
                .bind_var("q", serde_json::Value::String(problem.to_string()))
                .build();
            let start_ids: Vec<String> = db.aql_query(find_aql).await
                .unwrap_or_default();

            if start_ids.is_empty() {
                return Ok(vec![]);
            }

            // Step 2: graph traversal from each starting node
            let mut all_related = Vec::new();
            for start_id in &start_ids {
                let traverse_aql = arangors::AqlQuery::builder()
                    .query(AQL_TRAVERSE)
                    .bind_var("start", serde_json::Value::String(start_id.clone()))
                    .bind_var("depth", serde_json::Value::Number(serde_json::Number::from(depth)))
                    .build();
                let related: Vec<Solution> = db.aql_query(traverse_aql).await
                    .unwrap_or_default();
                all_related.extend(related);
            }

            // Deduplicate by solution ID
            all_related.sort_by(|a, b| a.id.cmp(&b.id));
            all_related.dedup_by(|a, b| a.id == b.id);
            return Ok(all_related);
        }

        Ok(vec![])
    }

    /// Record solution success/failure for learning
    pub async fn record_outcome(&self, solution_id: &str, success: bool) -> Result<()> {
        tracing::debug!("Recording outcome for {}: {}", solution_id, success);

        #[cfg(feature = "storage")]
        if let Some(ref db) = self.db {
            let field = if success { "success_count" } else { "failure_count" };
            let query = format!(
                "FOR s IN solutions FILTER s.id == @id UPDATE s WITH {{ {f}: s.{f} + 1, updated_at: DATE_ISO8601(DATE_NOW()) }} IN solutions",
                f = field
            );
            let aql = arangors::AqlQuery::builder()
                .query(&query)
                .bind_var("id", serde_json::Value::String(solution_id.to_string()))
                .build();
            let _: Vec<serde_json::Value> = db.aql_query(aql).await
                .map_err(|e| anyhow::anyhow!("ArangoDB update error: {}", e))?;
        }

        Ok(())
    }

    /// Get storage config
    pub fn config(&self) -> &StorageConfig {
        &self.config
    }

    /// Check if connected to ArangoDB
    pub fn is_connected(&self) -> bool {
        self.connected
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_storage_local_fallback() {
        let storage = Storage::new().await.unwrap();
        assert!(!storage.is_connected());
        let results = storage.find_by_category("test").await.unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_store_and_search_local() {
        let storage = Storage::new().await.unwrap();
        let result = storage.search("test query").await.unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn test_solution_serialization() {
        let solution = Solution {
            id: "sol-001".to_string(),
            category: "network".to_string(),
            problem: "DNS fails".to_string(),
            solution: "Restart resolved".to_string(),
            commands: vec!["systemctl restart systemd-resolved".to_string()],
            tags: vec!["dns".to_string()],
            success_count: 5,
            failure_count: 1,
            source: SolutionSource::Local,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        let json = serde_json::to_string(&solution).unwrap();
        let decoded: Solution = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, "sol-001");
        assert_eq!(decoded.category, "network");
        assert_eq!(decoded.success_count, 5);
    }

    #[test]
    fn test_problem_relation_serialization() {
        let relation = ProblemRelation {
            from_problem: "solutions/p1".to_string(),
            to_solution: "solutions/s1".to_string(),
            confidence: 0.85,
            context: vec!["network".to_string(), "timeout".to_string()],
        };

        let json = serde_json::to_string(&relation).unwrap();
        let decoded: ProblemRelation = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.confidence, 0.85);
        assert_eq!(decoded.context.len(), 2);
    }

    #[test]
    fn test_solution_source_variants() {
        let local = SolutionSource::Local;
        let mesh = SolutionSource::Mesh("peer-123".to_string());
        let forum = SolutionSource::Forum("askubuntu.com".to_string());
        let manual = SolutionSource::Manual;

        // All variants serialize to JSON
        for source in [&local, &mesh, &forum, &manual] {
            let json = serde_json::to_string(source).unwrap();
            assert!(!json.is_empty());
        }

        // Roundtrip Mesh variant
        let json = serde_json::to_string(&mesh).unwrap();
        let decoded: SolutionSource = serde_json::from_str(&json).unwrap();
        match decoded {
            SolutionSource::Mesh(peer) => assert_eq!(peer, "peer-123"),
            _ => panic!("Wrong variant"),
        }
    }

    #[test]
    fn test_storage_config_defaults() {
        let config = StorageConfig::default();
        assert_eq!(config.host, "localhost");
        assert_eq!(config.port, 8529);
        assert_eq!(config.database, "psa");
        assert_eq!(config.username, "root");
        assert!(config.password.is_empty());
    }

    #[test]
    fn test_aql_query_content() {
        // Verify AQL constants contain expected clauses
        assert!(AQL_FIND_BY_CATEGORY.contains("FILTER s.category == @cat"));
        assert!(AQL_FIND_BY_CATEGORY.contains("SORT s.success_count DESC"));

        assert!(AQL_SEARCH.contains("CONTAINS(LOWER(s.problem)"));
        assert!(AQL_SEARCH.contains("LIMIT 50"));

        assert!(AQL_FIND_STARTS.contains("LIMIT 5"));
        assert!(AQL_FIND_STARTS.contains("RETURN s._id"));

        assert!(AQL_TRAVERSE.contains("OUTBOUND"));
        assert!(AQL_TRAVERSE.contains("GRAPH 'knowledge'"));
        assert!(AQL_TRAVERSE.contains("RETURN DISTINCT"));
    }

    #[test]
    fn test_collection_constants() {
        assert_eq!(SOLUTIONS_COLLECTION, "solutions");
        assert_eq!(RELATIONS_COLLECTION, "problem_relations");
        assert_eq!(KNOWLEDGE_GRAPH, "knowledge");
    }
}
