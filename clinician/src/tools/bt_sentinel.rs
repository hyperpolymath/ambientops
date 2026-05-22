// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! BT Sentinel — Bluetooth device monitoring and alerting.
//!
//! Scans for nearby Bluetooth devices using the BlueZ D-Bus API (via the `bluer`
//! crate). Tracks known devices, alerts on new unknown devices, and logs
//! connection/disconnection events.
//!
//! Requires the `bluetooth` feature to be enabled for real hardware scanning.
//! Without the feature, uses a hcitool/bluetoothctl fallback via subprocess.

use anyhow::Result;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Represents a discovered Bluetooth device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BtDevice {
    /// MAC address of the device (e.g. "AA:BB:CC:DD:EE:FF").
    pub address: String,
    /// Human-readable name (if available).
    pub name: Option<String>,
    /// Device class (e.g. "Audio", "Phone", "Computer").
    pub device_class: Option<String>,
    /// Signal strength in dBm (if available).
    pub rssi: Option<i16>,
    /// Whether the device is currently connected.
    pub connected: bool,
    /// Whether the device is paired with this host.
    pub paired: bool,
    /// Whether this device is in the known/trusted list.
    pub trusted: bool,
    /// Timestamp of first discovery in this session.
    pub first_seen: DateTime<Local>,
    /// Timestamp of last activity.
    pub last_seen: DateTime<Local>,
}

/// Event types for BT Sentinel logging.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BtEvent {
    /// A new, previously-unknown device appeared.
    NewDeviceDiscovered(BtDevice),
    /// A device connected to this host.
    DeviceConnected {
        address: String,
        name: Option<String>,
    },
    /// A device disconnected from this host.
    DeviceDisconnected {
        address: String,
        name: Option<String>,
    },
    /// A known device reappeared after absence.
    DeviceReappeared {
        address: String,
        name: Option<String>,
    },
    /// Scan started.
    ScanStarted,
    /// Scan completed with device count.
    ScanCompleted { device_count: usize },
}

/// Configuration for BT Sentinel.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BtSentinelConfig {
    /// Path to the known-devices database file (JSON).
    pub known_devices_path: PathBuf,
    /// Whether to alert on new unknown devices.
    pub alert_on_unknown: bool,
    /// Scan duration in seconds for each sweep.
    pub scan_duration_secs: u64,
}

impl Default for BtSentinelConfig {
    fn default() -> Self {
        let data_dir = directories::ProjectDirs::from("com", "hyperpolymath", "ambientops")
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));
        Self {
            known_devices_path: data_dir.join("bt_known_devices.json"),
            alert_on_unknown: true,
            scan_duration_secs: 10,
        }
    }
}

/// Persistent registry of known Bluetooth devices.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct KnownDeviceRegistry {
    /// Map from MAC address to stored device info.
    pub devices: HashMap<String, BtDevice>,
}

impl KnownDeviceRegistry {
    /// Load from disk, creating an empty registry if the file does not exist.
    pub fn load(path: &std::path::Path) -> Result<Self> {
        if path.exists() {
            let data = std::fs::read_to_string(path)?;
            let registry: KnownDeviceRegistry = serde_json::from_str(&data)?;
            Ok(registry)
        } else {
            Ok(Self::default())
        }
    }

    /// Persist the registry to disk.
    pub fn save(&self, path: &std::path::Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let data = serde_json::to_string_pretty(self)?;
        std::fs::write(path, data)?;
        Ok(())
    }

    /// Check whether a device address is known.
    pub fn is_known(&self, address: &str) -> bool {
        self.devices.contains_key(address)
    }

    /// Register a device as known.
    pub fn register(&mut self, device: BtDevice) {
        self.devices.insert(device.address.clone(), device);
    }
}

/// BT Sentinel action types for CLI dispatch.
#[derive(Debug, Clone)]
pub enum BtAction {
    /// Perform a single scan and report findings.
    Scan,
    /// List all known/trusted devices.
    ListKnown,
    /// Add a device address to the trusted list.
    Trust { address: String },
    /// Remove a device address from the trusted list.
    Untrust { address: String },
    /// Show current adapter status.
    Status,
}

/// Handle a BT Sentinel CLI action.
pub async fn handle(action: BtAction) -> Result<()> {
    let config = BtSentinelConfig::default();

    match action {
        BtAction::Scan => scan_devices(&config).await?,
        BtAction::ListKnown => list_known(&config)?,
        BtAction::Trust { address } => trust_device(&config, &address)?,
        BtAction::Untrust { address } => untrust_device(&config, &address)?,
        BtAction::Status => show_adapter_status().await?,
    }

    Ok(())
}

/// Perform a Bluetooth device scan.
///
/// With the `bluetooth` feature enabled, uses the BlueZ D-Bus API directly.
/// Without the feature, falls back to parsing `bluetoothctl` output.
pub async fn scan_devices(config: &BtSentinelConfig) -> Result<()> {
    println!("BT Sentinel - Bluetooth Device Scanner");
    println!("{}", "=".repeat(50));

    let mut registry = KnownDeviceRegistry::load(&config.known_devices_path)?;
    let events = do_scan(config, &mut registry).await?;

    // Print results.
    println!("\nScan Results:");
    println!("{}", "-".repeat(50));

    let mut device_count = 0usize;
    for event in &events {
        match event {
            BtEvent::NewDeviceDiscovered(dev) => {
                device_count += 1;
                let alert = if config.alert_on_unknown {
                    " [!!! NEW/UNKNOWN]"
                } else {
                    ""
                };
                println!(
                    "  NEW  {} {:30} RSSI:{:>4} dBm{}",
                    dev.address,
                    dev.name.as_deref().unwrap_or("(unnamed)"),
                    dev.rssi.unwrap_or(0),
                    alert,
                );
            }
            BtEvent::DeviceReappeared { address, name } => {
                device_count += 1;
                println!(
                    "  OK   {} {:30} (known)",
                    address,
                    name.as_deref().unwrap_or("(unnamed)"),
                );
            }
            BtEvent::DeviceConnected { address, name } => {
                println!(
                    "  CONN {} {}",
                    address,
                    name.as_deref().unwrap_or("(unnamed)"),
                );
            }
            BtEvent::DeviceDisconnected { address, name } => {
                println!(
                    "  DISC {} {}",
                    address,
                    name.as_deref().unwrap_or("(unnamed)"),
                );
            }
            BtEvent::ScanStarted => {
                println!("  Scanning for {} seconds...", config.scan_duration_secs);
            }
            BtEvent::ScanCompleted { device_count: n } => {
                println!("\n  Total devices found: {}", n);
            }
        }
    }

    if device_count == 0 {
        println!("  No devices discovered.");
    }

    // Persist updated registry.
    registry.save(&config.known_devices_path)?;
    println!(
        "\nKnown device database: {} entries ({})",
        registry.devices.len(),
        config.known_devices_path.display()
    );

    Ok(())
}

/// Internal scan implementation — dispatches to bluer or fallback.
async fn do_scan(config: &BtSentinelConfig, registry: &mut KnownDeviceRegistry) -> Result<Vec<BtEvent>> {
    #[cfg(feature = "bluetooth")]
    {
        return scan_with_bluer(config, registry).await;
    }

    #[cfg(not(feature = "bluetooth"))]
    {
        return scan_with_bluetoothctl(config, registry).await;
    }
}

/// Scan using the BlueZ D-Bus API via the `bluer` crate.
#[cfg(feature = "bluetooth")]
async fn scan_with_bluer(
    config: &BtSentinelConfig,
    registry: &mut KnownDeviceRegistry,
) -> Result<Vec<BtEvent>> {
    use bluer::{Adapter, AdapterEvent, Address};
    use futures::StreamExt;

    let mut events = vec![BtEvent::ScanStarted];
    let session = bluer::Session::new().await?;
    let adapter = session.default_adapter().await?;
    adapter.set_powered(true).await?;

    tracing::info!(
        "BT Sentinel: scanning on adapter {} ({})",
        adapter.name(),
        adapter.address().await?
    );

    // Start discovery.
    let discover = adapter.discover_devices().await?;
    tokio::pin!(discover);

    let deadline =
        tokio::time::Instant::now() + tokio::time::Duration::from_secs(config.scan_duration_secs);
    let mut discovered: HashMap<Address, BtDevice> = HashMap::new();

    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(deadline) => break,
            evt = discover.next() => {
                match evt {
                    Some(AdapterEvent::DeviceAdded(addr)) => {
                        if let Ok(device) = adapter.device(addr) {
                            let now = Local::now();
                            let name = device.name().await.ok().flatten();
                            let rssi = device.rssi().await.ok().flatten();
                            let connected = device.is_connected().await.unwrap_or(false);
                            let paired = device.is_paired().await.unwrap_or(false);
                            let trusted = device.is_trusted().await.unwrap_or(false);
                            let class = device.class().await.ok().flatten()
                                .map(|c| classify_device_class(c));

                            let bt_dev = BtDevice {
                                address: addr.to_string(),
                                name: name.clone(),
                                device_class: class,
                                rssi,
                                connected,
                                paired,
                                trusted,
                                first_seen: now,
                                last_seen: now,
                            };

                            if registry.is_known(&addr.to_string()) {
                                events.push(BtEvent::DeviceReappeared {
                                    address: addr.to_string(),
                                    name,
                                });
                            } else {
                                events.push(BtEvent::NewDeviceDiscovered(bt_dev.clone()));
                                registry.register(bt_dev.clone());
                            }

                            if connected {
                                events.push(BtEvent::DeviceConnected {
                                    address: addr.to_string(),
                                    name: bt_dev.name.clone(),
                                });
                            }

                            discovered.insert(addr, bt_dev);
                        }
                    }
                    Some(AdapterEvent::DeviceRemoved(addr)) => {
                        let name = discovered.get(&addr).and_then(|d| d.name.clone());
                        events.push(BtEvent::DeviceDisconnected {
                            address: addr.to_string(),
                            name,
                        });
                    }
                    None => break,
                    _ => {}
                }
            }
        }
    }

    events.push(BtEvent::ScanCompleted {
        device_count: discovered.len(),
    });

    Ok(events)
}

/// Fallback scanner using `bluetoothctl` subprocess.
///
/// Parses the output of `bluetoothctl devices` to enumerate paired/nearby
/// devices. Less capable than the D-Bus path but works without the `bluer`
/// dependency.
#[cfg(not(feature = "bluetooth"))]
async fn scan_with_bluetoothctl(
    config: &BtSentinelConfig,
    registry: &mut KnownDeviceRegistry,
) -> Result<Vec<BtEvent>> {
    let mut events = vec![BtEvent::ScanStarted];

    tracing::info!("BT Sentinel: using bluetoothctl fallback (enable `bluetooth` feature for D-Bus scanning)");

    // Trigger a short scan via bluetoothctl.
    let scan_duration = std::cmp::min(config.scan_duration_secs, 15);
    let scan_result = tokio::process::Command::new("bluetoothctl")
        .args(["--timeout", &scan_duration.to_string(), "scan", "on"])
        .output()
        .await;

    if let Err(e) = &scan_result {
        tracing::warn!("bluetoothctl scan failed: {}. Listing paired devices only.", e);
    }

    // List all devices bluetoothctl knows about.
    let output = tokio::process::Command::new("bluetoothctl")
        .args(["devices"])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let now = Local::now();
    let mut device_count = 0usize;

    for line in stdout.lines() {
        // Format: "Device AA:BB:CC:DD:EE:FF DeviceName"
        let parts: Vec<&str> = line.splitn(3, ' ').collect();
        if parts.len() >= 2 && parts[0] == "Device" {
            let address = parts[1].to_string();
            let name = parts.get(2).map(|s| s.to_string());

            // Query connection status for this device.
            let info_output = tokio::process::Command::new("bluetoothctl")
                .args(["info", &address])
                .output()
                .await;

            let (connected, paired, trusted, rssi) = if let Ok(info) = info_output {
                let info_text = String::from_utf8_lossy(&info.stdout);
                let connected = info_text.contains("Connected: yes");
                let paired = info_text.contains("Paired: yes");
                let trusted = info_text.contains("Trusted: yes");
                let rssi = parse_rssi_from_info(&info_text);
                (connected, paired, trusted, rssi)
            } else {
                (false, false, false, None)
            };

            let bt_dev = BtDevice {
                address: address.clone(),
                name: name.clone(),
                device_class: None,
                rssi,
                connected,
                paired,
                trusted,
                first_seen: now,
                last_seen: now,
            };

            if registry.is_known(&address) {
                events.push(BtEvent::DeviceReappeared {
                    address: address.clone(),
                    name,
                });
            } else {
                events.push(BtEvent::NewDeviceDiscovered(bt_dev.clone()));
                registry.register(bt_dev.clone());
            }

            if connected {
                events.push(BtEvent::DeviceConnected {
                    address: address.clone(),
                    name: bt_dev.name.clone(),
                });
            }

            device_count += 1;
        }
    }

    events.push(BtEvent::ScanCompleted { device_count });
    Ok(events)
}

/// Parse RSSI from `bluetoothctl info` output.
///
/// Looks for a line like "RSSI: 0xffffffc8 (-56)" and extracts the dBm value.
#[cfg(not(feature = "bluetooth"))]
fn parse_rssi_from_info(info_text: &str) -> Option<i16> {
    for line in info_text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("RSSI:") {
            // Try to find the parenthesised value first.
            if let Some(start) = trimmed.find('(') {
                if let Some(end) = trimmed.find(')') {
                    if let Ok(val) = trimmed[start + 1..end].parse::<i16>() {
                        return Some(val);
                    }
                }
            }
            // Fall back to parsing the hex value.
            if let Some(hex) = trimmed.strip_prefix("RSSI:") {
                let hex = hex.trim().trim_start_matches("0x");
                if let Ok(val) = u32::from_str_radix(hex, 16) {
                    return Some(val as i16);
                }
            }
        }
    }
    None
}

/// Classify a Bluetooth device class integer into a human-readable category.
///
/// Uses the Bluetooth SIG Major Device Class field (bits 12-8 of the 24-bit
/// CoD). See Bluetooth Assigned Numbers, Section 2.8.
#[cfg(feature = "bluetooth")]
fn classify_device_class(class: u32) -> String {
    let major = (class >> 8) & 0x1F;
    match major {
        0 => "Miscellaneous".to_string(),
        1 => "Computer".to_string(),
        2 => "Phone".to_string(),
        3 => "LAN/Network".to_string(),
        4 => "Audio/Video".to_string(),
        5 => "Peripheral".to_string(),
        6 => "Imaging".to_string(),
        7 => "Wearable".to_string(),
        8 => "Toy".to_string(),
        9 => "Health".to_string(),
        _ => format!("Unknown(0x{:06x})", class),
    }
}

/// List all known devices from the persistent registry.
fn list_known(config: &BtSentinelConfig) -> Result<()> {
    let registry = KnownDeviceRegistry::load(&config.known_devices_path)?;

    println!("BT Sentinel - Known Devices");
    println!("{}", "=".repeat(60));

    if registry.devices.is_empty() {
        println!("  No known devices. Run `bt scan` to discover devices.");
        return Ok(());
    }

    println!(
        "{:<20} {:<30} {:<10} {:<10}",
        "ADDRESS", "NAME", "PAIRED", "TRUSTED"
    );
    println!("{}", "-".repeat(70));

    let mut devices: Vec<_> = registry.devices.values().collect();
    devices.sort_by_key(|d| &d.address);

    for dev in devices {
        println!(
            "{:<20} {:<30} {:<10} {:<10}",
            dev.address,
            dev.name.as_deref().unwrap_or("(unnamed)"),
            if dev.paired { "yes" } else { "no" },
            if dev.trusted { "yes" } else { "no" },
        );
    }

    println!(
        "\n{} devices in registry ({})",
        registry.devices.len(),
        config.known_devices_path.display()
    );

    Ok(())
}

/// Mark a device as trusted in the known-devices registry.
fn trust_device(config: &BtSentinelConfig, address: &str) -> Result<()> {
    let mut registry = KnownDeviceRegistry::load(&config.known_devices_path)?;

    if registry.devices.contains_key(address) {
        let dev = registry.devices.get_mut(address).unwrap();
        dev.trusted = true;
        let name = dev.name.clone();
        registry.save(&config.known_devices_path)?;
        println!("Trusted device: {} ({})", address, name.as_deref().unwrap_or("unnamed"));
    } else {
        // Register a minimal entry for a device we haven't scanned yet.
        let now = Local::now();
        let dev = BtDevice {
            address: address.to_string(),
            name: None,
            device_class: None,
            rssi: None,
            connected: false,
            paired: false,
            trusted: true,
            first_seen: now,
            last_seen: now,
        };
        registry.register(dev);
        registry.save(&config.known_devices_path)?;
        println!("Trusted new device: {} (added to registry)", address);
    }

    Ok(())
}

/// Remove trust from a device in the known-devices registry.
fn untrust_device(config: &BtSentinelConfig, address: &str) -> Result<()> {
    let mut registry = KnownDeviceRegistry::load(&config.known_devices_path)?;

    if registry.devices.contains_key(address) {
        let dev = registry.devices.get_mut(address).unwrap();
        dev.trusted = false;
        let name = dev.name.clone();
        registry.save(&config.known_devices_path)?;
        println!("Untrusted device: {} ({})", address, name.as_deref().unwrap_or("unnamed"));
    } else {
        println!("Device {} not found in registry.", address);
    }

    Ok(())
}

/// Show the status of the default Bluetooth adapter.
pub async fn show_adapter_status() -> Result<()> {
    println!("BT Sentinel - Adapter Status");
    println!("{}", "=".repeat(50));

    #[cfg(feature = "bluetooth")]
    {
        let session = bluer::Session::new().await?;
        let adapter = session.default_adapter().await?;

        println!("  Adapter:    {}", adapter.name());
        println!("  Address:    {}", adapter.address().await?);
        println!(
            "  Powered:    {}",
            if adapter.is_powered().await? { "yes" } else { "no" }
        );
        println!(
            "  Discoverable: {}",
            if adapter.is_discoverable().await? { "yes" } else { "no" }
        );
        println!(
            "  Pairable:   {}",
            if adapter.is_pairable().await? { "yes" } else { "no" }
        );

        return Ok(());
    }

    #[cfg(not(feature = "bluetooth"))]
    {
        let output = tokio::process::Command::new("bluetoothctl")
            .args(["show"])
            .output()
            .await?;

        let stdout = String::from_utf8_lossy(&output.stdout);

        if stdout.is_empty() {
            println!("  No Bluetooth adapter found (or bluetoothctl unavailable).");
        } else {
            for line in stdout.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("Controller")
                    || trimmed.starts_with("Name:")
                    || trimmed.starts_with("Powered:")
                    || trimmed.starts_with("Discoverable:")
                    || trimmed.starts_with("Pairable:")
                    || trimmed.starts_with("Address:")
                {
                    println!("  {}", trimmed);
                }
            }
        }

        println!("\n  (Enable `bluetooth` feature for full D-Bus integration)");
        return Ok(());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_known_device_registry_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("bt_known.json");

        let mut registry = KnownDeviceRegistry::default();
        let now = Local::now();

        registry.register(BtDevice {
            address: "AA:BB:CC:DD:EE:FF".to_string(),
            name: Some("Test Speaker".to_string()),
            device_class: Some("Audio/Video".to_string()),
            rssi: Some(-55),
            connected: false,
            paired: true,
            trusted: true,
            first_seen: now,
            last_seen: now,
        });

        registry.save(&path).unwrap();

        let loaded = KnownDeviceRegistry::load(&path).unwrap();
        assert_eq!(loaded.devices.len(), 1);
        assert!(loaded.is_known("AA:BB:CC:DD:EE:FF"));
        assert!(!loaded.is_known("00:00:00:00:00:00"));

        let dev = &loaded.devices["AA:BB:CC:DD:EE:FF"];
        assert_eq!(dev.name.as_deref(), Some("Test Speaker"));
        assert!(dev.trusted);
    }

    #[test]
    fn test_empty_registry_load_nonexistent() {
        let path = std::path::Path::new("/tmp/nonexistent_bt_sentinel_test.json");
        let registry = KnownDeviceRegistry::load(path).unwrap();
        assert!(registry.devices.is_empty());
    }

    #[test]
    fn test_trust_and_untrust() {
        let dir = tempfile::tempdir().unwrap();
        let config = BtSentinelConfig {
            known_devices_path: dir.path().join("bt_known.json"),
            alert_on_unknown: true,
            scan_duration_secs: 5,
        };

        // Trust a new address (should create a registry entry).
        trust_device(&config, "11:22:33:44:55:66").unwrap();
        let reg = KnownDeviceRegistry::load(&config.known_devices_path).unwrap();
        assert!(reg.devices["11:22:33:44:55:66"].trusted);

        // Untrust it.
        untrust_device(&config, "11:22:33:44:55:66").unwrap();
        let reg = KnownDeviceRegistry::load(&config.known_devices_path).unwrap();
        assert!(!reg.devices["11:22:33:44:55:66"].trusted);
    }
}
