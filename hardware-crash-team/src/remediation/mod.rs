// SPDX-License-Identifier: PMPL-1.0-or-later
//! Remediation engine
//!
//! Generates, applies, and undoes remediation plans for hardware issues.
//! All destructive operations require explicit human confirmation.

use crate::types::*;
use anyhow::Result;
use std::path::Path;

/// Create a remediation plan for a device
pub fn create_plan(device: &str, strategy: Option<&str>) -> Result<RemediationPlan> {
    let strategy = match strategy {
        Some("pci-stub") => RemediationStrategy::PciStub,
        Some("vfio-pci") => RemediationStrategy::VfioPci,
        Some("dual") | Some("both") => RemediationStrategy::DualNullDriver,
        Some("power-off") => RemediationStrategy::AcpiPowerOff,
        Some("disable") => RemediationStrategy::SysfsDisable,
        Some("unbind") => RemediationStrategy::DriverUnbind,
        Some(other) => anyhow::bail!("Unknown strategy: {}. Use: pci-stub, vfio-pci, dual, power-off, disable, unbind", other),
        None => RemediationStrategy::DualNullDriver, // Default: belt and braces
    };

    let plan = match strategy {
        RemediationStrategy::DualNullDriver => {
            // Read PCI ID from sysfs
            let pci_id = read_device_pci_id(device)?;
            let (vendor, dev_id) = pci_id.split_once(':')
                .unwrap_or(("0000", "0000"));

            RemediationPlan {
                id: format!("plan-{}-{}", device.replace(':', "-"), chrono::Utc::now().timestamp()),
                device: device.to_string(),
                strategy: RemediationStrategy::DualNullDriver,
                steps: vec![
                    RemediationStep {
                        description: format!("Claim device {} with pci-stub and vfio-pci null drivers", device),
                        command: format!(
                            "rpm-ostree kargs --append=pci-stub.ids={}:{},{}:{} --append=vfio-pci.ids={}:{},{}:{} --append=rd.driver.pre=vfio-pci",
                            vendor, dev_id, vendor, dev_id,
                            vendor, dev_id, vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: format!("Remove pci-stub and vfio-pci claims for device {}", device),
                        command: format!(
                            "rpm-ostree kargs --delete=pci-stub.ids={}:{},{}:{} --delete=vfio-pci.ids={}:{},{}:{} --delete=rd.driver.pre=vfio-pci",
                            vendor, dev_id, vendor, dev_id,
                            vendor, dev_id, vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                requires_reboot: true,
                risk: RiskLevel::Low,
            }
        }

        _ => {
            // TODO: Implement other strategies
            anyhow::bail!("Strategy {:?} not yet implemented", strategy)
        }
    };

    Ok(plan)
}

/// Print a remediation plan for human review
pub fn print_plan(plan: &RemediationPlan) {
    println!("\nRemediation Plan: {}", plan.id);
    println!("==================");
    println!("Target device: {}", plan.device);
    println!("Strategy: {:?}", plan.strategy);
    println!("Risk: {:?}", plan.risk);
    println!("Requires reboot: {}", plan.requires_reboot);

    println!("\nSteps:");
    for (i, step) in plan.steps.iter().enumerate() {
        println!("  {}. {}", i + 1, step.description);
        println!("     Command: {}{}", if step.needs_sudo { "sudo " } else { "" }, step.command);
        if step.needs_reboot {
            println!("     (requires reboot to take effect)");
        }
    }

    println!("\nUndo steps (if needed):");
    for (i, step) in plan.undo_steps.iter().enumerate() {
        println!("  {}. {}", i + 1, step.description);
        println!("     Command: {}{}", if step.needs_sudo { "sudo " } else { "" }, step.command);
    }

    // Save plan to file
    let plan_file = format!("{}.json", plan.id);
    if let Ok(json) = serde_json::to_string_pretty(plan) {
        if std::fs::write(&plan_file, &json).is_ok() {
            println!("\nPlan saved to: {}", plan_file);
            println!("Apply with: hardware-crash-team apply {}", plan_file);
        }
    }
}

/// Apply a remediation plan
pub fn apply_plan(plan_path: &Path) -> Result<()> {
    let content = std::fs::read_to_string(plan_path)?;
    let plan: RemediationPlan = serde_json::from_str(&content)?;

    println!("Applying plan: {}", plan.id);

    for step in &plan.steps {
        println!("  Executing: {}", step.description);
        if step.needs_sudo {
            println!("    (requires sudo) $ sudo {}", step.command);
            // In real implementation: std::process::Command::new("sudo")...
            println!("    [DRY RUN - would execute above command]");
        }
    }

    // Save receipt
    let receipt = RemediationReceipt {
        plan,
        applied_at: chrono::Utc::now().to_rfc3339(),
        reboot_pending: true,
        pre_state: String::new(),
    };

    let receipt_file = format!("receipt-{}.json", receipt.applied_at.replace(':', "-"));
    let json = serde_json::to_string_pretty(&receipt)?;
    std::fs::write(&receipt_file, &json)?;
    println!("\nReceipt saved to: {}", receipt_file);

    Ok(())
}

/// Undo a previously applied remediation
pub fn undo(receipt_path: &Path) -> Result<()> {
    let content = std::fs::read_to_string(receipt_path)?;
    let receipt: RemediationReceipt = serde_json::from_str(&content)?;

    println!("Undoing plan: {}", receipt.plan.id);

    for step in &receipt.plan.undo_steps {
        println!("  Executing: {}", step.description);
        if step.needs_sudo {
            println!("    (requires sudo) $ sudo {}", step.command);
            println!("    [DRY RUN - would execute above command]");
        }
    }

    Ok(())
}

/// Read a device's PCI ID from sysfs
fn read_device_pci_id(slot: &str) -> Result<String> {
    let base = format!("/sys/bus/pci/devices/{}", slot);
    let vendor = std::fs::read_to_string(format!("{}/vendor", base))
        .unwrap_or_default()
        .trim()
        .trim_start_matches("0x")
        .to_string();
    let device = std::fs::read_to_string(format!("{}/device", base))
        .unwrap_or_default()
        .trim()
        .trim_start_matches("0x")
        .to_string();

    if vendor.is_empty() || device.is_empty() {
        anyhow::bail!("Cannot read PCI ID for device {}. Check the slot address.", slot);
    }

    Ok(format!("{}:{}", vendor, device))
}
