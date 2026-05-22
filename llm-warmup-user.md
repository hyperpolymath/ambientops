# AmbientOps LLM Warmup (User Context)

## What This Is

AmbientOps is a hospital-model operations framework (hybrid monorepo).
Components are organized by hospital department. License: MPL-2.0.
Author: Jonathan D.A. Jewell.

## Architecture (30-second version)

Hospital metaphor for system operations:
- **Clinician** (Rust) -- AI-assisted sysadmin with feature gates
- **Emergency Room** (zig) -- Panic-safe intake, evidence envelopes
- **Hardware Crash Team** (Rust) -- Hardware diagnostics (PCI, lspci, SARIF)
- **Observatory** (Elixir) -- Metrics, system weather, monitoring
- **Contracts** (JSON + Deno) -- 8 JSON schemas for data backbone
- **Records/Referrals** (Elixir) -- Multi-platform bug reporting

Data flow: ER intake -> Evidence Envelope -> Procedure Plan -> Receipt -> System Weather

## Key Commands

```bash
just build-all        # Build everything (Rust + Elixir)
just test-all         # Run all tests
just scan             # Hardware scan (hardware-crash-team)
just demo             # End-to-end demo
just security         # Security audit (gitleaks + trivy)
just doctor           # Check toolchain
```

## Prerequisites

Rust/Cargo >= 1.80, Elixir >= 1.16, Erlang/OTP >= 26, V >= 0.4.4,
Deno >= 2.0 (contract tests), just >= 1.25.

## Components

| Component | Language | LOC | Purpose |
|-----------|----------|-----|---------|
| clinician | Rust | ~4400 | AI-assisted sysadmin |
| emergency-room | V | ~1800 | Panic-safe intake |
| hardware-crash-team | Rust | ~700 | Hardware diagnostics |
| observatory | Elixir | ~600 | Metrics/monitoring |
| contracts | JSON+Deno | - | 8 data schemas |
| contracts-rust | Rust | - | Serde types |
| records/referrals | Elixir | ~400 | Bug reporting |

## Clinician Feature Gates

```bash
cargo build -p ambientops-clinician                     # Default (fast)
cargo build -p ambientops-clinician --features ai       # Ollama
cargo build -p ambientops-clinician --features storage  # ArangoDB
cargo build -p ambientops-clinician --features p2p      # libp2p gossipsub
cargo build -p ambientops-clinician --all-features      # Everything
```

## Hardware Crash Team

Origin: NVIDIA Quadro M2000M zombie GPU caused 43+ reboots in 3 days.
Commands: scan, diagnose, plan, apply, undo, status, tui.
Output: text (default), json, sarif.
6 remediation strategies. 60 tests. 9 SARIF rules (HCT001-HCT009).

## Satellites (Separate Repos)

panic-attacker, verisim, hypatia, gitbot-fleet, echidna.
