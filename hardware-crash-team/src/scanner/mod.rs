// SPDX-License-Identifier: PMPL-1.0-or-later
//! PCI device scanner
//!
//! Enumerates PCI devices via sysfs, checks driver bindings,
//! power states, IOMMU groups, and detects zombie hardware.

use crate::types::*;
use anyhow::Result;
use std::fs;
use std::path::Path;

/// Scan the entire system for hardware issues
pub fn scan_system(verbose: bool) -> Result<SystemReport> {
    let devices = scan_pci_devices(verbose)?;
    let iommu = scan_iommu()?;
    let acpi_errors = scan_acpi_errors()?;

    let risk_level = assess_risk(&devices, &acpi_errors);

    Ok(SystemReport {
        timestamp: chrono::Utc::now().to_rfc3339(),
        kernel_version: read_kernel_version(),
        devices,
        iommu,
        acpi_errors,
        risk_level,
    })
}

/// Scan all PCI devices via /sys/bus/pci/devices/
fn scan_pci_devices(verbose: bool) -> Result<Vec<PciDevice>> {
    let pci_path = Path::new("/sys/bus/pci/devices");
    let mut devices = Vec::new();

    if !pci_path.exists() {
        anyhow::bail!("Cannot access /sys/bus/pci/devices - are you on Linux?");
    }

    for entry in fs::read_dir(pci_path)? {
        let entry = entry?;
        let slot_path = entry.path();
        let slot = entry.file_name().to_string_lossy().to_string();

        let device = scan_single_device(&slot, &slot_path, verbose)?;
        devices.push(device);
    }

    devices.sort_by(|a, b| a.slot.cmp(&b.slot));
    Ok(devices)
}

/// Scan a single PCI device
fn scan_single_device(slot: &str, path: &Path, _verbose: bool) -> Result<PciDevice> {
    let vendor_id = read_sysfs_hex(path, "vendor");
    let device_id = read_sysfs_hex(path, "device");
    let pci_id = format!("{}:{}", vendor_id, device_id);

    let class = read_sysfs_string(path, "class");
    let driver = read_driver(path);
    let enabled = read_sysfs_string(path, "enable") == "1";
    let power_state = read_power_state(path);
    let iommu_group = read_iommu_group(path);

    let mut issues = Vec::new();

    // Detect zombie devices: powered on, no driver, but enabled or in D0
    if driver.is_none() && (power_state == PowerState::D0 || enabled) {
        issues.push(DeviceIssue {
            severity: IssueSeverity::High,
            issue_type: IssueType::ZombieDevice,
            description: format!(
                "Device {} is in {:?} power state with no driver managing it",
                slot, power_state
            ),
            remediation: "Claim with pci-stub or vfio-pci null driver".to_string(),
        });
    }

    // Detect partial bindings (e.g., audio codec on GPU chip)
    if let Some(ref drv) = driver {
        if drv == "snd_hda_intel" && pci_id.starts_with("10de:") {
            issues.push(DeviceIssue {
                severity: IssueSeverity::Warning,
                issue_type: IssueType::PartialBinding,
                description: format!(
                    "NVIDIA audio codec {} bound to snd_hda_intel - partial GPU binding",
                    slot
                ),
                remediation: "Claim with pci-stub to prevent partial binding".to_string(),
            });
        }
    }

    Ok(PciDevice {
        slot: slot.to_string(),
        pci_id,
        description: String::new(), // Filled by lspci lookup
        vendor: vendor_id,
        class,
        driver,
        kernel_modules: Vec::new(),
        power_state,
        enabled,
        iommu_group,
        memory_regions: Vec::new(),
        issues,
    })
}

/// Read IOMMU status
fn scan_iommu() -> Result<IommuStatus> {
    let groups_path = Path::new("/sys/kernel/iommu_groups");
    let enabled = groups_path.exists();

    let group_count = if enabled {
        fs::read_dir(groups_path)?.count() as u32
    } else {
        0
    };

    Ok(IommuStatus {
        enabled,
        iommu_type: if enabled {
            // Check for Intel VT-d or AMD-Vi
            let dmar = Path::new("/sys/firmware/acpi/tables/DMAR");
            let ivrs = Path::new("/sys/firmware/acpi/tables/IVRS");
            if dmar.exists() {
                Some("Intel VT-d".to_string())
            } else if ivrs.exists() {
                Some("AMD-Vi".to_string())
            } else {
                Some("Unknown".to_string())
            }
        } else {
            None
        },
        group_count,
        interrupt_remapping: enabled, // Simplified; real check reads DMAR table
    })
}

/// Scan for ACPI errors in kernel log
fn scan_acpi_errors() -> Result<Vec<AcpiError>> {
    // In real implementation, parse journalctl -k for ACPI errors
    // For now, return empty
    Ok(Vec::new())
}

/// Assess overall system risk
fn assess_risk(devices: &[PciDevice], acpi_errors: &[AcpiError]) -> RiskLevel {
    let critical = devices.iter()
        .flat_map(|d| &d.issues)
        .any(|i| i.severity == IssueSeverity::Critical);

    let high = devices.iter()
        .flat_map(|d| &d.issues)
        .filter(|i| i.severity == IssueSeverity::High)
        .count();

    if critical {
        RiskLevel::Critical
    } else if high > 0 || !acpi_errors.is_empty() {
        RiskLevel::High
    } else if devices.iter().any(|d| !d.issues.is_empty()) {
        RiskLevel::Medium
    } else {
        RiskLevel::Clean
    }
}

/// Format report for output
pub fn format_report(report: &SystemReport, format: &str) -> Result<String> {
    match format {
        "json" => Ok(serde_json::to_string_pretty(report)?),
        "text" | _ => Ok(format_text_report(report)),
    }
}

/// Print system status summary
pub fn print_status(report: &SystemReport) {
    println!("Kernel: {}", report.kernel_version);
    println!("IOMMU: {} ({})",
        if report.iommu.enabled { "enabled" } else { "disabled" },
        report.iommu.iommu_type.as_deref().unwrap_or("N/A")
    );
    println!("PCI devices: {}", report.devices.len());

    let issues: Vec<_> = report.devices.iter()
        .filter(|d| !d.issues.is_empty())
        .collect();

    if issues.is_empty() {
        println!("Issues: none detected");
    } else {
        println!("Issues: {} device(s) with problems", issues.len());
        for dev in issues {
            for issue in &dev.issues {
                println!("  [{:?}] {} - {}", issue.severity, dev.slot, issue.description);
            }
        }
    }
}

fn format_text_report(report: &SystemReport) -> String {
    let mut out = String::new();
    out.push_str(&format!("Hardware Crash Team Scan Report\n"));
    out.push_str(&format!("==============================\n"));
    out.push_str(&format!("Timestamp: {}\n", report.timestamp));
    out.push_str(&format!("Kernel: {}\n", report.kernel_version));
    out.push_str(&format!("Risk Level: {:?}\n\n", report.risk_level));
    out
}

// Sysfs helper functions

fn read_sysfs_string(path: &Path, file: &str) -> String {
    fs::read_to_string(path.join(file))
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn read_sysfs_hex(path: &Path, file: &str) -> String {
    read_sysfs_string(path, file)
        .trim_start_matches("0x")
        .to_string()
}

fn read_driver(path: &Path) -> Option<String> {
    let driver_link = path.join("driver");
    if driver_link.exists() {
        fs::read_link(&driver_link)
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
    } else {
        None
    }
}

fn read_power_state(path: &Path) -> PowerState {
    match read_sysfs_string(path, "power_state").as_str() {
        "D0" => PowerState::D0,
        "D1" => PowerState::D1,
        "D2" => PowerState::D2,
        "D3hot" => PowerState::D3Hot,
        "D3cold" => PowerState::D3Cold,
        _ => PowerState::Unknown,
    }
}

fn read_iommu_group(path: &Path) -> Option<u32> {
    let iommu_link = path.join("iommu_group");
    if iommu_link.exists() {
        fs::read_link(&iommu_link)
            .ok()
            .and_then(|p| {
                p.file_name()
                    .and_then(|n| n.to_string_lossy().parse::<u32>().ok())
            })
    } else {
        None
    }
}

fn read_kernel_version() -> String {
    fs::read_to_string("/proc/version")
        .unwrap_or_default()
        .split_whitespace()
        .nth(2)
        .unwrap_or("unknown")
        .to_string()
}
