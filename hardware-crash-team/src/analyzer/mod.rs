// SPDX-License-Identifier: PMPL-1.0-or-later
//! Crash log analyzer
//!
//! Correlates system crash events with hardware state to identify
//! which devices are causing instability. Parses journalctl boot logs
//! for PCI errors, kernel taints, ACPI issues, and module failures.

use crate::types::*;
use anyhow::Result;
use std::collections::HashMap;
use std::process::Command;

/// Hardware error patterns to search for in kernel logs
const PCI_ERROR_PATTERNS: &[&str] = &[
    "pci",
    "AER",
    "PCIe Bus Error",
    "BAR",
    "DPC:",
    "ACS",
];

const ACPI_ERROR_PATTERNS: &[&str] = &[
    "ACPI Error",
    "ACPI BIOS Error",
    "ACPI Exception",
    "AE_AML",
    "AE_NOT_FOUND",
    "_SB._OSC",
];

const TAINT_PATTERNS: &[&str] = &[
    "module verification failed",
    "tainting kernel",
    "Tainted:",
    "loading out-of-tree module",
];

const CRASH_INDICATORS: &[&str] = &[
    "Kernel panic",
    "BUG:",
    "Oops:",
    "RIP:",
    "Call Trace:",
    "watchdog: BUG:",
    "Hardware Error",
    "Machine check events logged",
    "MCE:",
];

/// Analyze recent boots for hardware-related crashes
pub fn diagnose(boots: usize, device_filter: Option<&str>) -> Result<CrashDiagnosis> {
    let boot_list = list_boots(boots)?;

    if boot_list.is_empty() {
        return Ok(CrashDiagnosis {
            boots_analyzed: 0,
            crashes: Vec::new(),
            correlations: Vec::new(),
            confidence: 0.0,
            primary_suspect: None,
            recommendation: "No boot records found. Check journalctl access.".to_string(),
        });
    }

    let mut crashes = Vec::new();
    let mut device_events: HashMap<String, Vec<String>> = HashMap::new();
    let mut device_crash_count: HashMap<String, usize> = HashMap::new();

    for (i, boot_entry) in boot_list.iter().enumerate() {
        let boot_id = &boot_entry.boot_id;
        let log = read_boot_log(boot_id)?;

        // Check if this boot ended in a crash (short session or crash indicators)
        let has_crash_indicators = CRASH_INDICATORS.iter().any(|p| log.contains(p));
        let is_short_session = boot_entry.duration_secs < 120;
        let is_unclean = is_short_session || has_crash_indicators;

        if !is_unclean && i < boot_list.len() - 1 {
            // Skip clean boots (except current boot)
            continue;
        }

        let mut indicators = Vec::new();
        let mut hw_events = Vec::new();

        // Scan for hardware-related events
        for line in log.lines() {
            let line_lower = line.to_lowercase();

            // PCI errors
            for pattern in PCI_ERROR_PATTERNS {
                if line_lower.contains(&pattern.to_lowercase()) {
                    let device = extract_pci_device(line);
                    if let Some(ref dev) = device {
                        if let Some(filter) = device_filter {
                            if !dev.contains(filter) {
                                continue;
                            }
                        }
                        device_events.entry(dev.clone()).or_default().push(format!("PCI: {}", truncate(line, 120)));
                        if is_unclean {
                            *device_crash_count.entry(dev.clone()).or_default() += 1;
                        }
                    }
                    hw_events.push(format!("PCI event: {}", truncate(line, 100)));
                    break;
                }
            }

            // ACPI errors
            for pattern in ACPI_ERROR_PATTERNS {
                if line.contains(pattern) {
                    let device = extract_acpi_device(line);
                    if let Some(ref dev) = device {
                        device_events.entry(dev.clone()).or_default().push(format!("ACPI: {}", truncate(line, 120)));
                        if is_unclean {
                            *device_crash_count.entry(dev.clone()).or_default() += 1;
                        }
                    }
                    hw_events.push(format!("ACPI event: {}", truncate(line, 100)));
                    break;
                }
            }

            // Kernel taints
            for pattern in TAINT_PATTERNS {
                if line.contains(pattern) {
                    indicators.push(format!("Taint: {}", truncate(line, 100)));
                    // Try to extract module name
                    if let Some(module) = extract_module_name(line) {
                        hw_events.push(format!("Tainted module: {}", module));
                    }
                    break;
                }
            }

            // Crash indicators
            for pattern in CRASH_INDICATORS {
                if line.contains(pattern) {
                    indicators.push(truncate(line, 120).to_string());
                    break;
                }
            }
        }

        if is_unclean || !indicators.is_empty() || !hw_events.is_empty() {
            crashes.push(CrashEvent {
                boot_id: boot_id.clone(),
                timestamp: boot_entry.timestamp.clone(),
                session_duration: boot_entry.duration_secs,
                indicators,
                hardware_events: hw_events,
            });
        }
    }

    // Build correlations from device event counts
    let total_crashes = crashes.len().max(1);
    let mut correlations: Vec<HardwareCorrelation> = device_crash_count
        .iter()
        .map(|(device, &count)| {
            let events = device_events.get(device).map(|e| e.len()).unwrap_or(0);
            let event_desc = device_events
                .get(device)
                .and_then(|e| e.first())
                .cloned()
                .unwrap_or_else(|| "Hardware event".to_string());

            HardwareCorrelation {
                device: device.clone(),
                event: event_desc,
                crash_count: count,
                strength: (count as f64) / (total_crashes as f64),
            }
        })
        .collect();

    // Sort by correlation strength (strongest first)
    correlations.sort_by(|a, b| b.strength.partial_cmp(&a.strength).unwrap_or(std::cmp::Ordering::Equal));

    let primary_suspect = correlations.first().map(|c| c.device.clone());
    let confidence = correlations.first().map(|c| c.strength).unwrap_or(0.0);

    let recommendation = if let Some(ref suspect) = primary_suspect {
        if confidence > 0.7 {
            format!(
                "High confidence: device {} is likely causing crashes. Run `hardware-crash-team plan {}` to generate remediation.",
                suspect, suspect
            )
        } else if confidence > 0.3 {
            format!(
                "Moderate confidence: device {} correlates with crashes. Investigate with `hardware-crash-team scan` for details.",
                suspect
            )
        } else {
            "Low correlation found. Crashes may have multiple causes. Review full boot logs.".to_string()
        }
    } else if crashes.is_empty() {
        "No crashes detected in analyzed boots. System appears stable.".to_string()
    } else {
        "Crashes detected but no hardware correlation found. May be software issue.".to_string()
    };

    Ok(CrashDiagnosis {
        boots_analyzed: boot_list.len(),
        crashes,
        correlations,
        confidence,
        primary_suspect,
        recommendation,
    })
}

/// Print diagnosis results
pub fn print_diagnosis(diagnosis: &CrashDiagnosis) {
    println!("\nCrash Diagnosis");
    println!("===============");
    println!("Boots analyzed: {}", diagnosis.boots_analyzed);
    println!("Crashes/anomalies found: {}", diagnosis.crashes.len());

    if !diagnosis.crashes.is_empty() {
        println!("\nBoot History:");
        for crash in &diagnosis.crashes {
            let duration = if crash.session_duration < 60 {
                format!("{}s", crash.session_duration)
            } else {
                format!("{}m {}s", crash.session_duration / 60, crash.session_duration % 60)
            };

            let status = if crash.session_duration < 120 {
                "SHORT"
            } else if crash.indicators.iter().any(|i| i.contains("panic") || i.contains("Oops")) {
                "CRASH"
            } else {
                "UNCLEAN"
            };

            println!("  [{}] {} (duration: {}, {} indicators, {} hw events)",
                status, crash.timestamp, duration,
                crash.indicators.len(), crash.hardware_events.len());

            for indicator in crash.indicators.iter().take(3) {
                println!("    -> {}", indicator);
            }
        }
    }

    if let Some(ref suspect) = diagnosis.primary_suspect {
        println!("\nPrimary suspect: {}", suspect);
        println!("Confidence: {:.0}%", diagnosis.confidence * 100.0);
    }

    if !diagnosis.correlations.is_empty() {
        println!("\nHardware Correlations:");
        for corr in &diagnosis.correlations {
            println!("  {} — {} (strength: {:.0}%, in {} crash boots)",
                corr.device, corr.event, corr.strength * 100.0, corr.crash_count);
        }
    }

    println!("\nRecommendation: {}", diagnosis.recommendation);
}

// Internal helpers

struct BootEntry {
    boot_id: String,
    timestamp: String,
    duration_secs: u64,
}

/// List recent boots from journalctl
fn list_boots(max_boots: usize) -> Result<Vec<BootEntry>> {
    let output = Command::new("journalctl")
        .args(["--list-boots", "--no-pager", "-q"])
        .output();

    let output = match output {
        Ok(o) => o,
        Err(_) => return Ok(Vec::new()),
    };

    if !output.status.success() {
        return Ok(Vec::new());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut boots = Vec::new();

    for line in stdout.lines() {
        // Format: " -N BOOTID timestamp—timestamp"
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 {
            let boot_id = parts[1].to_string();

            // Parse timestamps to get duration
            let timestamp = parts[2..].join(" ");
            let duration = estimate_boot_duration(&timestamp);

            boots.push(BootEntry {
                boot_id,
                timestamp: timestamp.clone(),
                duration_secs: duration,
            });
        }
    }

    // Take only the most recent N boots
    let start = if boots.len() > max_boots {
        boots.len() - max_boots
    } else {
        0
    };

    Ok(boots[start..].to_vec())
}

/// Read kernel log for a specific boot
fn read_boot_log(boot_id: &str) -> Result<String> {
    let output = Command::new("journalctl")
        .args(["-b", boot_id, "-k", "--no-pager", "-q", "--no-hostname"])
        .output()?;

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Extract PCI device address from a log line (e.g., "0000:01:00.0")
fn extract_pci_device(line: &str) -> Option<String> {
    // Look for PCI address pattern: XXXX:XX:XX.X or XX:XX.X
    let bytes = line.as_bytes();
    let len = bytes.len();

    for i in 0..len.saturating_sub(6) {
        // Try XX:XX.X pattern
        if i + 7 <= len
            && bytes[i + 2] == b':'
            && bytes[i + 5] == b'.'
            && bytes[i].is_ascii_hexdigit()
            && bytes[i + 1].is_ascii_hexdigit()
            && bytes[i + 3].is_ascii_hexdigit()
            && bytes[i + 4].is_ascii_hexdigit()
            && bytes[i + 6].is_ascii_digit()
        {
            return Some(line[i..i + 7].to_string());
        }
    }
    None
}

/// Extract ACPI device path from a log line
fn extract_acpi_device(line: &str) -> Option<String> {
    // Look for ACPI paths like _SB.PCI0 or \_SB._OSC
    if let Some(pos) = line.find("_SB") {
        let end = line[pos..]
            .find(|c: char| c.is_whitespace() || c == ')' || c == ']')
            .unwrap_or(line.len() - pos);
        return Some(line[pos..pos + end].to_string());
    }
    None
}

/// Extract module name from taint/module log line
fn extract_module_name(line: &str) -> Option<String> {
    // "module nvidia failed" → "nvidia"
    if let Some(pos) = line.find("module ") {
        let rest = &line[pos + 7..];
        let end = rest.find(|c: char| c.is_whitespace()).unwrap_or(rest.len());
        let module = &rest[..end];
        if !module.is_empty() && module != "verification" {
            return Some(module.to_string());
        }
    }
    None
}

/// Estimate boot duration from journalctl timestamp range
fn estimate_boot_duration(timestamp_range: &str) -> u64 {
    // journalctl format: "2026-02-08 10:00:00 UTC—2026-02-08 10:00:45 UTC"
    if let Some(dash_pos) = timestamp_range.find('—') {
        // Very rough: parse hours/minutes from both sides
        let start = &timestamp_range[..dash_pos];
        let end = &timestamp_range[dash_pos + 3..]; // skip '—' (3 bytes UTF-8)
        if let (Some(s), Some(e)) = (parse_epoch_rough(start), parse_epoch_rough(end)) {
            if e > s {
                return e - s;
            }
        }
    }
    3600 // Default to 1 hour if we can't parse
}

/// Rough epoch parsing (just hours and minutes for duration estimation)
fn parse_epoch_rough(ts: &str) -> Option<u64> {
    // Find HH:MM:SS pattern
    let parts: Vec<&str> = ts.split_whitespace().collect();
    for part in parts {
        let time_parts: Vec<&str> = part.split(':').collect();
        if time_parts.len() == 3 {
            if let (Ok(h), Ok(m), Ok(s)) = (
                time_parts[0].parse::<u64>(),
                time_parts[1].parse::<u64>(),
                time_parts[2].parse::<u64>(),
            ) {
                return Some(h * 3600 + m * 60 + s);
            }
        }
    }
    None
}

fn truncate(s: &str, max_len: usize) -> &str {
    if s.len() <= max_len {
        s
    } else {
        &s[..max_len]
    }
}

impl Clone for BootEntry {
    fn clone(&self) -> Self {
        BootEntry {
            boot_id: self.boot_id.clone(),
            timestamp: self.timestamp.clone(),
            duration_secs: self.duration_secs,
        }
    }
}
