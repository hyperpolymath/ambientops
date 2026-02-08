# Hardware Crash Team - Project Instructions

## Overview

Hardware diagnostic and remediation tool for zombie PCI devices, driver conflicts, and hardware-induced system crashes. Part of the AmbientOps ecosystem (hospital model - Operating Room → Crash Team).

## Architecture

```
src/
├── main.rs          # CLI entry point (clap), 6 subcommands
├── types.rs         # All data types (SystemReport, PciDevice, DeviceIssue, RemediationPlan, etc.)
├── scanner/mod.rs   # PCI scanner via /sys/bus/pci/devices/ sysfs
├── analyzer/mod.rs  # Crash log analyzer (STUB - v0.2.0 milestone)
└── remediation/mod.rs # Plan/Apply/Undo workflow with receipt generation
```

## Build & Test

```bash
cargo build --release
cargo test
# Run scan (needs Linux with sysfs):
cargo run -- scan
cargo run -- scan --format json --output report.json
cargo run -- plan 01:00.0 --strategy dual
```

## Key Design Decisions

- **sysfs-only scanning**: No lspci dependency, reads /sys/bus/pci/devices/ directly
- **DRY RUN by default**: `apply` prints commands without executing; `--yes` needed for real execution
- **Receipt-based undo**: Every `apply` generates a receipt JSON for rollback
- **Fedora Atomic first**: Uses `rpm-ostree kargs` for kernel parameter changes (grubby/systemd-boot planned)
- **Human oversight mandatory**: All destructive operations require explicit confirmation

## Subcommands

| Command | Status | Purpose |
|---------|--------|---------|
| `scan` | Working | Enumerate PCI devices, detect zombies, partial bindings |
| `diagnose` | Stub | Parse journalctl for crash-hardware correlations |
| `plan` | Working | Generate remediation plan (dual null-driver strategy) |
| `apply` | Working (dry-run) | Execute plan with confirmation + receipt |
| `undo` | Working (dry-run) | Reverse plan using receipt |
| `status` | Working | Quick system overview |

## Issue Types Detected

- ZombieDevice: D0 power + no driver
- PartialBinding: snd_hda_intel on NVIDIA audio codec
- TaintedDriver: Failed module verification
- SpuriousInterrupts, AcpiError, NoIommuIsolation, UnmanagedMemory

## Remediation Strategies

- `dual` (default): pci-stub + vfio-pci (belt and braces)
- `pci-stub`: Kernel builtin null driver
- `vfio-pci`: IOMMU-backed isolation
- `power-off`, `disable`, `unbind`: Planned

## Current Roadmap Priority

1. **v0.1.0** (current): Complete scanner - add BAR enumeration, lspci enrichment, interrupt checking
2. **v0.2.0**: Crash analyzer - journalctl parsing, boot history, crash-hardware correlation
3. **v0.3.0**: Remediation engine - rpm-ostree/grubby/systemd-boot, multi-device plans
4. **v0.4.0**: ATS2 TUI for interactive diagnostics
5. **v0.5.0**: Integration (verisimdb, hypatia, MCP server, SARIF output)

## Origin

Born from real NVIDIA Quadro M2000M incident (43+ reboots in 3 days). GPU was in zombie D0 state with no driver, crashing via PCI bus errors, kernel taints, partial audio binding, and ACPI BIOS bugs.

## Code Style

- SPDX headers on all files: `PMPL-1.0-or-later`
- Author: Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
- Use anyhow::Result for error handling
- Serde derive on all public types for JSON serialization
- Human-readable error messages with remediation suggestions
