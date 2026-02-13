# Hardware Crash Team - Project Instructions

## Overview

Hardware diagnostic and remediation tool for zombie PCI devices, driver conflicts, and hardware-induced system crashes. Part of the AmbientOps ecosystem (hospital model - Operating Room → Crash Team).

## Architecture

```
src/
├── main.rs          # CLI entry point (clap), 7 subcommands
├── types.rs         # All data types (SystemReport, PciDevice, DeviceIssue, RemediationPlan, MultiDevicePlan, etc.)
├── scanner/mod.rs   # PCI scanner via sysfs + BAR enumeration + lspci enrichment + interrupt checking
├── analyzer/mod.rs  # Crash log analyzer (~429 LOC, journalctl parsing)
├── remediation/mod.rs # Plan/Apply/Undo workflow with 6 strategies + multi-device support
└── tui/             # ATS2 TUI (ratatui, behind `tui` feature)
    ├── mod.rs       # Screen enum, feature gate
    ├── app.rs       # App state, event loop
    └── ui.rs        # Rendering for 5 screens
```

## Build & Test

```bash
cargo build --release
cargo test
# With TUI:
cargo build --release --features tui
# Run scan (needs Linux with sysfs):
cargo run -- scan
cargo run -- scan --format json --output report.json
cargo run -- plan 01:00.0 --strategy dual
cargo run -- plan 01:00.0 01:00.1 --strategy vfio-pci   # Multi-device
cargo run -- tui   # Interactive TUI (requires --features tui)
```

## Key Design Decisions

- **sysfs-only scanning**: Reads /sys/bus/pci/devices/ directly, lspci enrichment optional
- **BAR enumeration**: Parses /sys/bus/pci/devices/{slot}/resource for memory regions
- **lspci enrichment**: Calls `lspci -s {slot} -q` for human-readable descriptions
- **Interrupt checking**: Parses /proc/interrupts for spurious interrupt detection
- **DRY RUN by default**: `apply` prints commands without executing; `--yes` needed for real execution
- **Receipt-based undo**: Every `apply` generates a receipt JSON for rollback
- **Fedora Atomic first**: Uses `rpm-ostree kargs` for kernel parameter changes
- **Human oversight mandatory**: All destructive operations require explicit confirmation

## Subcommands

| Command | Status | Purpose |
|---------|--------|---------|
| `scan` | Working | Enumerate PCI devices, BARs, detect zombies, partial bindings, unmanaged memory |
| `diagnose` | Working | Parse journalctl for crash-hardware correlations |
| `plan` | Working | Generate remediation plan (all 6 strategies, multi-device) |
| `apply` | Working (dry-run) | Execute plan with confirmation + receipt |
| `undo` | Working (dry-run) | Reverse plan using receipt |
| `status` | Working | Quick system overview |
| `tui` | Working | Interactive TUI with 5 screens (requires `--features tui`) |

## Issue Types Detected

- ZombieDevice: D0 power + no driver
- PartialBinding: snd_hda_intel on NVIDIA audio codec
- TaintedDriver: Failed module verification
- SpuriousInterrupts: High interrupt count with no driver
- AcpiError: ACPI method failures
- NoIommuIsolation: Device not in IOMMU group
- UnmanagedMemory: BARs mapped with no managing driver
- BlacklistedButActive: Driver blacklisted but device still active
- PowerStateConflict: Power state mismatch

## Remediation Strategies (All 6 Working)

| Strategy | Reboot | Risk | Description |
|----------|--------|------|-------------|
| `pci-stub` | Yes | Low | Kernel builtin null driver via rpm-ostree kargs |
| `vfio-pci` | Yes | Low | IOMMU-backed isolation via rpm-ostree kargs |
| `dual` (default) | Yes | Low | Both pci-stub + vfio-pci (belt and braces) |
| `power-off` | No | Medium | ACPI power off + sysfs remove |
| `disable` | No | Low | Write 0 to sysfs enable |
| `unbind` | No | Low | Unbind driver from device |

## Multi-Device Support

`plan` accepts multiple device arguments. For kernel-arg strategies (pci-stub, vfio-pci, dual), device IDs are combined into a single `rpm-ostree kargs` command. For sysfs strategies, steps are generated per-device.

## TUI Screens (--features tui)

1. **Device List** — Table with slot, PCI ID, driver, power, issues, risk (color-coded)
2. **Device Detail** — Full device info + issues + BAR regions
3. **Plan Builder** — Select strategy, preview details
4. **Diagnosis** — Summary + per-device issue breakdown
5. **Status Dashboard** — System overview, ACPI errors, device class breakdown

Keys: `q`/`Esc`:back/quit, `Tab`:screens, `↑↓`:navigate, `Enter`:select, `p`:plan, `d`:diagnose, `r`:refresh, `?`:help

## Origin

Born from real NVIDIA Quadro M2000M incident (43+ reboots in 3 days). GPU was in zombie D0 state with no driver, crashing via PCI bus errors, kernel taints, partial audio binding, and ACPI BIOS bugs.

## Code Style

- SPDX headers on all files: `PMPL-1.0-or-later`
- Author: Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
- Use anyhow::Result for error handling
- Serde derive on all public types for JSON serialization
- Human-readable error messages with remediation suggestions
