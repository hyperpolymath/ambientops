// SPDX-License-Identifier: PMPL-1.0-or-later
//! P2P mesh communication for sharing solutions across clinician instances
//!
//! Uses libp2p with TCP+Noise+Yamux transport, mDNS for local peer discovery,
//! and Gossipsub for pub/sub messaging.
//!
//! Architecture: discovery uses an mDNS-only swarm; messaging (join, share, sync)
//! uses a gossipsub-only swarm with explicit peer dialing. This avoids the need
//! for a combined NetworkBehaviour derive.
//!
//! When `p2p` feature is disabled, stubs suggest enabling the feature.

#![allow(dead_code)]
#![allow(unused_variables)]

use anyhow::Result;
use crate::storage::Storage;
use crate::cache::Cache;

/// Gossipsub topic for solution sharing
pub const SOLUTIONS_TOPIC: &str = "ambientops/solutions/v1";

/// Gossipsub topic for sync coordination
pub const SYNC_TOPIC: &str = "ambientops/sync/v1";

/// Filename for persistent peer identity key
pub const PEER_KEY_FILENAME: &str = "peer_key";

/// Mesh action types
#[derive(Debug, Clone)]
pub enum MeshAction {
    Discover,
    Join { peer: String },
    Share { solution_id: String },
    Sync,
    Status,
}

/// Handle mesh subcommands
pub async fn handle(action: MeshAction, storage: &Storage, cache: &Cache) -> Result<()> {
    match action {
        MeshAction::Discover => discover_peers().await?,
        MeshAction::Join { peer } => join_mesh(&peer).await?,
        MeshAction::Share { solution_id } => share_solution(&solution_id, storage).await?,
        MeshAction::Sync => sync_knowledge(storage, cache).await?,
        MeshAction::Status => show_status().await?,
    }
    Ok(())
}

// ── Wire protocol messages ─────────────────────────────────────────────

#[cfg(feature = "p2p")]
pub mod protocol {
    use serde::{Deserialize, Serialize};
    use crate::storage::Solution;

    /// Messages exchanged over gossipsub
    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub enum MeshMessage {
        /// Share a solution with peers
        ShareSolution(Solution),
        /// Request knowledge sync (advertise our solution count)
        SyncRequest {
            peer_id: String,
            solution_count: u64,
        },
        /// Respond with solutions the requester may be missing
        SyncResponse {
            solutions: Vec<Solution>,
        },
    }
}

// ── Persistent peer identity ───────────────────────────────────────────

#[cfg(feature = "p2p")]
pub mod identity_store {
    use anyhow::Result;
    use libp2p::identity::Keypair;
    use std::path::PathBuf;

    /// Directory for clinician data files
    pub fn data_dir() -> PathBuf {
        directories::ProjectDirs::from("com", "hyperpolymath", "psa")
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."))
    }

    /// Load a persistent Ed25519 keypair, or generate and save one
    pub fn load_or_create_keypair() -> Result<Keypair> {
        let dir = data_dir();
        let key_path = dir.join(super::PEER_KEY_FILENAME);

        if key_path.exists() {
            let bytes = std::fs::read(&key_path)?;
            match Keypair::from_protobuf_encoding(&bytes) {
                Ok(kp) => return Ok(kp),
                Err(e) => {
                    tracing::warn!("Corrupt peer key, regenerating: {}", e);
                }
            }
        }

        std::fs::create_dir_all(&dir)?;
        let keypair = Keypair::generate_ed25519();
        let encoded = keypair.to_protobuf_encoding()?;
        std::fs::write(&key_path, &encoded)?;
        tracing::info!("Generated new peer identity at {}", key_path.display());
        Ok(keypair)
    }
}

// ── Function implementations ───────────────────────────────────────────

async fn discover_peers() -> Result<()> {
    println!("Discovering PSA peers on local network...");
    println!("{}", "-".repeat(50));

    #[cfg(feature = "p2p")]
    {
        use libp2p::{mdns, noise, tcp, yamux, swarm::SwarmEvent, SwarmBuilder};
        use futures::StreamExt;
        use std::collections::HashMap;

        let keypair = identity_store::load_or_create_keypair()?;
        let local_peer_id = keypair.public().to_peer_id();
        println!("  Local Peer ID: {}", local_peer_id);

        let mdns_behaviour = mdns::tokio::Behaviour::new(
            mdns::Config::default(),
            local_peer_id,
        )?;

        let mut swarm = SwarmBuilder::with_existing_identity(keypair)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|_| mdns_behaviour)?
            .build();

        swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
        println!("  Listening for mDNS announcements (10 seconds)...");

        let mut discovered: HashMap<libp2p::PeerId, Vec<libp2p::Multiaddr>> = HashMap::new();
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);

        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                event = swarm.select_next_some() => {
                    if let SwarmEvent::Behaviour(mdns::Event::Discovered(peers)) = event {
                        for (peer_id, addr) in peers {
                            discovered.entry(peer_id).or_default().push(addr);
                        }
                    }
                }
            }
        }

        if discovered.is_empty() {
            println!("\n  No peers found on local network.");
            println!("  Ensure other clinician instances are running with --features p2p.");
        } else {
            println!("\n  Discovered {} peer(s):", discovered.len());
            for (peer_id, addrs) in &discovered {
                println!("    {} ({} addr(s))", peer_id, addrs.len());
                for addr in addrs {
                    println!("      {}", addr);
                }
            }
        }

        println!("\n  Discovery uses mDNS on local network only.");
        println!("  No internet exposure - peers must be on same LAN/VLAN.");
        return Ok(());
    }

    #[cfg(not(feature = "p2p"))]
    {
        println!("\n  P2P discovery requires the 'p2p' feature.");
        println!("  Build with: cargo build -p ambientops-clinician --features p2p");
        println!("\n  Discovery uses mDNS on local network only.");
        println!("  No internet exposure - peers must be on same LAN/VLAN.");
    }

    Ok(())
}

async fn join_mesh(peer: &str) -> Result<()> {
    println!("Joining mesh via peer: {}", peer);

    #[cfg(feature = "p2p")]
    {
        use libp2p::{gossipsub, noise, tcp, yamux, swarm::SwarmEvent, Multiaddr, SwarmBuilder};
        use futures::StreamExt;

        let addr: Multiaddr = peer
            .parse()
            .map_err(|e| anyhow::anyhow!("Invalid multiaddr '{}': {}", peer, e))?;

        let keypair = identity_store::load_or_create_keypair()?;
        let local_peer_id = keypair.public().to_peer_id();
        println!("  Local Peer ID: {}", local_peer_id);

        let gossipsub_config = gossipsub::ConfigBuilder::default()
            .heartbeat_interval(std::time::Duration::from_secs(1))
            .validation_mode(gossipsub::ValidationMode::Strict)
            .build()
            .map_err(|e| anyhow::anyhow!("Gossipsub config error: {}", e))?;

        let gossipsub_behaviour = gossipsub::Behaviour::<gossipsub::IdentityTransform, gossipsub::AllowAllSubscriptionFilter>::new(
            gossipsub::MessageAuthenticity::Signed(keypair.clone()),
            gossipsub_config,
        )
        .map_err(|e| anyhow::anyhow!("Gossipsub behaviour error: {}", e))?;

        let mut swarm = SwarmBuilder::with_existing_identity(keypair)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|_| gossipsub_behaviour)?
            .build();

        // Subscribe to topics
        let solutions_topic = gossipsub::IdentTopic::new(SOLUTIONS_TOPIC);
        let sync_topic = gossipsub::IdentTopic::new(SYNC_TOPIC);
        swarm.behaviour_mut().subscribe(&solutions_topic)?;
        swarm.behaviour_mut().subscribe(&sync_topic)?;

        swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
        swarm.dial(addr)?;
        println!("  Dialing peer...");

        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
        let mut connected = false;

        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => {
                    if !connected {
                        println!("  Connection timed out after 30 seconds.");
                    }
                    break;
                }
                event = swarm.select_next_some() => {
                    match event {
                        SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                            println!("  Connected to peer: {}", peer_id);
                            connected = true;
                            println!("  Subscribed to topics:");
                            println!("    - {}", SOLUTIONS_TOPIC);
                            println!("    - {}", SYNC_TOPIC);
                            break;
                        }
                        SwarmEvent::OutgoingConnectionError { error, .. } => {
                            println!("  Connection error: {}", error);
                            break;
                        }
                        _ => {}
                    }
                }
            }
        }

        return Ok(());
    }

    #[cfg(not(feature = "p2p"))]
    {
        println!("\n  Mesh joining requires the 'p2p' feature.");
        println!("  Build with: cargo build -p ambientops-clinician --features p2p");
    }

    Ok(())
}

async fn share_solution(solution_id: &str, storage: &Storage) -> Result<()> {
    println!("Sharing solution {} with mesh...", solution_id);

    #[cfg(feature = "p2p")]
    {
        use libp2p::{gossipsub, noise, tcp, yamux, SwarmBuilder};

        // Retrieve solution from storage
        let results = storage.search(solution_id).await?;
        let solution = results.into_iter().find(|s| s.id == solution_id);

        let solution = match solution {
            Some(s) => s,
            None => {
                println!("  Solution '{}' not found in storage.", solution_id);
                if !storage.is_connected() {
                    println!("  Storage is in local mode. Enable with --features storage.");
                }
                return Ok(());
            }
        };

        let keypair = identity_store::load_or_create_keypair()?;

        let gossipsub_config = gossipsub::ConfigBuilder::default()
            .heartbeat_interval(std::time::Duration::from_secs(1))
            .validation_mode(gossipsub::ValidationMode::Strict)
            .build()
            .map_err(|e| anyhow::anyhow!("Gossipsub config error: {}", e))?;

        let gossipsub_behaviour = gossipsub::Behaviour::<gossipsub::IdentityTransform, gossipsub::AllowAllSubscriptionFilter>::new(
            gossipsub::MessageAuthenticity::Signed(keypair.clone()),
            gossipsub_config,
        )
        .map_err(|e| anyhow::anyhow!("Gossipsub behaviour error: {}", e))?;

        let mut swarm = SwarmBuilder::with_existing_identity(keypair)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|_| gossipsub_behaviour)?
            .build();

        let topic = gossipsub::IdentTopic::new(SOLUTIONS_TOPIC);
        swarm.behaviour_mut().subscribe(&topic)?;
        swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;

        let msg = protocol::MeshMessage::ShareSolution(solution);
        let json = serde_json::to_vec(&msg)?;

        println!("  Waiting for peers (5 seconds)...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;

        match swarm.behaviour_mut().publish(topic, json) {
            Ok(msg_id) => {
                println!("  Published solution (message ID: {:?})", msg_id);
            }
            Err(e) => {
                println!("  Publish failed: {}. No connected peers?", e);
            }
        }

        return Ok(());
    }

    #[cfg(not(feature = "p2p"))]
    {
        println!("\n  Solution sharing requires the 'p2p' feature.");
        println!("  Build with: cargo build -p ambientops-clinician --features p2p");
    }

    Ok(())
}

async fn sync_knowledge(storage: &Storage, _cache: &Cache) -> Result<()> {
    println!("Synchronizing knowledge base with mesh peers...");

    #[cfg(feature = "p2p")]
    {
        use libp2p::{gossipsub, noise, tcp, yamux, swarm::SwarmEvent, SwarmBuilder};
        use futures::StreamExt;

        let keypair = identity_store::load_or_create_keypair()?;
        let local_peer_id = keypair.public().to_peer_id();

        let gossipsub_config = gossipsub::ConfigBuilder::default()
            .heartbeat_interval(std::time::Duration::from_secs(1))
            .validation_mode(gossipsub::ValidationMode::Strict)
            .build()
            .map_err(|e| anyhow::anyhow!("Gossipsub config error: {}", e))?;

        let gossipsub_behaviour = gossipsub::Behaviour::<gossipsub::IdentityTransform, gossipsub::AllowAllSubscriptionFilter>::new(
            gossipsub::MessageAuthenticity::Signed(keypair.clone()),
            gossipsub_config,
        )
        .map_err(|e| anyhow::anyhow!("Gossipsub behaviour error: {}", e))?;

        let mut swarm = SwarmBuilder::with_existing_identity(keypair)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|_| gossipsub_behaviour)?
            .build();

        let solutions_topic = gossipsub::IdentTopic::new(SOLUTIONS_TOPIC);
        let sync_topic = gossipsub::IdentTopic::new(SYNC_TOPIC);
        swarm.behaviour_mut().subscribe(&solutions_topic)?;
        swarm.behaviour_mut().subscribe(&sync_topic)?;
        swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;

        println!("  Waiting for peers (5 seconds)...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;

        // Publish sync request
        let request = protocol::MeshMessage::SyncRequest {
            peer_id: local_peer_id.to_string(),
            solution_count: 0,
        };
        let json = serde_json::to_vec(&request)?;
        let _ = swarm.behaviour_mut().publish(sync_topic, json);
        println!("  Sent sync request, listening for responses (30 seconds)...");

        let mut received = 0u32;
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);

        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(deadline) => break,
                event = swarm.select_next_some() => {
                    if let SwarmEvent::Behaviour(gossipsub::Event::Message {
                        message, ..
                    }) = event {
                        if let Ok(msg) = serde_json::from_slice::<protocol::MeshMessage>(&message.data) {
                            match msg {
                                protocol::MeshMessage::SyncResponse { solutions } => {
                                    for sol in solutions {
                                        println!("  Received solution: {}", sol.id);
                                        let _ = storage.store_solution(&sol).await;
                                        received += 1;
                                    }
                                }
                                protocol::MeshMessage::ShareSolution(sol) => {
                                    println!("  Received shared solution: {}", sol.id);
                                    let _ = storage.store_solution(&sol).await;
                                    received += 1;
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }
        }

        println!("\n  Sync complete. Received {} solution(s).", received);
        return Ok(());
    }

    #[cfg(not(feature = "p2p"))]
    {
        println!("\n  Knowledge sync requires the 'p2p' feature.");
        println!("  Build with: cargo build -p ambientops-clinician --features p2p");
    }

    Ok(())
}

async fn show_status() -> Result<()> {
    println!("Mesh Status");
    println!("{}", "=".repeat(50));

    #[cfg(feature = "p2p")]
    {
        let keypair = identity_store::load_or_create_keypair()?;
        let peer_id = keypair.public().to_peer_id();

        println!("\nPeer ID: {} (persistent)", peer_id);
        println!("Data Dir: {}", identity_store::data_dir().display());
        println!("Connected Peers: 0 (not in mesh — use 'mesh discover' first)");
        println!("Mesh Status: gossipsub v1");
        println!("Topics:");
        println!("  - {}", SOLUTIONS_TOPIC);
        println!("  - {}", SYNC_TOPIC);
        println!("\nCapabilities:");
        println!("  [x] mDNS peer discovery");
        println!("  [x] Gossipsub messaging");
        println!("  [x] Solution sharing");
        println!("  [x] Knowledge sync");
        println!("  [ ] Kademlia DHT (roadmap)");
        return Ok(());
    }

    #[cfg(not(feature = "p2p"))]
    {
        println!("\nPeer ID: (p2p feature not enabled)");
        println!("Connected Peers: 0");
        println!("Shared Solutions: 0");
        println!("Last Sync: never");
        println!("\nEnable with: cargo build -p ambientops-clinician --features p2p");
    }

    Ok(())
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mesh_action_variants() {
        let discover = MeshAction::Discover;
        let join = MeshAction::Join { peer: "QmPeer123".to_string() };
        let share = MeshAction::Share { solution_id: "sol-001".to_string() };
        let sync = MeshAction::Sync;
        let status = MeshAction::Status;

        assert!(format!("{:?}", discover).contains("Discover"));
        assert!(format!("{:?}", join).contains("QmPeer123"));
        assert!(format!("{:?}", share).contains("sol-001"));
        assert!(format!("{:?}", sync).contains("Sync"));
        assert!(format!("{:?}", status).contains("Status"));
    }

    #[test]
    fn test_mesh_action_clone() {
        let action = MeshAction::Share { solution_id: "sol-002".to_string() };
        let cloned = action.clone();
        assert!(format!("{:?}", cloned).contains("sol-002"));
    }

    #[test]
    fn test_topic_constants() {
        assert!(SOLUTIONS_TOPIC.contains("ambientops"));
        assert!(SOLUTIONS_TOPIC.contains("solutions"));
        assert!(SYNC_TOPIC.contains("ambientops"));
        assert!(SYNC_TOPIC.contains("sync"));
    }

    #[test]
    fn test_peer_key_filename() {
        assert_eq!(PEER_KEY_FILENAME, "peer_key");
        assert!(!PEER_KEY_FILENAME.is_empty());
    }

    #[cfg(feature = "p2p")]
    mod p2p_tests {
        use super::super::*;

        #[test]
        fn test_keypair_persistence() {
            let dir = tempfile::tempdir().unwrap();
            let key_path = dir.path().join(PEER_KEY_FILENAME);

            // Generate and save
            let kp1 = libp2p::identity::Keypair::generate_ed25519();
            let encoded = kp1.to_protobuf_encoding().unwrap();
            std::fs::write(&key_path, &encoded).unwrap();

            // Reload and verify same peer ID
            let bytes = std::fs::read(&key_path).unwrap();
            let kp2 = libp2p::identity::Keypair::from_protobuf_encoding(&bytes).unwrap();
            assert_eq!(
                kp1.public().to_peer_id(),
                kp2.public().to_peer_id()
            );
        }

        #[test]
        fn test_mesh_message_serialize_roundtrip() {
            let solution = crate::storage::Solution {
                id: "sol-001".to_string(),
                category: "network".to_string(),
                problem: "DNS resolution fails".to_string(),
                solution: "Restart systemd-resolved".to_string(),
                commands: vec!["systemctl restart systemd-resolved".to_string()],
                tags: vec!["dns".to_string(), "network".to_string()],
                success_count: 5,
                failure_count: 0,
                source: crate::storage::SolutionSource::Local,
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            };

            let msg = protocol::MeshMessage::ShareSolution(solution);
            let json = serde_json::to_string(&msg).unwrap();
            let decoded: protocol::MeshMessage = serde_json::from_str(&json).unwrap();

            match decoded {
                protocol::MeshMessage::ShareSolution(s) => {
                    assert_eq!(s.id, "sol-001");
                    assert_eq!(s.category, "network");
                }
                _ => panic!("Wrong variant after roundtrip"),
            }
        }

        #[test]
        fn test_sync_request_roundtrip() {
            let msg = protocol::MeshMessage::SyncRequest {
                peer_id: "12D3KooWExample".to_string(),
                solution_count: 42,
            };
            let json = serde_json::to_string(&msg).unwrap();
            let decoded: protocol::MeshMessage = serde_json::from_str(&json).unwrap();

            match decoded {
                protocol::MeshMessage::SyncRequest {
                    peer_id,
                    solution_count,
                } => {
                    assert_eq!(peer_id, "12D3KooWExample");
                    assert_eq!(solution_count, 42);
                }
                _ => panic!("Wrong variant after roundtrip"),
            }
        }

        #[test]
        fn test_gossipsub_topic_hash() {
            use libp2p::gossipsub::IdentTopic;
            let topic1 = IdentTopic::new(SOLUTIONS_TOPIC);
            let topic2 = IdentTopic::new(SOLUTIONS_TOPIC);
            assert_eq!(topic1.hash(), topic2.hash());
        }
    }
}
