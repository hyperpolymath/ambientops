// SPDX-License-Identifier: PMPL-1.0-or-later
//! Network diagnostics tools (like TCPView)

use anyhow::Result;
use crate::storage::Storage;
use crate::cache::Cache;

/// Network action types
#[derive(Debug, Clone)]
pub enum NetworkAction {
    Connections { state: Option<String> },
    Listen,
    Bandwidth,
    Ping { host: String },
    Dns { domain: String },
    Watch,
}

/// Handle network subcommands
pub async fn handle(action: NetworkAction, _storage: &Storage, _cache: &Cache) -> Result<()> {
    match action {
        NetworkAction::Connections { state } => {
            show_connections(state.as_deref()).await?;
        }
        NetworkAction::Listen => {
            show_listening_ports().await?;
        }
        NetworkAction::Bandwidth => {
            show_bandwidth().await?;
        }
        NetworkAction::Ping { host } => {
            ping_host(&host).await?;
        }
        NetworkAction::Dns { domain } => {
            dns_lookup(&domain).await?;
        }
        NetworkAction::Watch => {
            watch_connections().await?;
        }
    }

    Ok(())
}

async fn show_connections(state_filter: Option<&str>) -> Result<()> {
    println!("{:<6} {:<23} {:<23} {:<12} PROCESS", "PROTO", "LOCAL", "REMOTE", "STATE");
    println!("{}", "-".repeat(80));

    // Use netstat2 or procfs to get connections
    // For now, use /proc/net directly
    if let Ok(tcp) = std::fs::read_to_string("/proc/net/tcp") {
        for line in tcp.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let local = parse_socket_addr(parts[1]);
                let remote = parse_socket_addr(parts[2]);
                let state = parse_tcp_state(parts[3]);

                if let Some(filter) = state_filter {
                    if !state.to_uppercase().contains(&filter.to_uppercase()) {
                        continue;
                    }
                }

                println!("{:<6} {:<23} {:<23} {:<12}", "TCP", local, remote, state);
            }
        }
    }

    if let Ok(tcp6) = std::fs::read_to_string("/proc/net/tcp6") {
        for line in tcp6.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let local = parse_socket_addr6(parts[1]);
                let remote = parse_socket_addr6(parts[2]);
                let state = parse_tcp_state(parts[3]);

                if let Some(filter) = state_filter {
                    if !state.to_uppercase().contains(&filter.to_uppercase()) {
                        continue;
                    }
                }

                println!("{:<6} {:<23} {:<23} {:<12}", "TCP6", local, remote, state);
            }
        }
    }

    Ok(())
}

fn parse_socket_addr(hex: &str) -> String {
    let parts: Vec<&str> = hex.split(':').collect();
    if parts.len() == 2 {
        let ip = u32::from_str_radix(parts[0], 16).unwrap_or(0);
        let port = u16::from_str_radix(parts[1], 16).unwrap_or(0);
        format!(
            "{}.{}.{}.{}:{}",
            ip & 0xFF,
            (ip >> 8) & 0xFF,
            (ip >> 16) & 0xFF,
            (ip >> 24) & 0xFF,
            port
        )
    } else {
        hex.to_string()
    }
}

fn parse_socket_addr6(hex: &str) -> String {
    let parts: Vec<&str> = hex.split(':').collect();
    if parts.len() == 2 {
        let port = u16::from_str_radix(parts[1], 16).unwrap_or(0);
        format!("[::]::{}", port)
    } else {
        hex.to_string()
    }
}

fn parse_tcp_state(hex: &str) -> &'static str {
    match u8::from_str_radix(hex, 16).unwrap_or(0) {
        0x01 => "ESTABLISHED",
        0x02 => "SYN_SENT",
        0x03 => "SYN_RECV",
        0x04 => "FIN_WAIT1",
        0x05 => "FIN_WAIT2",
        0x06 => "TIME_WAIT",
        0x07 => "CLOSE",
        0x08 => "CLOSE_WAIT",
        0x09 => "LAST_ACK",
        0x0A => "LISTEN",
        0x0B => "CLOSING",
        _ => "UNKNOWN",
    }
}

async fn show_listening_ports() -> Result<()> {
    println!("{:<6} {:<23} PROCESS", "PROTO", "ADDRESS");
    println!("{}", "-".repeat(50));

    // Show only listening sockets
    if let Ok(tcp) = std::fs::read_to_string("/proc/net/tcp") {
        for line in tcp.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let state = u8::from_str_radix(parts[3], 16).unwrap_or(0);
                if state == 0x0A {
                    // LISTEN
                    let local = parse_socket_addr(parts[1]);
                    println!("{:<6} {:<23}", "TCP", local);
                }
            }
        }
    }

    if let Ok(tcp6) = std::fs::read_to_string("/proc/net/tcp6") {
        for line in tcp6.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 4 {
                let state = u8::from_str_radix(parts[3], 16).unwrap_or(0);
                if state == 0x0A {
                    let local = parse_socket_addr6(parts[1]);
                    println!("{:<6} {:<23}", "TCP6", local);
                }
            }
        }
    }

    Ok(())
}

async fn show_bandwidth() -> Result<()> {
    println!("Network interface bandwidth:");
    println!("{}", "-".repeat(60));

    if let Ok(content) = std::fs::read_to_string("/proc/net/dev") {
        println!("{:<12} {:>15} {:>15}", "INTERFACE", "RX (bytes)", "TX (bytes)");

        for line in content.lines().skip(2) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 10 {
                let iface = parts[0].trim_end_matches(':');
                let rx_bytes: u64 = parts[1].parse().unwrap_or(0);
                let tx_bytes: u64 = parts[9].parse().unwrap_or(0);

                println!(
                    "{:<12} {:>15} {:>15}",
                    iface,
                    format_bytes(rx_bytes),
                    format_bytes(tx_bytes)
                );
            }
        }
    }

    Ok(())
}

fn format_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

async fn ping_host(host: &str) -> Result<()> {
    println!("Pinging {}...", host);

    let output = tokio::process::Command::new("ping")
        .args(["-c", "4", host])
        .output()
        .await?;

    println!("{}", String::from_utf8_lossy(&output.stdout));

    if !output.status.success() {
        println!("{}", String::from_utf8_lossy(&output.stderr));
    }

    Ok(())
}

async fn dns_lookup(domain: &str) -> Result<()> {
    println!("DNS lookup for {}...", domain);

    // Use getaddrinfo via tokio
    let addrs = tokio::net::lookup_host(format!("{}:80", domain)).await?;

    println!("\nResolved addresses:");
    for addr in addrs {
        println!("  {}", addr.ip());
    }

    // Also try dig/host for more details
    if let Ok(output) = tokio::process::Command::new("host")
        .arg(domain)
        .output()
        .await
    {
        println!("\nDNS records:");
        println!("{}", String::from_utf8_lossy(&output.stdout));
    }

    Ok(())
}

async fn watch_connections() -> Result<()> {
    println!("Watching for new/suspicious connections...");
    println!("(Press Ctrl+C to stop)");
    println!();

    // TODO: Integrate ESN/LSM for anomaly detection
    // This would:
    // 1. Baseline normal connection patterns
    // 2. Alert on unusual ports, destinations, or traffic patterns

    let mut prev_connections = std::collections::HashSet::new();

    loop {
        let mut current_connections = std::collections::HashSet::new();

        if let Ok(tcp) = std::fs::read_to_string("/proc/net/tcp") {
            for line in tcp.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    let conn = format!("{}->{}", parts[1], parts[2]);
                    current_connections.insert(conn);
                }
            }
        }

        // Find new connections
        for conn in current_connections.difference(&prev_connections) {
            println!(
                "[{}] NEW: {}",
                chrono::Local::now().format("%H:%M:%S"),
                conn
            );
        }

        prev_connections = current_connections;
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    }
}
