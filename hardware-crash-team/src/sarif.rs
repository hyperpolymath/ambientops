// SPDX-License-Identifier: PMPL-1.0-or-later
//! SARIF 2.1.0 output format for hardware scan reports
//!
//! Maps hardware-crash-team scan results to the Static Analysis Results
//! Interchange Format (SARIF) for integration with VS Code, GitHub
//! Advanced Security, and other SARIF consumers.

use anyhow::Result;
use serde::Serialize;

use crate::types::{DeviceIssue, IssueSeverity, IssueType, PciDevice, SystemReport};

/// SARIF schema URL
const SARIF_SCHEMA: &str =
    "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json";

/// SARIF version
const SARIF_VERSION: &str = "2.1.0";

/// Tool name
const TOOL_NAME: &str = "hardware-crash-team";

/// Tool information URI
const TOOL_URI: &str = "https://github.com/hyperpolymath/ambientops";

// ── SARIF 2.1.0 Schema Types ──────────────────────────────────────────

/// Top-level SARIF log
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SarifLog {
    #[serde(rename = "$schema")]
    pub schema: String,
    pub version: String,
    pub runs: Vec<Run>,
}

/// A single analysis run
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Run {
    pub tool: Tool,
    pub results: Vec<SarifResult>,
    pub invocations: Vec<Invocation>,
}

/// Tool that produced the results
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Tool {
    pub driver: ToolDriver,
}

/// Tool driver metadata and rule definitions
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolDriver {
    pub name: String,
    pub version: String,
    pub semantic_version: String,
    pub information_uri: String,
    pub rules: Vec<ReportingDescriptor>,
}

/// A rule that can produce results (one per IssueType)
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportingDescriptor {
    pub id: String,
    pub name: String,
    pub short_description: MultiformatMessage,
    pub full_description: MultiformatMessage,
    pub default_configuration: DefaultConfiguration,
}

/// Default configuration for a rule
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DefaultConfiguration {
    pub level: String,
}

/// A text message
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MultiformatMessage {
    pub text: String,
}

/// An individual finding
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SarifResult {
    pub rule_id: String,
    pub rule_index: usize,
    pub level: String,
    pub message: MultiformatMessage,
    pub locations: Vec<Location>,
    pub properties: ResultProperties,
}

/// Location of a finding
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Location {
    pub physical_location: PhysicalLocation,
    pub logical_locations: Vec<LogicalLocation>,
}

/// Physical location (sysfs path)
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PhysicalLocation {
    pub artifact_location: ArtifactLocation,
}

/// URI-based artifact location
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactLocation {
    pub uri: String,
}

/// Logical location (PCI slot, device kind)
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogicalLocation {
    pub name: String,
    pub kind: String,
    pub fully_qualified_name: String,
}

/// Invocation metadata
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Invocation {
    pub execution_successful: bool,
    pub start_time_utc: String,
    pub end_time_utc: String,
    pub properties: InvocationProperties,
}

/// Custom invocation properties
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InvocationProperties {
    pub kernel_version: String,
    pub risk_level: String,
}

/// Custom result properties
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResultProperties {
    pub pci_slot: String,
    pub pci_id: String,
    pub remediation: String,
}

// ── Conversion Functions ───────────────────────────────────────────────

/// Convert a SystemReport to SARIF 2.1.0 JSON string
pub fn format_sarif(report: &SystemReport) -> Result<String> {
    let log = system_report_to_sarif(report);
    Ok(serde_json::to_string_pretty(&log)?)
}

/// Build the full SARIF log from a SystemReport
fn system_report_to_sarif(report: &SystemReport) -> SarifLog {
    let rules = build_rules();

    let results: Vec<SarifResult> = report
        .devices
        .iter()
        .flat_map(|device| {
            device
                .issues
                .iter()
                .map(move |issue| device_issue_to_result(device, issue))
        })
        .collect();

    SarifLog {
        schema: SARIF_SCHEMA.to_string(),
        version: SARIF_VERSION.to_string(),
        runs: vec![Run {
            tool: Tool {
                driver: ToolDriver {
                    name: TOOL_NAME.to_string(),
                    version: env!("CARGO_PKG_VERSION").to_string(),
                    semantic_version: env!("CARGO_PKG_VERSION").to_string(),
                    information_uri: TOOL_URI.to_string(),
                    rules,
                },
            },
            results,
            invocations: vec![Invocation {
                execution_successful: true,
                start_time_utc: report.timestamp.clone(),
                end_time_utc: report.timestamp.clone(),
                properties: InvocationProperties {
                    kernel_version: report.kernel_version.clone(),
                    risk_level: format!("{:?}", report.risk_level),
                },
            }],
        }],
    }
}

/// Build the ReportingDescriptor rules array for all 9 IssueType variants
fn build_rules() -> Vec<ReportingDescriptor> {
    vec![
        make_rule("HCT001", "ZombieDevice", "Device powered on with no driver", "PCI device is in D0 (full power) state with no kernel driver bound, consuming power and potentially causing bus errors.", "error"),
        make_rule("HCT002", "TaintedDriver", "Driver failed verification", "Kernel module loaded but failed signature verification, tainting the kernel and risking instability.", "error"),
        make_rule("HCT003", "PartialBinding", "Partial driver binding", "Audio codec on GPU chip bound to generic audio driver (e.g., snd_hda_intel on NVIDIA HDA), creating ghost audio endpoints.", "warning"),
        make_rule("HCT004", "SpuriousInterrupts", "Spurious interrupt storm", "Device generating high interrupt count with no driver handling them, risking IRQ storms and system hangs.", "error"),
        make_rule("HCT005", "AcpiError", "ACPI method failure", "ACPI BIOS method returned an error, indicating firmware bugs affecting device power management.", "warning"),
        make_rule("HCT006", "NoIommuIsolation", "Missing IOMMU isolation", "Device not assigned to an IOMMU group, lacking DMA isolation and vulnerable to bus-level attacks.", "warning"),
        make_rule("HCT007", "BlacklistedButActive", "Blacklisted driver still active", "Kernel driver is blacklisted via modprobe.d but the device remains powered and active.", "error"),
        make_rule("HCT008", "UnmanagedMemory", "Unmanaged BAR memory regions", "PCI BAR memory regions are mapped into the system address space with no driver managing access.", "error"),
        make_rule("HCT009", "PowerStateConflict", "Power state conflict", "Device power state does not match expected state for its driver binding status.", "warning"),
    ]
}

/// Helper to create a ReportingDescriptor
fn make_rule(id: &str, name: &str, short: &str, full: &str, level: &str) -> ReportingDescriptor {
    ReportingDescriptor {
        id: id.to_string(),
        name: name.to_string(),
        short_description: MultiformatMessage {
            text: short.to_string(),
        },
        full_description: MultiformatMessage {
            text: full.to_string(),
        },
        default_configuration: DefaultConfiguration {
            level: level.to_string(),
        },
    }
}

/// Map IssueType to SARIF rule ID
fn issue_type_to_rule_id(issue_type: &IssueType) -> &'static str {
    match issue_type {
        IssueType::ZombieDevice => "HCT001",
        IssueType::TaintedDriver => "HCT002",
        IssueType::PartialBinding => "HCT003",
        IssueType::SpuriousInterrupts => "HCT004",
        IssueType::AcpiError => "HCT005",
        IssueType::NoIommuIsolation => "HCT006",
        IssueType::BlacklistedButActive => "HCT007",
        IssueType::UnmanagedMemory => "HCT008",
        IssueType::PowerStateConflict => "HCT009",
    }
}

/// Map IssueType to rule index (position in the rules array)
fn issue_type_to_rule_index(issue_type: &IssueType) -> usize {
    match issue_type {
        IssueType::ZombieDevice => 0,
        IssueType::TaintedDriver => 1,
        IssueType::PartialBinding => 2,
        IssueType::SpuriousInterrupts => 3,
        IssueType::AcpiError => 4,
        IssueType::NoIommuIsolation => 5,
        IssueType::BlacklistedButActive => 6,
        IssueType::UnmanagedMemory => 7,
        IssueType::PowerStateConflict => 8,
    }
}

/// Map IssueSeverity to SARIF level
fn severity_to_level(severity: &IssueSeverity) -> &'static str {
    match severity {
        IssueSeverity::Critical | IssueSeverity::High => "error",
        IssueSeverity::Warning => "warning",
        IssueSeverity::Info => "note",
    }
}

/// Convert a DeviceIssue on a PciDevice into a SARIF Result
fn device_issue_to_result(device: &PciDevice, issue: &DeviceIssue) -> SarifResult {
    let rule_id = issue_type_to_rule_id(&issue.issue_type);
    let rule_index = issue_type_to_rule_index(&issue.issue_type);
    let level = severity_to_level(&issue.severity);

    SarifResult {
        rule_id: rule_id.to_string(),
        rule_index,
        level: level.to_string(),
        message: MultiformatMessage {
            text: issue.description.clone(),
        },
        locations: vec![Location {
            physical_location: PhysicalLocation {
                artifact_location: ArtifactLocation {
                    uri: format!("file:///sys/bus/pci/devices/{}", device.slot),
                },
            },
            logical_locations: vec![LogicalLocation {
                name: device.slot.clone(),
                kind: "device".to_string(),
                fully_qualified_name: format!("pci:0000:{}", device.slot),
            }],
        }],
        properties: ResultProperties {
            pci_slot: device.slot.clone(),
            pci_id: device.pci_id.clone(),
            remediation: issue.remediation.clone(),
        },
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::*;

    /// Helper: create a minimal SystemReport
    fn empty_report() -> SystemReport {
        SystemReport {
            timestamp: "2026-02-13T12:00:00Z".to_string(),
            kernel_version: "6.18.8".to_string(),
            devices: vec![],
            iommu: IommuStatus {
                enabled: true,
                iommu_type: Some("Intel VT-d".to_string()),
                group_count: 14,
                interrupt_remapping: true,
            },
            acpi_errors: vec![],
            risk_level: RiskLevel::Clean,
        }
    }

    /// Helper: create a device with one issue
    fn device_with_issue(
        slot: &str,
        pci_id: &str,
        issue_type: IssueType,
        severity: IssueSeverity,
    ) -> PciDevice {
        PciDevice {
            slot: slot.to_string(),
            pci_id: pci_id.to_string(),
            description: "Test device".to_string(),
            vendor: "Test".to_string(),
            class: "VGA compatible controller".to_string(),
            driver: None,
            kernel_modules: vec![],
            power_state: PowerState::D0,
            enabled: true,
            iommu_group: Some(1),
            memory_regions: vec![],
            issues: vec![DeviceIssue {
                severity,
                issue_type,
                description: "Test issue description".to_string(),
                remediation: "Test remediation".to_string(),
            }],
        }
    }

    #[test]
    fn test_sarif_schema_version() {
        let report = empty_report();
        let log = system_report_to_sarif(&report);
        assert_eq!(log.version, "2.1.0");
        assert!(log.schema.contains("sarif-schema-2.1.0"));
    }

    #[test]
    fn test_sarif_empty_report() {
        let report = empty_report();
        let json = format_sarif(&report).unwrap();
        let val: serde_json::Value = serde_json::from_str(&json).unwrap();
        let results = val["runs"][0]["results"].as_array().unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_severity_mapping() {
        assert_eq!(severity_to_level(&IssueSeverity::Critical), "error");
        assert_eq!(severity_to_level(&IssueSeverity::High), "error");
        assert_eq!(severity_to_level(&IssueSeverity::Warning), "warning");
        assert_eq!(severity_to_level(&IssueSeverity::Info), "note");
    }

    #[test]
    fn test_rule_id_mapping() {
        assert_eq!(issue_type_to_rule_id(&IssueType::ZombieDevice), "HCT001");
        assert_eq!(issue_type_to_rule_id(&IssueType::TaintedDriver), "HCT002");
        assert_eq!(issue_type_to_rule_id(&IssueType::PartialBinding), "HCT003");
        assert_eq!(
            issue_type_to_rule_id(&IssueType::SpuriousInterrupts),
            "HCT004"
        );
        assert_eq!(issue_type_to_rule_id(&IssueType::AcpiError), "HCT005");
        assert_eq!(
            issue_type_to_rule_id(&IssueType::NoIommuIsolation),
            "HCT006"
        );
        assert_eq!(
            issue_type_to_rule_id(&IssueType::BlacklistedButActive),
            "HCT007"
        );
        assert_eq!(
            issue_type_to_rule_id(&IssueType::UnmanagedMemory),
            "HCT008"
        );
        assert_eq!(
            issue_type_to_rule_id(&IssueType::PowerStateConflict),
            "HCT009"
        );
    }

    #[test]
    fn test_rule_index_consistency() {
        let rules = build_rules();
        // Verify each rule index matches its position in the rules array
        for (i, rule) in rules.iter().enumerate() {
            let expected_id = format!("HCT{:03}", i + 1);
            assert_eq!(rule.id, expected_id, "Rule at index {} has wrong ID", i);
        }
        assert_eq!(rules.len(), 9);
    }

    #[test]
    fn test_single_device_single_issue() {
        let mut report = empty_report();
        report.devices.push(device_with_issue(
            "01:00.0",
            "10de:13b0",
            IssueType::ZombieDevice,
            IssueSeverity::High,
        ));

        let log = system_report_to_sarif(&report);
        assert_eq!(log.runs[0].results.len(), 1);

        let result = &log.runs[0].results[0];
        assert_eq!(result.rule_id, "HCT001");
        assert_eq!(result.rule_index, 0);
        assert_eq!(result.level, "error");
        assert_eq!(result.properties.pci_slot, "01:00.0");
        assert_eq!(result.properties.pci_id, "10de:13b0");
    }

    #[test]
    fn test_multi_device_multi_issue() {
        let mut report = empty_report();

        let mut dev1 = device_with_issue(
            "01:00.0",
            "10de:13b0",
            IssueType::ZombieDevice,
            IssueSeverity::High,
        );
        dev1.issues.push(DeviceIssue {
            severity: IssueSeverity::Warning,
            issue_type: IssueType::NoIommuIsolation,
            description: "Not isolated".to_string(),
            remediation: "Enable IOMMU".to_string(),
        });
        report.devices.push(dev1);

        report.devices.push(device_with_issue(
            "01:00.1",
            "10de:0fbc",
            IssueType::PartialBinding,
            IssueSeverity::Warning,
        ));

        let log = system_report_to_sarif(&report);
        assert_eq!(log.runs[0].results.len(), 3);

        let rule_ids: Vec<&str> = log.runs[0]
            .results
            .iter()
            .map(|r| r.rule_id.as_str())
            .collect();
        assert!(rule_ids.contains(&"HCT001"));
        assert!(rule_ids.contains(&"HCT006"));
        assert!(rule_ids.contains(&"HCT003"));
    }

    #[test]
    fn test_location_uri_format() {
        let mut report = empty_report();
        report.devices.push(device_with_issue(
            "01:00.0",
            "10de:13b0",
            IssueType::ZombieDevice,
            IssueSeverity::High,
        ));

        let log = system_report_to_sarif(&report);
        let loc = &log.runs[0].results[0].locations[0];
        assert_eq!(
            loc.physical_location.artifact_location.uri,
            "file:///sys/bus/pci/devices/01:00.0"
        );
        assert_eq!(loc.logical_locations[0].name, "01:00.0");
        assert_eq!(loc.logical_locations[0].kind, "device");
        assert_eq!(
            loc.logical_locations[0].fully_qualified_name,
            "pci:0000:01:00.0"
        );
    }

    #[test]
    fn test_sarif_json_roundtrip() {
        let mut report = empty_report();
        report.devices.push(device_with_issue(
            "01:00.0",
            "10de:13b0",
            IssueType::ZombieDevice,
            IssueSeverity::Critical,
        ));

        let json = format_sarif(&report).unwrap();
        let val: serde_json::Value = serde_json::from_str(&json).unwrap();

        // Verify top-level structure
        assert!(val.get("$schema").is_some());
        assert_eq!(val["version"], "2.1.0");
        assert!(val["runs"].is_array());
        assert!(val["runs"][0]["tool"]["driver"]["rules"].is_array());
        assert!(val["runs"][0]["results"].is_array());
        assert!(val["runs"][0]["invocations"].is_array());

        // Verify invocation properties
        assert_eq!(
            val["runs"][0]["invocations"][0]["properties"]["kernelVersion"],
            "6.18.8"
        );
    }
}
