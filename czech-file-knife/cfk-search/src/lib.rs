// SPDX-License-Identifier: PMPL-1.0-or-later
//! Full-text search for Czech File Knife
//!
//! This module provides full-text search capabilities.
//! Includes a simple inverted-index implementation using
//! `HashMap<String, Vec<PathBuf>>` for file content search,
//! as well as filename-based search and glob matching.

#![forbid(unsafe_code)]
use async_trait::async_trait;
use cfk_core::{CfkError, CfkResult, Entry, VirtualPath};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;

/// Search index errors
#[derive(Error, Debug)]
pub enum SearchError {
    /// The requested index was not found
    #[error("Index not found: {0}")]
    IndexNotFound(String),

    /// An error occurred during indexing operations
    #[error("Index error: {0}")]
    IndexError(String),

    /// The search query could not be parsed
    #[error("Query parse error: {0}")]
    QueryError(String),

    /// An I/O error occurred
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

/// Search result with relevance score
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// The matching entry
    pub entry: Entry,
    /// Relevance score (0.0 - 1.0)
    pub score: f32,
    /// Matching snippets with highlights
    pub snippets: Vec<String>,
}

/// Search query options
#[derive(Debug, Clone, Default)]
pub struct SearchQuery {
    /// The search query string
    pub query: String,
    /// Limit search to specific backends
    pub backends: Option<Vec<String>>,
    /// Limit search to specific path prefixes
    pub paths: Option<Vec<VirtualPath>>,
    /// Maximum number of results
    pub limit: Option<usize>,
    /// Offset for pagination
    pub offset: Option<usize>,
    /// File type filters (e.g., "pdf", "txt")
    pub file_types: Option<Vec<String>>,
    /// Search in file contents (not just names)
    pub search_contents: bool,
}

/// Search index trait
#[async_trait]
pub trait SearchIndex: Send + Sync {
    /// Index a file or directory entry, optionally with its content bytes.
    async fn index(&self, entry: &Entry, content: Option<&[u8]>) -> CfkResult<()>;

    /// Remove an entry from the index by its path.
    async fn remove(&self, path: &VirtualPath) -> CfkResult<()>;

    /// Search the index and return matching results.
    async fn search(&self, query: &SearchQuery) -> CfkResult<Vec<SearchResult>>;

    /// Clear all entries from the index.
    async fn clear(&self) -> CfkResult<()>;

    /// Get index statistics (document count, size, last update).
    async fn stats(&self) -> CfkResult<IndexStats>;
}

/// Index statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct IndexStats {
    /// Number of indexed documents
    pub document_count: u64,
    /// Index size in bytes (approximate)
    pub size_bytes: u64,
    /// Last update timestamp
    pub last_updated: Option<chrono::DateTime<chrono::Utc>>,
}

/// Internal document record stored in the inverted index
#[derive(Debug, Clone)]
struct IndexedDocument {
    /// The CFK entry for this document
    entry: Entry,
    /// Tokenised words from the filename
    name_tokens: Vec<String>,
    /// Tokenised words from the file content (if indexed)
    content_tokens: Vec<String>,
}

/// Simple inverted-index search engine
///
/// Uses a `HashMap<String, Vec<usize>>` mapping each unique lowercased
/// token to the list of document indices that contain it. Documents
/// are stored in a flat Vec alongside a parallel token map.
///
/// This is suitable for small-to-medium corpora (thousands of files).
/// For larger workloads, enable the `tantivy` feature.
pub struct InvertedIndex {
    /// All indexed documents, keyed by their VirtualPath URI
    documents: Arc<RwLock<Vec<IndexedDocument>>>,
    /// Inverted index: token -> list of document indices
    token_index: Arc<RwLock<HashMap<String, Vec<usize>>>>,
    /// Path to document-index mapping for fast removal
    path_map: Arc<RwLock<HashMap<String, usize>>>,
}

impl InvertedIndex {
    /// Create a new empty inverted index.
    pub fn new() -> Self {
        Self {
            documents: Arc::new(RwLock::new(Vec::new())),
            token_index: Arc::new(RwLock::new(HashMap::new())),
            path_map: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Tokenise a string into lowercase words suitable for indexing.
    ///
    /// Splits on whitespace and non-alphanumeric characters, filters
    /// out very short tokens (< 2 chars), and lowercases everything.
    fn tokenise(text: &str) -> Vec<String> {
        text.split(|c: char| !c.is_alphanumeric() && c != '_' && c != '-')
            .filter(|w| w.len() >= 2)
            .map(|w| w.to_lowercase())
            .collect()
    }

    /// Compute a simple TF-IDF-like score for a document against query tokens.
    fn score_document(doc: &IndexedDocument, query_tokens: &[String], search_contents: bool) -> f32 {
        if query_tokens.is_empty() {
            return 0.0;
        }

        let mut matched = 0u32;
        let mut total_matches = 0u32;

        for qt in query_tokens {
            // Name matches are weighted higher (x3)
            let name_hits = doc.name_tokens.iter().filter(|t| t.contains(qt.as_str())).count() as u32;
            if name_hits > 0 {
                matched += 1;
                total_matches += name_hits * 3;
            }

            if search_contents {
                let content_hits = doc.content_tokens.iter().filter(|t| t.contains(qt.as_str())).count() as u32;
                if content_hits > 0 {
                    matched += 1;
                    total_matches += content_hits;
                }
            }
        }

        if matched == 0 {
            return 0.0;
        }

        // Normalise: fraction of query tokens matched * log(total_matches)
        let coverage = matched as f32 / (query_tokens.len() as f32 * 2.0); // /2 because name+content
        let intensity = (1.0 + total_matches as f32).ln() / 10.0;
        (coverage + intensity).min(1.0)
    }

    /// Extract a snippet around the first occurrence of a query token.
    fn extract_snippet(text: &str, query_token: &str, context_chars: usize) -> Option<String> {
        let lower = text.to_lowercase();
        if let Some(pos) = lower.find(query_token) {
            let start = pos.saturating_sub(context_chars);
            let end = (pos + query_token.len() + context_chars).min(text.len());
            // Find character boundaries
            let start = text[..start].char_indices().last().map(|(i, _)| i).unwrap_or(0);
            let end = text[end..].char_indices().next().map(|(i, _)| end + i).unwrap_or(text.len());
            let mut snippet = String::new();
            if start > 0 {
                snippet.push_str("...");
            }
            snippet.push_str(&text[start..end]);
            if end < text.len() {
                snippet.push_str("...");
            }
            Some(snippet)
        } else {
            None
        }
    }
}

impl Default for InvertedIndex {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SearchIndex for InvertedIndex {
    async fn index(&self, entry: &Entry, content: Option<&[u8]>) -> CfkResult<()> {
        let path_key = entry.path.to_uri();

        // Tokenise the filename
        let name = entry.name().unwrap_or("");
        let name_tokens = Self::tokenise(name);

        // Tokenise the content (if provided and UTF-8)
        let content_tokens = if let Some(bytes) = content {
            if let Ok(text) = std::str::from_utf8(bytes) {
                Self::tokenise(text)
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        let doc = IndexedDocument {
            entry: entry.clone(),
            name_tokens: name_tokens.clone(),
            content_tokens: content_tokens.clone(),
        };

        // Insert into documents list
        let mut docs = self.documents.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let mut path_map = self.path_map.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let mut token_idx = self.token_index.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;

        // If already indexed, remove old entry first
        if let Some(&old_idx) = path_map.get(&path_key) {
            // Remove old token references (expensive but correct)
            let old_doc = &docs[old_idx];
            for token in old_doc.name_tokens.iter().chain(old_doc.content_tokens.iter()) {
                if let Some(indices) = token_idx.get_mut(token) {
                    indices.retain(|&i| i != old_idx);
                }
            }
            docs[old_idx] = doc;
            // Re-index tokens for this slot
            let idx = old_idx;
            for token in name_tokens.iter().chain(content_tokens.iter()) {
                token_idx.entry(token.clone()).or_default().push(idx);
            }
        } else {
            let idx = docs.len();
            docs.push(doc);
            path_map.insert(path_key, idx);

            // Update inverted index
            for token in name_tokens.iter().chain(content_tokens.iter()) {
                token_idx.entry(token.clone()).or_default().push(idx);
            }
        }

        Ok(())
    }

    async fn remove(&self, path: &VirtualPath) -> CfkResult<()> {
        let path_key = path.to_uri();

        let mut path_map = self.path_map.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let docs = self.documents.read().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let mut token_idx = self.token_index.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;

        if let Some(&idx) = path_map.get(&path_key) {
            // Remove token references
            let doc = &docs[idx];
            for token in doc.name_tokens.iter().chain(doc.content_tokens.iter()) {
                if let Some(indices) = token_idx.get_mut(token) {
                    indices.retain(|&i| i != idx);
                }
            }
            path_map.remove(&path_key);
        }

        Ok(())
    }

    async fn search(&self, query: &SearchQuery) -> CfkResult<Vec<SearchResult>> {
        let query_tokens = Self::tokenise(&query.query);
        if query_tokens.is_empty() {
            return Ok(Vec::new());
        }

        let docs = self.documents.read().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let token_idx = self.token_index.read().map_err(|_| CfkError::Other("Lock poisoned".into()))?;

        // Collect candidate document indices from the inverted index
        let mut candidate_set = std::collections::HashSet::new();
        for qt in &query_tokens {
            // Also match partial token prefixes
            for (token, indices) in token_idx.iter() {
                if token.contains(qt.as_str()) {
                    for &idx in indices {
                        candidate_set.insert(idx);
                    }
                }
            }
        }

        // Score and filter candidates
        let mut results: Vec<SearchResult> = candidate_set.into_iter()
            .filter_map(|idx| {
                let doc = docs.get(idx)?;

                // Backend filter
                if let Some(ref backends) = query.backends {
                    if !backends.contains(&doc.entry.path.backend) {
                        return None;
                    }
                }

                // Path prefix filter
                if let Some(ref paths) = query.paths {
                    let doc_path = doc.entry.path.to_path_string();
                    if !paths.iter().any(|p| doc_path.starts_with(&p.to_path_string())) {
                        return None;
                    }
                }

                // File type filter
                if let Some(ref file_types) = query.file_types {
                    if let Some(ext) = doc.entry.path.extension() {
                        if !file_types.iter().any(|ft| ft.eq_ignore_ascii_case(ext)) {
                            return None;
                        }
                    } else {
                        return None;
                    }
                }

                let score = Self::score_document(doc, &query_tokens, query.search_contents);
                if score <= 0.0 {
                    return None;
                }

                // Build snippets
                let mut snippets = Vec::new();
                let name = doc.entry.name().unwrap_or("");
                for qt in &query_tokens {
                    if let Some(s) = Self::extract_snippet(name, qt, 20) {
                        snippets.push(s);
                    }
                }

                Some(SearchResult {
                    entry: doc.entry.clone(),
                    score,
                    snippets,
                })
            })
            .collect();

        // Sort by score descending
        results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));

        // Apply offset and limit
        let offset = query.offset.unwrap_or(0);
        let limit = query.limit.unwrap_or(100);
        let results: Vec<_> = results.into_iter().skip(offset).take(limit).collect();

        Ok(results)
    }

    async fn clear(&self) -> CfkResult<()> {
        let mut docs = self.documents.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let mut token_idx = self.token_index.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let mut path_map = self.path_map.write().map_err(|_| CfkError::Other("Lock poisoned".into()))?;

        docs.clear();
        token_idx.clear();
        path_map.clear();

        Ok(())
    }

    async fn stats(&self) -> CfkResult<IndexStats> {
        let docs = self.documents.read().map_err(|_| CfkError::Other("Lock poisoned".into()))?;
        let token_idx = self.token_index.read().map_err(|_| CfkError::Other("Lock poisoned".into()))?;

        // Approximate size: count of tokens * average key size + posting list sizes
        let token_count: usize = token_idx.values().map(|v| v.len()).sum();
        let key_size: usize = token_idx.keys().map(|k| k.len()).sum();
        let approx_size = (key_size + token_count * 8) as u64;

        Ok(IndexStats {
            document_count: docs.len() as u64,
            size_bytes: approx_size,
            last_updated: Some(chrono::Utc::now()),
        })
    }
}

/// Tantivy-based search index (stub)
/// Enable the `tantivy` feature to use this.
#[cfg(feature = "tantivy")]
pub struct TantivyIndex {
    _path: std::path::PathBuf,
}

#[cfg(feature = "tantivy")]
impl TantivyIndex {
    /// Create a new Tantivy index at the given path
    pub fn new(_path: impl Into<std::path::PathBuf>) -> CfkResult<Self> {
        Err(CfkError::Unsupported(
            "Tantivy search index not yet implemented".into(),
        ))
    }

    /// Open an existing index
    pub fn open(_path: impl Into<std::path::PathBuf>) -> CfkResult<Self> {
        Err(CfkError::Unsupported(
            "Tantivy search index not yet implemented".into(),
        ))
    }
}

#[cfg(feature = "tantivy")]
#[async_trait]
impl SearchIndex for TantivyIndex {
    async fn index(&self, _entry: &Entry, _content: Option<&[u8]>) -> CfkResult<()> {
        Err(CfkError::Unsupported("Tantivy indexing not yet implemented".into()))
    }

    async fn remove(&self, _path: &VirtualPath) -> CfkResult<()> {
        Err(CfkError::Unsupported("Tantivy indexing not yet implemented".into()))
    }

    async fn search(&self, _query: &SearchQuery) -> CfkResult<Vec<SearchResult>> {
        Err(CfkError::Unsupported("Tantivy search not yet implemented".into()))
    }

    async fn clear(&self) -> CfkResult<()> {
        Err(CfkError::Unsupported("Tantivy indexing not yet implemented".into()))
    }

    async fn stats(&self) -> CfkResult<IndexStats> {
        Err(CfkError::Unsupported("Tantivy indexing not yet implemented".into()))
    }
}

/// Simple filename-based search (works without full-text index)
pub async fn search_by_name(
    pattern: &str,
    entries: impl IntoIterator<Item = Entry>,
) -> Vec<Entry> {
    let pattern_lower = pattern.to_lowercase();
    entries
        .into_iter()
        .filter(|e| {
            e.name()
                .map(|n| n.to_lowercase().contains(&pattern_lower))
                .unwrap_or(false)
        })
        .collect()
}

/// Glob-style pattern matching
pub fn matches_glob(pattern: &str, name: &str) -> bool {
    let pattern = pattern.to_lowercase();
    let name = name.to_lowercase();

    if pattern == "*" {
        return true;
    }

    if let Some(suffix) = pattern.strip_prefix("*.") {
        return name.ends_with(&format!(".{}", suffix));
    }

    if let Some(prefix) = pattern.strip_suffix(".*") {
        return name.starts_with(prefix);
    }

    name.contains(&pattern)
}

#[cfg(test)]
mod tests {
    use super::*;
    use cfk_core::{EntryKind, metadata::Metadata};

    #[test]
    fn test_matches_glob() {
        assert!(matches_glob("*", "anything.txt"));
        assert!(matches_glob("*.txt", "file.txt"));
        assert!(matches_glob("*.TXT", "file.txt"));
        assert!(!matches_glob("*.txt", "file.pdf"));
        assert!(matches_glob("file.*", "file.txt"));
        assert!(matches_glob("test", "my_test_file.txt"));
    }

    fn make_entry(backend: &str, path: &str) -> Entry {
        Entry {
            path: VirtualPath::new(backend, path),
            kind: EntryKind::File,
            metadata: Metadata::new(),
        }
    }

    #[tokio::test]
    async fn test_inverted_index_basic() {
        let index = InvertedIndex::new();

        // Index some entries
        let entry1 = make_entry("local", "/docs/readme.txt");
        let entry2 = make_entry("local", "/docs/license.md");
        let entry3 = make_entry("local", "/src/main.rs");

        index.index(&entry1, Some(b"This is the readme file with important documentation")).await.unwrap();
        index.index(&entry2, Some(b"MIT License - free software")).await.unwrap();
        index.index(&entry3, Some(b"fn main() { println!(\"hello\"); }")).await.unwrap();

        // Search by filename
        let query = SearchQuery {
            query: "readme".to_string(),
            search_contents: false,
            ..Default::default()
        };
        let results = index.search(&query).await.unwrap();
        assert!(!results.is_empty());
        assert!(results[0].entry.path.to_uri().contains("readme"));

        // Search by content
        let query = SearchQuery {
            query: "license".to_string(),
            search_contents: true,
            ..Default::default()
        };
        let results = index.search(&query).await.unwrap();
        assert!(!results.is_empty());
    }

    #[tokio::test]
    async fn test_inverted_index_stats() {
        let index = InvertedIndex::new();

        let entry = make_entry("local", "/test.txt");
        index.index(&entry, Some(b"hello world")).await.unwrap();

        let stats = index.stats().await.unwrap();
        assert_eq!(stats.document_count, 1);
        assert!(stats.size_bytes > 0);
    }

    #[tokio::test]
    async fn test_inverted_index_remove() {
        let index = InvertedIndex::new();

        let entry = make_entry("local", "/removeme.txt");
        index.index(&entry, Some(b"temporary content")).await.unwrap();

        let query = SearchQuery {
            query: "removeme".to_string(),
            search_contents: false,
            ..Default::default()
        };
        let results = index.search(&query).await.unwrap();
        assert!(!results.is_empty());

        // Remove and verify
        index.remove(&entry.path).await.unwrap();
        let results = index.search(&query).await.unwrap();
        assert!(results.is_empty());
    }

    #[tokio::test]
    async fn test_inverted_index_clear() {
        let index = InvertedIndex::new();

        let entry1 = make_entry("local", "/a.txt");
        let entry2 = make_entry("local", "/b.txt");
        index.index(&entry1, None).await.unwrap();
        index.index(&entry2, None).await.unwrap();

        let stats = index.stats().await.unwrap();
        assert_eq!(stats.document_count, 2);

        index.clear().await.unwrap();

        let stats = index.stats().await.unwrap();
        assert_eq!(stats.document_count, 0);
    }

    #[tokio::test]
    async fn test_inverted_index_file_type_filter() {
        let index = InvertedIndex::new();

        let txt = make_entry("local", "/notes.txt");
        let pdf = make_entry("local", "/report.pdf");
        index.index(&txt, Some(b"project notes")).await.unwrap();
        index.index(&pdf, Some(b"project report")).await.unwrap();

        let query = SearchQuery {
            query: "project".to_string(),
            search_contents: true,
            file_types: Some(vec!["txt".to_string()]),
            ..Default::default()
        };
        let results = index.search(&query).await.unwrap();
        assert_eq!(results.len(), 1);
        assert!(results[0].entry.path.to_uri().contains("notes.txt"));
    }

    #[tokio::test]
    async fn test_inverted_index_pagination() {
        let index = InvertedIndex::new();

        for i in 0..10 {
            let entry = make_entry("local", &format!("/file_{}.txt", i));
            index.index(&entry, Some(format!("common content {}", i).as_bytes())).await.unwrap();
        }

        let query = SearchQuery {
            query: "file".to_string(),
            search_contents: false,
            limit: Some(3),
            offset: Some(0),
            ..Default::default()
        };
        let results = index.search(&query).await.unwrap();
        assert_eq!(results.len(), 3);

        let query2 = SearchQuery {
            query: "file".to_string(),
            search_contents: false,
            limit: Some(3),
            offset: Some(3),
            ..Default::default()
        };
        let results2 = index.search(&query2).await.unwrap();
        assert_eq!(results2.len(), 3);
    }
}
