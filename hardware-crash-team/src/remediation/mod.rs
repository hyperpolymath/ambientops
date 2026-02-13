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
    let strategy = parse_strategy(strategy)?;
    let pci_id = read_device_pci_id(device)?;
    let (vendor, dev_id) = pci_id.split_once(':').unwrap_or(("0000", "0000"));
    let plan_id = format!("plan-{}-{}", device.replace(':', "-"), chrono::Utc::now().timestamp());

    let plan = match strategy {
        RemediationStrategy::DualNullDriver => {
            RemediationPlan {
                id: plan_id,
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

        RemediationStrategy::PciStub => {
            RemediationPlan {
                id: plan_id,
                device: device.to_string(),
                strategy: RemediationStrategy::PciStub,
                steps: vec![
                    RemediationStep {
                        description: format!("Claim device {} with pci-stub kernel null driver", device),
                        command: format!(
                            "rpm-ostree kargs --append=pci-stub.ids={}:{}",
                            vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: format!("Remove pci-stub claim for device {}", device),
                        command: format!(
                            "rpm-ostree kargs --delete=pci-stub.ids={}:{}",
                            vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                requires_reboot: true,
                risk: RiskLevel::Low,
            }
        }

        RemediationStrategy::VfioPci => {
            RemediationPlan {
                id: plan_id,
                device: device.to_string(),
                strategy: RemediationStrategy::VfioPci,
                steps: vec![
                    RemediationStep {
                        description: format!("Claim device {} with vfio-pci (IOMMU-backed isolation)", device),
                        command: format!(
                            "rpm-ostree kargs --append=vfio-pci.ids={}:{} --append=rd.driver.pre=vfio-pci",
                            vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: format!("Remove vfio-pci claim for device {}", device),
                        command: format!(
                            "rpm-ostree kargs --delete=vfio-pci.ids={}:{} --delete=rd.driver.pre=vfio-pci",
                            vendor, dev_id
                        ),
                        needs_sudo: true,
                        needs_reboot: true,
                    },
                ],
                requires_reboot: true,
                risk: RiskLevel::Low,
            }
        }

        RemediationStrategy::AcpiPowerOff => {
            RemediationPlan {
                id: plan_id,
                device: device.to_string(),
                strategy: RemediationStrategy::AcpiPowerOff,
                steps: vec![
                    RemediationStep {
                        description: format!("Set device {} power control to auto", device),
                        command: format!(
                            "echo auto > /sys/bus/pci/devices/{}/power/control",
                            device
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                    RemediationStep {
                        description: format!("Remove device {} from PCI bus", device),
                        command: format!(
                            "echo 1 > /sys/bus/pci/devices/{}/remove",
                            device
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: "Rescan PCI bus to re-discover removed device".to_string(),
                        command: "echo 1 > /sys/bus/pci/rescan".to_string(),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                requires_reboot: false,
                risk: RiskLevel::Medium,
            }
        }

        RemediationStrategy::SysfsDisable => {
            RemediationPlan {
                id: plan_id,
                device: device.to_string(),
                strategy: RemediationStrategy::SysfsDisable,
                steps: vec![
                    RemediationStep {
                        description: format!("Disable device {} via sysfs", device),
                        command: format!(
                            "echo 0 > /sys/bus/pci/devices/{}/enable",
                            device
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: format!("Re-enable device {} via sysfs", device),
                        command: format!(
                            "echo 1 > /sys/bus/pci/devices/{}/enable",
                            device
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                requires_reboot: false,
                risk: RiskLevel::Low,
            }
        }

        RemediationStrategy::DriverUnbind => {
            // Read current driver to know where to unbind from
            let driver_path = format!("/sys/bus/pci/devices/{}/driver", device);
            let driver_name = std::fs::read_link(&driver_path)
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
                .unwrap_or_else(|| "unknown".to_string());

            RemediationPlan {
                id: plan_id,
                device: device.to_string(),
                strategy: RemediationStrategy::DriverUnbind,
                steps: vec![
                    RemediationStep {
                        description: format!("Unbind driver {} from device {}", driver_name, device),
                        command: format!(
                            "echo {} > /sys/bus/pci/devices/{}/driver/unbind",
                            device, device
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                undo_steps: vec![
                    RemediationStep {
                        description: format!("Rebind device {} to driver {}", device, driver_name),
                        command: format!(
                            "echo {} > /sys/bus/pci/drivers/{}/bind",
                            device, driver_name
                        ),
                        needs_sudo: true,
                        needs_reboot: false,
                    },
                ],
                requires_reboot: false,
                risk: RiskLevel::Low,
            }
        }
    };

    Ok(plan)
}

/// Create a multi-device remediation plan
pub fn create_multi_plan(devices: &[String], strategy: Option<&str>) -> Result<MultiDevicePlan> {
    let strategy = parse_strategy(strategy)?;
    let plan_id = format!("multi-plan-{}", chrono::Utc::now().timestamp());

    // Collect PCI IDs for all devices
    let mut device_ids: Vec<(String, String, String)> = Vec::new(); // (slot, vendor, device)
    for dev in devices {
        let pci_id = read_device_pci_id(dev)?;
        let (vendor, dev_id) = pci_id.split_once(':').unwrap_or(("0000", "0000"));
        device_ids.push((dev.clone(), vendor.to_string(), dev_id.to_string()));
    }

    // For kernel arg strategies, combine into single command
    let plans = match strategy {
        RemediationStrategy::PciStub | RemediationStrategy::VfioPci | RemediationStrategy::DualNullDriver => {
            // Combined kernel args for all devices
            let combined_plan = create_combined_kargs_plan(
                &plan_id, &device_ids, &strategy,
            );
            vec![combined_plan]
        }

        // Per-device strategies
        _ => {
            let mut plans = Vec::new();
            for dev in devices {
                plans.push(create_plan(dev, strategy_name(&strategy))?);
            }
            plans
        }
    };

    Ok(MultiDevicePlan {
        id: plan_id,
        devices: devices.to_vec(),
        plans,
        requires_reboot: strategy.requires_reboot(),
        risk: strategy.risk_level(),
    })
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

/// Print a multi-device remediation plan
pub fn print_multi_plan(multi: &MultiDevicePlan) {
    println!("\nMulti-Device Remediation Plan: {}", multi.id);
    println!("================================");
    println!("Devices: {}", multi.devices.join(", "));
    println!("Risk: {:?}", multi.risk);
    println!("Requires reboot: {}", multi.requires_reboot);
    println!("Sub-plans: {}", multi.plans.len());

    for plan in &multi.plans {
        print_plan(plan);
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

// Helper functions

fn parse_strategy(strategy: Option<&str>) -> Result<RemediationStrategy> {
    match strategy {
        Some("pci-stub") => Ok(RemediationStrategy::PciStub),
        Some("vfio-pci") => Ok(RemediationStrategy::VfioPci),
        Some("dual") | Some("both") => Ok(RemediationStrategy::DualNullDriver),
        Some("power-off") => Ok(RemediationStrategy::AcpiPowerOff),
        Some("disable") => Ok(RemediationStrategy::SysfsDisable),
        Some("unbind") => Ok(RemediationStrategy::DriverUnbind),
        Some(other) => anyhow::bail!("Unknown strategy: {}. Use: pci-stub, vfio-pci, dual, power-off, disable, unbind", other),
        None => Ok(RemediationStrategy::DualNullDriver),
    }
}

fn strategy_name(strategy: &RemediationStrategy) -> Option<&str> {
    match strategy {
        RemediationStrategy::PciStub => Some("pci-stub"),
        RemediationStrategy::VfioPci => Some("vfio-pci"),
        RemediationStrategy::DualNullDriver => Some("dual"),
        RemediationStrategy::AcpiPowerOff => Some("power-off"),
        RemediationStrategy::SysfsDisable => Some("disable"),
        RemediationStrategy::DriverUnbind => Some("unbind"),
    }
}

fn create_combined_kargs_plan(
    plan_id: &str,
    device_ids: &[(String, String, String)],
    strategy: &RemediationStrategy,
) -> RemediationPlan {
    let all_slots = device_ids.iter().map(|(s, _, _)| s.as_str()).collect::<Vec<_>>().join(", ");

    let mut apply_args = Vec::new();
    let mut undo_args = Vec::new();

    match strategy {
        RemediationStrategy::PciStub => {
            let ids: Vec<String> = device_ids.iter().map(|(_, v, d)| format!("{}:{}", v, d)).collect();
            let combined = ids.join(",");
            apply_args.push(format!("--append=pci-stub.ids={}", combined));
            undo_args.push(format!("--delete=pci-stub.ids={}", combined));
        }
        RemediationStrategy::VfioPci => {
            let ids: Vec<String> = device_ids.iter().map(|(_, v, d)| format!("{}:{}", v, d)).collect();
            let combined = ids.join(",");
            apply_args.push(format!("--append=vfio-pci.ids={}", combined));
            apply_args.push("--append=rd.driver.pre=vfio-pci".to_string());
            undo_args.push(format!("--delete=vfio-pci.ids={}", combined));
            undo_args.push("--delete=rd.driver.pre=vfio-pci".to_string());
        }
        RemediationStrategy::DualNullDriver => {
            let ids: Vec<String> = device_ids.iter().map(|(_, v, d)| format!("{}:{}", v, d)).collect();
            let combined = ids.join(",");
            apply_args.push(format!("--append=pci-stub.ids={}", combined));
            apply_args.push(format!("--append=vfio-pci.ids={}", combined));
            apply_args.push("--append=rd.driver.pre=vfio-pci".to_string());
            undo_args.push(format!("--delete=pci-stub.ids={}", combined));
            undo_args.push(format!("--delete=vfio-pci.ids={}", combined));
            undo_args.push("--delete=rd.driver.pre=vfio-pci".to_string());
        }
        _ => unreachable!("Only kernel arg strategies should use combined plan"),
    }

    RemediationPlan {
        id: format!("{}-combined", plan_id),
        device: all_slots.clone(),
        strategy: strategy.clone(),
        steps: vec![
            RemediationStep {
                description: format!("Claim devices [{}] via kernel args", all_slots),
                command: format!("rpm-ostree kargs {}", apply_args.join(" ")),
                needs_sudo: true,
                needs_reboot: true,
            },
        ],
        undo_steps: vec![
            RemediationStep {
                description: format!("Remove kernel arg claims for devices [{}]", all_slots),
                command: format!("rpm-ostree kargs {}", undo_args.join(" ")),
                needs_sudo: true,
                needs_reboot: true,
            },
        ],
        requires_reboot: true,
        risk: RiskLevel::Low,
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_strategy_all_valid() {
        assert!(matches!(parse_strategy(Some("pci-stub")).unwrap(), RemediationStrategy::PciStub));
        assert!(matches!(parse_strategy(Some("vfio-pci")).unwrap(), RemediationStrategy::VfioPci));
        assert!(matches!(parse_strategy(Some("dual")).unwrap(), RemediationStrategy::DualNullDriver));
        assert!(matches!(parse_strategy(Some("both")).unwrap(), RemediationStrategy::DualNullDriver));
        assert!(matches!(parse_strategy(Some("power-off")).unwrap(), RemediationStrategy::AcpiPowerOff));
        assert!(matches!(parse_strategy(Some("disable")).unwrap(), RemediationStrategy::SysfsDisable));
        assert!(matches!(parse_strategy(Some("unbind")).unwrap(), RemediationStrategy::DriverUnbind));
        assert!(matches!(parse_strategy(None).unwrap(), RemediationStrategy::DualNullDriver));
    }

    #[test]
    fn test_parse_strategy_invalid() {
        assert!(parse_strategy(Some("bogus")).is_err());
    }

    #[test]
    fn test_combined_kargs_pci_stub() {
        let devices = vec![
            ("01:00.0".to_string(), "10de".to_string(), "13b0".to_string()),
            ("01:00.1".to_string(), "10de".to_string(), "0fbc".to_string()),
        ];
        let plan = create_combined_kargs_plan("test", &devices, &RemediationStrategy::PciStub);
        assert!(plan.steps[0].command.contains("pci-stub.ids=10de:13b0,10de:0fbc"));
        assert!(plan.steps[0].needs_reboot);
    }

    #[test]
    fn test_combined_kargs_vfio() {
        let devices = vec![
            ("01:00.0".to_string(), "10de".to_string(), "13b0".to_string()),
        ];
        let plan = create_combined_kargs_plan("test", &devices, &RemediationStrategy::VfioPci);
        assert!(plan.steps[0].command.contains("vfio-pci.ids=10de:13b0"));
        assert!(plan.steps[0].command.contains("rd.driver.pre=vfio-pci"));
    }

    #[test]
    fn test_combined_kargs_dual() {
        let devices = vec![
            ("01:00.0".to_string(), "10de".to_string(), "13b0".to_string()),
            ("01:00.1".to_string(), "10de".to_string(), "0fbc".to_string()),
        ];
        let plan = create_combined_kargs_plan("test", &devices, &RemediationStrategy::DualNullDriver);
        assert!(plan.steps[0].command.contains("pci-stub.ids=10de:13b0,10de:0fbc"));
        assert!(plan.steps[0].command.contains("vfio-pci.ids=10de:13b0,10de:0fbc"));
        assert!(plan.steps[0].command.contains("rd.driver.pre=vfio-pci"));
    }

    #[test]
    fn test_undo_is_inverse_of_apply_pci_stub() {
        let devices = vec![
            ("01:00.0".to_string(), "10de".to_string(), "13b0".to_string()),
        ];
        let plan = create_combined_kargs_plan("test", &devices, &RemediationStrategy::PciStub);
        // Apply has --append, undo has --delete, same IDs
        assert!(plan.steps[0].command.contains("--append=pci-stub.ids=10de:13b0"));
        assert!(plan.undo_steps[0].command.contains("--delete=pci-stub.ids=10de:13b0"));
    }

    #[test]
    fn test_undo_is_inverse_of_apply_dual() {
        let devices = vec![
            ("01:00.0".to_string(), "10de".to_string(), "13b0".to_string()),
        ];
        let plan = create_combined_kargs_plan("test", &devices, &RemediationStrategy::DualNullDriver);
        assert!(plan.steps[0].command.contains("--append="));
        assert!(plan.undo_steps[0].command.contains("--delete="));
        // Both should reference the same IDs
        assert!(plan.undo_steps[0].command.contains("pci-stub.ids=10de:13b0"));
        assert!(plan.undo_steps[0].command.contains("vfio-pci.ids=10de:13b0"));
    }

    #[test]
    fn test_acpi_power_off_no_reboot() {
        // AcpiPowerOff shouldn't need a reboot — verify via strategy trait
        assert!(!RemediationStrategy::AcpiPowerOff.requires_reboot());
        assert!(matches!(RemediationStrategy::AcpiPowerOff.risk_level(), RiskLevel::Medium));
    }

    #[test]
    fn test_sysfs_disable_no_reboot() {
        assert!(!RemediationStrategy::SysfsDisable.requires_reboot());
        assert!(matches!(RemediationStrategy::SysfsDisable.risk_level(), RiskLevel::Low));
    }

    #[test]
    fn test_driver_unbind_no_reboot() {
        assert!(!RemediationStrategy::DriverUnbind.requires_reboot());
        assert!(matches!(RemediationStrategy::DriverUnbind.risk_level(), RiskLevel::Low));
    }

    #[test]
    fn test_strategy_name_roundtrip() {
        let strategies = vec![
            RemediationStrategy::PciStub,
            RemediationStrategy::VfioPci,
            RemediationStrategy::DualNullDriver,
            RemediationStrategy::AcpiPowerOff,
            RemediationStrategy::SysfsDisable,
            RemediationStrategy::DriverUnbind,
        ];
        for s in strategies {
            let name = strategy_name(&s).unwrap();
            let parsed = parse_strategy(Some(name)).unwrap();
            // Verify we can roundtrip
            assert_eq!(strategy_name(&parsed), strategy_name(&s));
        }
    }
}
