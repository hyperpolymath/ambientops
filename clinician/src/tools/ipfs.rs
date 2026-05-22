// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! IPFS Integration — Local IPFS node interaction via the HTTP API.
//!
//! Connects to a local IPFS daemon (default: localhost:5001) and provides:
//! - Node status checking (`id`, `version`, `repo/stat`)
//! - Pin management (pin, unpin, list pinned)
//! - Content operations (add, cat)
//!
//! Uses `reqwest` (already a workspace dependency) to communicate with the
//! IPFS HTTP API. No additional crates required.

use anyhow::{Context, Result};
use reqwest::{multipart, Client};
use serde::{Deserialize, Serialize};

/// Default IPFS API endpoint.
const DEFAULT_API_URL: &str = "http://127.0.0.1:5001/api/v0";

/// IPFS integration configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpfsConfig {
    /// Base URL for the IPFS HTTP API (e.g. "http://127.0.0.1:5001/api/v0").
    pub api_url: String,
    /// Request timeout in seconds.
    pub timeout_secs: u64,
}

impl Default for IpfsConfig {
    fn default() -> Self {
        Self {
            api_url: DEFAULT_API_URL.to_string(),
            timeout_secs: 30,
        }
    }
}

/// Client for interacting with a local IPFS daemon.
pub struct IpfsClient {
    config: IpfsConfig,
    http: Client,
}

impl IpfsClient {
    /// Create a new IPFS client with the given configuration.
    pub fn new(config: IpfsConfig) -> Result<Self> {
        let http = Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout_secs))
            .build()
            .context("Failed to build HTTP client for IPFS")?;
        Ok(Self { config, http })
    }

    /// Create a client with default configuration (localhost:5001).
    pub fn default_local() -> Result<Self> {
        Self::new(IpfsConfig::default())
    }

    /// Build a full URL for an API endpoint.
    fn url(&self, endpoint: &str) -> String {
        format!("{}/{}", self.config.api_url, endpoint)
    }

    // -----------------------------------------------------------------------
    // Node status
    // -----------------------------------------------------------------------

    /// Get the node's identity (peer ID, public key, agent version).
    pub async fn node_id(&self) -> Result<NodeIdResponse> {
        let resp = self
            .http
            .post(&self.url("id"))
            .send()
            .await
            .context("IPFS daemon unreachable — is `ipfs daemon` running?")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS id failed ({}): {}", status, body);
        }

        resp.json::<NodeIdResponse>()
            .await
            .context("Failed to parse IPFS id response")
    }

    /// Get the IPFS daemon version.
    pub async fn version(&self) -> Result<VersionResponse> {
        let resp = self
            .http
            .post(&self.url("version"))
            .send()
            .await
            .context("IPFS daemon unreachable")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS version failed ({}): {}", status, body);
        }

        resp.json::<VersionResponse>()
            .await
            .context("Failed to parse IPFS version response")
    }

    /// Get repository statistics (disk usage, object count, storage limit).
    pub async fn repo_stat(&self) -> Result<RepoStatResponse> {
        let resp = self
            .http
            .post(&self.url("repo/stat"))
            .send()
            .await
            .context("IPFS daemon unreachable")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS repo/stat failed ({}): {}", status, body);
        }

        resp.json::<RepoStatResponse>()
            .await
            .context("Failed to parse IPFS repo/stat response")
    }

    /// Get connected swarm peers.
    pub async fn swarm_peers(&self) -> Result<Vec<String>> {
        #[derive(Deserialize)]
        struct SwarmPeersResponse {
            #[serde(rename = "Peers")]
            peers: Option<Vec<PeerEntry>>,
        }

        #[derive(Deserialize)]
        struct PeerEntry {
            #[serde(rename = "Peer")]
            peer: String,
        }

        let resp = self
            .http
            .post(&self.url("swarm/peers"))
            .send()
            .await
            .context("IPFS daemon unreachable")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS swarm/peers failed ({}): {}", status, body);
        }

        let body: SwarmPeersResponse = resp.json().await?;
        Ok(body
            .peers
            .unwrap_or_default()
            .into_iter()
            .map(|p| p.peer)
            .collect())
    }

    // -----------------------------------------------------------------------
    // Pin management
    // -----------------------------------------------------------------------

    /// Pin a CID so it is not garbage-collected.
    pub async fn pin(&self, cid: &str) -> Result<PinResponse> {
        let resp = self
            .http
            .post(&self.url("pin/add"))
            .query(&[("arg", cid)])
            .send()
            .await
            .context("IPFS pin/add request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS pin/add failed for CID {} ({}): {}", cid, status, body);
        }

        resp.json::<PinResponse>()
            .await
            .context("Failed to parse pin/add response")
    }

    /// Unpin a CID, allowing it to be garbage-collected.
    pub async fn unpin(&self, cid: &str) -> Result<PinResponse> {
        let resp = self
            .http
            .post(&self.url("pin/rm"))
            .query(&[("arg", cid)])
            .send()
            .await
            .context("IPFS pin/rm request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS pin/rm failed for CID {} ({}): {}", cid, status, body);
        }

        resp.json::<PinResponse>()
            .await
            .context("Failed to parse pin/rm response")
    }

    /// List all pinned CIDs, optionally filtered by pin type.
    ///
    /// `pin_type` can be "all", "direct", "recursive", or "indirect".
    pub async fn list_pins(&self, pin_type: &str) -> Result<Vec<PinEntry>> {
        #[derive(Deserialize)]
        struct PinLsResponse {
            #[serde(rename = "Keys")]
            keys: std::collections::HashMap<String, PinTypeEntry>,
        }

        #[derive(Deserialize)]
        struct PinTypeEntry {
            #[serde(rename = "Type")]
            pin_type: String,
        }

        let resp = self
            .http
            .post(&self.url("pin/ls"))
            .query(&[("type", pin_type)])
            .send()
            .await
            .context("IPFS pin/ls request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS pin/ls failed ({}): {}", status, body);
        }

        let body: PinLsResponse = resp.json().await?;
        let mut entries: Vec<PinEntry> = body
            .keys
            .into_iter()
            .map(|(cid, pt)| PinEntry {
                cid,
                pin_type: pt.pin_type,
            })
            .collect();

        entries.sort_by(|a, b| a.cid.cmp(&b.cid));
        Ok(entries)
    }

    // -----------------------------------------------------------------------
    // Content operations
    // -----------------------------------------------------------------------

    /// Add content (bytes) to IPFS, returning the resulting CID.
    pub async fn add(&self, data: &[u8], filename: Option<&str>) -> Result<AddResponse> {
        let part = multipart::Part::bytes(data.to_vec())
            .file_name(filename.unwrap_or("data").to_string());
        let form = multipart::Form::new().part("file", part);

        let resp = self
            .http
            .post(&self.url("add"))
            .multipart(form)
            .send()
            .await
            .context("IPFS add request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS add failed ({}): {}", status, body);
        }

        let text = resp.text().await?;
        // IPFS add returns newline-delimited JSON; take the last line for the
        // top-level object.
        let last_line = text.lines().last().unwrap_or(&text);
        serde_json::from_str(last_line).context("Failed to parse IPFS add response")
    }

    /// Retrieve content by CID.
    pub async fn cat(&self, cid: &str) -> Result<Vec<u8>> {
        let resp = self
            .http
            .post(&self.url("cat"))
            .query(&[("arg", cid)])
            .send()
            .await
            .context("IPFS cat request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS cat failed for CID {} ({}): {}", cid, status, body);
        }

        Ok(resp.bytes().await?.to_vec())
    }

    /// Run garbage collection on the IPFS repository.
    pub async fn repo_gc(&self) -> Result<()> {
        let resp = self
            .http
            .post(&self.url("repo/gc"))
            .send()
            .await
            .context("IPFS repo/gc request failed")?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("IPFS repo/gc failed ({}): {}", status, body);
        }

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/// Response from `ipfs id`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeIdResponse {
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(rename = "PublicKey")]
    pub public_key: String,
    #[serde(rename = "AgentVersion")]
    pub agent_version: String,
    #[serde(rename = "ProtocolVersion")]
    pub protocol_version: String,
    #[serde(rename = "Addresses")]
    pub addresses: Vec<String>,
}

/// Response from `ipfs version`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionResponse {
    #[serde(rename = "Version")]
    pub version: String,
    #[serde(rename = "Commit")]
    pub commit: Option<String>,
    #[serde(rename = "Repo")]
    pub repo: Option<String>,
    #[serde(rename = "System")]
    pub system: Option<String>,
    #[serde(rename = "Golang")]
    pub golang: Option<String>,
}

/// Response from `ipfs repo/stat`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoStatResponse {
    #[serde(rename = "RepoSize")]
    pub repo_size: u64,
    #[serde(rename = "StorageMax")]
    pub storage_max: u64,
    #[serde(rename = "NumObjects")]
    pub num_objects: u64,
    #[serde(rename = "RepoPath")]
    pub repo_path: String,
    #[serde(rename = "Version")]
    pub version: String,
}

/// Response from `ipfs pin/add` or `ipfs pin/rm`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PinResponse {
    #[serde(rename = "Pins")]
    pub pins: Vec<String>,
}

/// A single pinned entry from `ipfs pin/ls`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PinEntry {
    pub cid: String,
    pub pin_type: String,
}

/// Response from `ipfs add`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddResponse {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Hash")]
    pub hash: String,
    #[serde(rename = "Size")]
    pub size: String,
}

// ---------------------------------------------------------------------------
// CLI action types and handler
// ---------------------------------------------------------------------------

/// IPFS action types for CLI dispatch.
#[derive(Debug, Clone)]
pub enum IpfsAction {
    /// Show IPFS node status (id, version, repo stats, peer count).
    Status,
    /// List pinned CIDs with optional type filter.
    ListPins { pin_type: String },
    /// Pin a CID.
    Pin { cid: String },
    /// Unpin a CID.
    Unpin { cid: String },
    /// Add a file to IPFS.
    Add { file_path: String },
    /// Retrieve content by CID and print to stdout.
    Cat { cid: String },
    /// Run garbage collection.
    Gc,
}

/// Handle an IPFS CLI action.
pub async fn handle(action: IpfsAction) -> Result<()> {
    let client = IpfsClient::default_local()?;

    match action {
        IpfsAction::Status => show_status(&client).await?,
        IpfsAction::ListPins { pin_type } => list_pins_cli(&client, &pin_type).await?,
        IpfsAction::Pin { cid } => pin_cli(&client, &cid).await?,
        IpfsAction::Unpin { cid } => unpin_cli(&client, &cid).await?,
        IpfsAction::Add { file_path } => add_file_cli(&client, &file_path).await?,
        IpfsAction::Cat { cid } => cat_cli(&client, &cid).await?,
        IpfsAction::Gc => gc_cli(&client).await?,
    }

    Ok(())
}

/// Print comprehensive IPFS node status.
async fn show_status(client: &IpfsClient) -> Result<()> {
    println!("IPFS Node Status");
    println!("{}", "=".repeat(50));

    match client.node_id().await {
        Ok(id) => {
            println!("  Peer ID:     {}", id.id);
            println!("  Agent:       {}", id.agent_version);
            println!("  Protocol:    {}", id.protocol_version);
            println!("  Addresses:   {}", id.addresses.len());
            for addr in &id.addresses {
                println!("    {}", addr);
            }
        }
        Err(e) => {
            println!("  ERROR: Cannot connect to IPFS daemon: {}", e);
            println!("  Ensure `ipfs daemon` is running on localhost:5001");
            return Ok(());
        }
    }

    if let Ok(ver) = client.version().await {
        println!("\n  IPFS Version: {}", ver.version);
        if let Some(commit) = &ver.commit {
            println!("  Commit:       {}", commit);
        }
    }

    if let Ok(stat) = client.repo_stat().await {
        println!("\n  Repository:");
        println!(
            "    Size:    {:.2} MB / {:.2} MB",
            stat.repo_size as f64 / 1_048_576.0,
            stat.storage_max as f64 / 1_048_576.0
        );
        println!("    Objects: {}", stat.num_objects);
        println!("    Path:    {}", stat.repo_path);
    }

    if let Ok(peers) = client.swarm_peers().await {
        println!("\n  Connected Peers: {}", peers.len());
        for peer in peers.iter().take(10) {
            println!("    {}", peer);
        }
        if peers.len() > 10 {
            println!("    ... and {} more", peers.len() - 10);
        }
    }

    Ok(())
}

/// List pinned CIDs.
async fn list_pins_cli(client: &IpfsClient, pin_type: &str) -> Result<()> {
    println!("IPFS Pinned Content (type: {})", pin_type);
    println!("{}", "=".repeat(60));

    let pins = client.list_pins(pin_type).await?;

    if pins.is_empty() {
        println!("  No pinned content.");
        return Ok(());
    }

    println!("{:<52} {:<12}", "CID", "TYPE");
    println!("{}", "-".repeat(64));

    for entry in &pins {
        println!("{:<52} {:<12}", entry.cid, entry.pin_type);
    }

    println!("\n{} pinned objects", pins.len());
    Ok(())
}

/// Pin a CID.
async fn pin_cli(client: &IpfsClient, cid: &str) -> Result<()> {
    println!("Pinning {}...", cid);
    let resp = client.pin(cid).await?;
    println!("Pinned: {:?}", resp.pins);
    Ok(())
}

/// Unpin a CID.
async fn unpin_cli(client: &IpfsClient, cid: &str) -> Result<()> {
    println!("Unpinning {}...", cid);
    let resp = client.unpin(cid).await?;
    println!("Unpinned: {:?}", resp.pins);
    Ok(())
}

/// Add a file to IPFS.
async fn add_file_cli(client: &IpfsClient, file_path: &str) -> Result<()> {
    let path = std::path::Path::new(file_path);
    if !path.exists() {
        anyhow::bail!("File does not exist: {}", file_path);
    }

    let data = std::fs::read(path).context("Failed to read file")?;
    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");

    println!("Adding {} ({} bytes)...", file_path, data.len());
    let resp = client.add(&data, Some(filename)).await?;

    println!("Added successfully:");
    println!("  CID:  {}", resp.hash);
    println!("  Name: {}", resp.name);
    println!("  Size: {} bytes", resp.size);
    Ok(())
}

/// Retrieve and display content by CID.
async fn cat_cli(client: &IpfsClient, cid: &str) -> Result<()> {
    let data = client.cat(cid).await?;

    // Try to print as UTF-8; fall back to hex dump for binary.
    match std::str::from_utf8(&data) {
        Ok(text) => print!("{}", text),
        Err(_) => {
            println!("[Binary content, {} bytes]", data.len());
            // Print first 256 bytes as hex.
            for (i, byte) in data.iter().take(256).enumerate() {
                if i % 16 == 0 && i > 0 {
                    println!();
                }
                print!("{:02x} ", byte);
            }
            if data.len() > 256 {
                println!("\n... ({} more bytes)", data.len() - 256);
            }
            println!();
        }
    }

    Ok(())
}

/// Run IPFS garbage collection.
async fn gc_cli(client: &IpfsClient) -> Result<()> {
    println!("Running IPFS garbage collection...");

    let stat_before = client.repo_stat().await.ok();
    client.repo_gc().await?;
    let stat_after = client.repo_stat().await.ok();

    println!("Garbage collection complete.");

    if let (Some(before), Some(after)) = (stat_before, stat_after) {
        let freed = before.repo_size.saturating_sub(after.repo_size);
        println!(
            "  Freed: {:.2} MB",
            freed as f64 / 1_048_576.0
        );
        println!(
            "  Repo size: {:.2} MB -> {:.2} MB",
            before.repo_size as f64 / 1_048_576.0,
            after.repo_size as f64 / 1_048_576.0
        );
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ipfs_config_default() {
        let config = IpfsConfig::default();
        assert_eq!(config.api_url, "http://127.0.0.1:5001/api/v0");
        assert_eq!(config.timeout_secs, 30);
    }

    #[test]
    fn test_client_url_construction() {
        let client = IpfsClient::default_local().unwrap();
        assert_eq!(client.url("id"), "http://127.0.0.1:5001/api/v0/id");
        assert_eq!(client.url("pin/ls"), "http://127.0.0.1:5001/api/v0/pin/ls");
    }

    #[test]
    fn test_pin_entry_deserialization() {
        let entry = PinEntry {
            cid: "QmTest123".to_string(),
            pin_type: "recursive".to_string(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        let parsed: PinEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.cid, "QmTest123");
        assert_eq!(parsed.pin_type, "recursive");
    }

    #[test]
    fn test_add_response_deserialization() {
        let json = r#"{"Name":"hello.txt","Hash":"QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN","Size":"12"}"#;
        let resp: AddResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.name, "hello.txt");
        assert_eq!(
            resp.hash,
            "QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN"
        );
        assert_eq!(resp.size, "12");
    }

    #[test]
    fn test_node_id_response_deserialization() {
        let json = r#"{
            "ID": "12D3KooWTest",
            "PublicKey": "CAESIG==",
            "AgentVersion": "kubo/0.23.0",
            "ProtocolVersion": "ipfs/0.1.0",
            "Addresses": ["/ip4/127.0.0.1/tcp/4001"]
        }"#;
        let resp: NodeIdResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.id, "12D3KooWTest");
        assert_eq!(resp.agent_version, "kubo/0.23.0");
        assert_eq!(resp.addresses.len(), 1);
    }
}
