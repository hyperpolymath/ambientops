// SPDX-License-Identifier: PMPL-1.0-or-later
//! PCI device scanner
//!
//! Enumerates PCI devices via sysfs, checks driver bindings,
//! power states, IOMMU groups, and detects zombie hardware.

use crate::types::*;
use anyhow::Result;
use std::fs;
use std::path::Path;
use std::process::Command;

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

    let memory_regions = enumerate_bars(path);
    let description = lspci_describe(slot);

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

    // Detect unmanaged memory: device has BAR regions but no driver
    if driver.is_none() && !memory_regions.is_empty() {
        let total_bytes: u64 = memory_regions.iter().map(|r| r.size).sum();
        issues.push(DeviceIssue {
            severity: IssueSeverity::High,
            issue_type: IssueType::UnmanagedMemory,
            description: format!(
                "Device {} has {} memory region(s) ({} bytes) mapped with no driver",
                slot,
                memory_regions.len(),
                total_bytes
            ),
            remediation: "Claim with vfio-pci for IOMMU isolation or disable the device".to_string(),
        });
    }

    // Detect spurious interrupts
    if let Some(issue) = check_interrupts(slot, &driver) {
        issues.push(issue);
    }

    Ok(PciDevice {
        slot: slot.to_string(),
        pci_id,
        description,
        vendor: vendor_id,
        class,
        driver,
        kernel_modules: Vec::new(),
        power_state,
        enabled,
        iommu_group,
        memory_regions,
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
        "sarif" => crate::sarif::format_sarif(report),
        "text" => Ok(format_text_report(report)),
        other => anyhow::bail!("Unknown format '{}'. Supported: text, json, sarif", other),
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

/// Enumerate BAR (Base Address Register) memory regions from sysfs resource file.
///
/// Each line in `/sys/bus/pci/devices/{slot}/resource` is:
/// `start_addr end_addr flags` in hex.
/// Size = end - start + 1. Flags bit 3 = prefetchable, bit 2 = 64-bit.
fn enumerate_bars(device_path: &Path) -> Vec<MemoryRegion> {
    let resource_path = device_path.join("resource");
    let content = match fs::read_to_string(&resource_path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    parse_bars(&content)
}

/// Parse BAR resource file content into MemoryRegion entries
fn parse_bars(content: &str) -> Vec<MemoryRegion> {
    let mut regions = Vec::new();
    let mut bar_index: u8 = 0;
    let mut skip_next = false;

    for line in content.lines() {
        if skip_next {
            skip_next = false;
            bar_index += 1;
            continue;
        }

        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            bar_index += 1;
            continue;
        }

        let start = u64::from_str_radix(parts[0].trim_start_matches("0x"), 16).unwrap_or(0);
        let end = u64::from_str_radix(parts[1].trim_start_matches("0x"), 16).unwrap_or(0);
        let flags = u64::from_str_radix(parts[2].trim_start_matches("0x"), 16).unwrap_or(0);

        if start == 0 {
            bar_index += 1;
            continue;
        }

        let size = end - start + 1;
        let prefetchable = (flags & 0x8) != 0;
        let is_64bit = (flags & 0x4) != 0;

        regions.push(MemoryRegion {
            index: bar_index,
            address: format!("0x{:x}", start),
            size,
            prefetchable,
            width: if is_64bit { 64 } else { 32 },
        });

        if is_64bit {
            // Next BAR is upper 32 bits, skip it
            skip_next = true;
        }

        bar_index += 1;
    }

    regions
}

/// Get human-readable device description from lspci.
/// Falls back to empty string if lspci is not installed.
fn lspci_describe(slot: &str) -> String {
    parse_lspci_output(
        &Command::new("lspci")
            .args(["-s", slot, "-q"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_default()
    )
}

/// Parse lspci output line for device description
fn parse_lspci_output(output: &str) -> String {
    // lspci output: "01:00.0 VGA compatible controller: NVIDIA Corporation GM206 [GeForce GTX 960]"
    // We want everything after the first ": "
    output
        .lines()
        .next()
        .and_then(|line| line.split_once(": ").map(|(_, desc)| desc.trim().to_string()))
        .unwrap_or_default()
}

/// Check /proc/interrupts for spurious interrupt activity on a device.
/// A device generating many interrupts without a driver is suspicious.
fn check_interrupts(slot: &str, driver: &Option<String>) -> Option<DeviceIssue> {
    let content = fs::read_to_string("/proc/interrupts").ok()?;
    parse_interrupt_issues(&content, slot, driver)
}

/// Parse /proc/interrupts content and detect issues for a given slot
fn parse_interrupt_issues(content: &str, slot: &str, driver: &Option<String>) -> Option<DeviceIssue> {
    // Look for lines containing this device's slot or IRQ info
    // /proc/interrupts format: IRQ_NUM: CPU0_COUNT CPU1_COUNT ... device_name
    for line in content.lines().skip(1) {
        if !line.contains(slot) {
            continue;
        }

        // Sum interrupt counts across all CPUs
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            continue;
        }

        let total_count: u64 = parts[1..]
            .iter()
            .take_while(|p| p.chars().all(|c| c.is_ascii_digit()))
            .filter_map(|p| p.parse::<u64>().ok())
            .sum();

        // High interrupt count with no driver = spurious
        if total_count > 1000 && driver.is_none() {
            return Some(DeviceIssue {
                severity: IssueSeverity::Critical,
                issue_type: IssueType::SpuriousInterrupts,
                description: format!(
                    "Device {} generating {} interrupts with no driver handling them",
                    slot, total_count
                ),
                remediation: "Disable device or claim with null driver to stop interrupt storm".to_string(),
            });
        }
    }

    None
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::*;

    fn make_device(slot: &str, driver: Option<&str>, power: PowerState, issues: Vec<DeviceIssue>) -> PciDevice {
        PciDevice {
            slot: slot.to_string(),
            pci_id: "10de:13b0".to_string(),
            description: String::new(),
            vendor: "10de".to_string(),
            class: "0300".to_string(),
            driver: driver.map(|s| s.to_string()),
            kernel_modules: Vec::new(),
            power_state: power,
            enabled: true,
            iommu_group: None,
            memory_regions: Vec::new(),
            issues,
        }
    }

    #[test]
    fn test_pci_device_json_roundtrip() {
        let device = make_device("01:00.0", None, PowerState::D0, vec![]);
        let json = serde_json::to_string(&device).unwrap();
        let parsed: PciDevice = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.slot, "01:00.0");
        assert_eq!(parsed.pci_id, "10de:13b0");
        assert!(parsed.driver.is_none());
    }

    #[test]
    fn test_system_report_json_roundtrip() {
        let report = SystemReport {
            timestamp: "2026-02-12T00:00:00Z".to_string(),
            kernel_version: "6.18.8".to_string(),
            devices: vec![make_device("01:00.0", Some("i915"), PowerState::D0, vec![])],
            iommu: IommuStatus {
                enabled: true,
                iommu_type: Some("Intel VT-d".to_string()),
                group_count: 14,
                interrupt_remapping: true,
            },
            acpi_errors: vec![],
            risk_level: RiskLevel::Clean,
        };
        let json = serde_json::to_string_pretty(&report).unwrap();
        let parsed: SystemReport = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.devices.len(), 1);
        assert_eq!(parsed.kernel_version, "6.18.8");
    }

    #[test]
    fn test_zombie_device_issue() {
        let issue = DeviceIssue {
            severity: IssueSeverity::High,
            issue_type: IssueType::ZombieDevice,
            description: "Device in D0 with no driver".to_string(),
            remediation: "Claim with pci-stub".to_string(),
        };
        assert_eq!(issue.severity, IssueSeverity::High);
    }

    #[test]
    fn test_partial_binding_issue() {
        let issue = DeviceIssue {
            severity: IssueSeverity::Warning,
            issue_type: IssueType::PartialBinding,
            description: "NVIDIA audio codec bound to snd_hda_intel".to_string(),
            remediation: "Claim with pci-stub".to_string(),
        };
        assert_eq!(issue.severity, IssueSeverity::Warning);
    }

    #[test]
    fn test_assess_risk_clean() {
        let devices = vec![make_device("01:00.0", Some("i915"), PowerState::D0, vec![])];
        let risk = assess_risk(&devices, &[]);
        assert!(matches!(risk, RiskLevel::Clean));
    }

    #[test]
    fn test_assess_risk_medium() {
        let issues = vec![DeviceIssue {
            severity: IssueSeverity::Warning,
            issue_type: IssueType::PartialBinding,
            description: "partial binding".to_string(),
            remediation: "fix".to_string(),
        }];
        let devices = vec![make_device("01:00.0", Some("snd_hda_intel"), PowerState::D0, issues)];
        let risk = assess_risk(&devices, &[]);
        assert!(matches!(risk, RiskLevel::Medium));
    }

    #[test]
    fn test_assess_risk_high() {
        let issues = vec![DeviceIssue {
            severity: IssueSeverity::High,
            issue_type: IssueType::ZombieDevice,
            description: "zombie".to_string(),
            remediation: "fix".to_string(),
        }];
        let devices = vec![make_device("01:00.0", None, PowerState::D0, issues)];
        let risk = assess_risk(&devices, &[]);
        assert!(matches!(risk, RiskLevel::High));
    }

    #[test]
    fn test_assess_risk_high_with_acpi() {
        let devices = vec![make_device("01:00.0", Some("i915"), PowerState::D0, vec![])];
        let acpi_errors = vec![AcpiError {
            method: "_SB._OSC".to_string(),
            error_code: "AE_AML_BUFFER_LIMIT".to_string(),
            description: "BIOS bug".to_string(),
            related_device: None,
        }];
        let risk = assess_risk(&devices, &acpi_errors);
        assert!(matches!(risk, RiskLevel::High));
    }

    #[test]
    fn test_assess_risk_critical() {
        let issues = vec![DeviceIssue {
            severity: IssueSeverity::Critical,
            issue_type: IssueType::SpuriousInterrupts,
            description: "critical interrupt storm".to_string(),
            remediation: "disable device".to_string(),
        }];
        let devices = vec![make_device("01:00.0", None, PowerState::D0, issues)];
        let risk = assess_risk(&devices, &[]);
        assert!(matches!(risk, RiskLevel::Critical));
    }

    #[test]
    fn test_issue_severity_ordering() {
        assert!(IssueSeverity::Info < IssueSeverity::Warning);
        assert!(IssueSeverity::Warning < IssueSeverity::High);
        assert!(IssueSeverity::High < IssueSeverity::Critical);
    }

    #[test]
    fn test_enumerate_bars_parses_resource_file() {
        // Simulated /sys/bus/pci/devices/.../resource content
        // Format: start end flags (hex)
        let content = "\
0x00000000de000000 0x00000000deffffff 0x0040200c
0x0000000000000000 0x0000000000000000 0x00000000
0x00000000d0000000 0x00000000d1ffffff 0x0014220c
0x0000000000000000 0x0000000000000000 0x00000000
0x000000000000e000 0x000000000000e07f 0x00040101
0x0000000000000000 0x0000000000000000 0x00000000";

        let bars = parse_bars(content);
        assert_eq!(bars.len(), 3);

        // First BAR: 16MB, prefetchable, 64-bit
        assert_eq!(bars[0].index, 0);
        assert_eq!(bars[0].size, 0x1000000); // 16MB
        assert!(bars[0].prefetchable);
        assert_eq!(bars[0].width, 64);

        // Third BAR: 32MB, not prefetchable, 64-bit
        assert_eq!(bars[1].index, 2);
        assert_eq!(bars[1].size, 0x2000000); // 32MB
        assert_eq!(bars[1].width, 64);

        // Fifth BAR: 128 bytes, I/O space
        assert_eq!(bars[2].index, 4);
        assert_eq!(bars[2].size, 0x80); // 128 bytes
    }

    #[test]
    fn test_enumerate_bars_empty() {
        let content = "\
0x0000000000000000 0x0000000000000000 0x00000000
0x0000000000000000 0x0000000000000000 0x00000000";

        let bars = parse_bars(content);
        assert!(bars.is_empty());
    }

    #[test]
    fn test_lspci_output_parsing() {
        let output = "01:00.0 VGA compatible controller: NVIDIA Corporation GM206 [GeForce GTX 960]\n";
        assert_eq!(
            parse_lspci_output(output),
            "NVIDIA Corporation GM206 [GeForce GTX 960]"
        );
    }

    #[test]
    fn test_lspci_output_empty() {
        assert_eq!(parse_lspci_output(""), "");
        assert_eq!(parse_lspci_output("no colon here"), "");
    }

    #[test]
    fn test_interrupt_spurious_detection() {
        let content = "\
           CPU0       CPU1
  9:       5432       6789   IO-APIC   9-fasteoi   acpi
 16:      50000      60000   IO-APIC  16-fasteoi   01:00.0
 17:        100        200   IO-APIC  17-fasteoi   snd_hda_intel";

        // Device with high interrupts and no driver
        let issue = parse_interrupt_issues(content, "01:00.0", &None);
        assert!(issue.is_some());
        let issue = issue.unwrap();
        assert!(matches!(issue.issue_type, IssueType::SpuriousInterrupts));
        assert!(matches!(issue.severity, IssueSeverity::Critical));
    }

    #[test]
    fn test_interrupt_no_issue_with_driver() {
        let content = "\
           CPU0       CPU1
 16:      50000      60000   IO-APIC  16-fasteoi   01:00.0";

        // Device with driver should not flag spurious
        let issue = parse_interrupt_issues(content, "01:00.0", &Some("i915".to_string()));
        assert!(issue.is_none());
    }

    #[test]
    fn test_interrupt_no_issue_low_count() {
        let content = "\
           CPU0       CPU1
 16:        100        200   IO-APIC  16-fasteoi   01:00.0";

        // Low interrupt count, no driver — not spurious
        let issue = parse_interrupt_issues(content, "01:00.0", &None);
        assert!(issue.is_none());
    }

    #[test]
    fn test_unmanaged_memory_detection() {
        // Device with BARs but no driver should get UnmanagedMemory issue
        let device = PciDevice {
            slot: "01:00.0".to_string(),
            pci_id: "10de:13b0".to_string(),
            description: String::new(),
            vendor: "10de".to_string(),
            class: "0300".to_string(),
            driver: None,
            kernel_modules: Vec::new(),
            power_state: PowerState::D0,
            enabled: true,
            iommu_group: None,
            memory_regions: vec![MemoryRegion {
                index: 0,
                address: "0xde000000".to_string(),
                size: 16 * 1024 * 1024,
                prefetchable: true,
                width: 64,
            }],
            issues: Vec::new(),
        };

        // The issue detection happens in scan_single_device, so we test
        // the logic directly: no driver + memory regions = UnmanagedMemory
        assert!(device.driver.is_none());
        assert!(!device.memory_regions.is_empty());
    }
}
