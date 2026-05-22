# AmbientOps LLM Warmup (Developer Context)

## Identity

- **Name**: AmbientOps
- **License**: MPL-2.0
- **Author**: Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
- **Repo**: https://github.com/hyperpolymath/ambientops

## Architecture

Hospital-model operations framework. Hybrid monorepo with Rust workspace,
Elixir applications, zig tools, and Deno contract tests.

### Component Map

```
ambientops/                      Hybrid monorepo
├── clinician/            (Rust ~4400 LOC)  Operating Room: AI-assisted sysadmin
├── emergency-room/       (V ~1800 LOC)     Emergency Room: panic-safe intake
├── hardware-crash-team/  (Rust ~700 LOC)   Operating Room: hardware diagnostics
├── observatory/          (Elixir ~600 LOC) Ward: metrics, weather, monitoring
├── contracts/            (JSON+Deno)       Data Backbone: 8 JSON schemas
├── contracts-rust/       (Rust)            Data Backbone: serde types + conversions
├── records/referrals/    (Elixir ~400 LOC) Records: multi-platform bug reporting
├── composer/             (stubs)           Operating Room: orchestration
├── displace/             (Rust)            Displacement tool
├── personal-sysadmin/    (Rust)            Personal sysadmin toolkit
├── panoptes/             (Rust)            Monitoring
├── czech-file-knife/     (Rust)            File manipulation tool
├── volumod/              (V)               Volume modifier
├── emergency-button/     (V)               Emergency button
├── network-dashboard/    (Elixir)          Network monitoring
├── total-update/         (Elixir)          System update orchestration
├── session-sentinel/     (Ephapax WIP)     Session health (disabled locally)
├── hybrid-automation-router/ (Elixir)      HAR integration
├── broad-spectrum/       (Deno)            Broad spectrum scanning
├── nick-shells/          (various)         Shell tools
├── system-tools/         (multi-lang)      Monitoring, recovery, ambulances
│   ├── monitoring/       observatory, systems-observatory, flare
│   ├── recovery/         emergency-room, operating-theatre, freeze-ejector
│   ├── ambulances/       network, performance
│   ├── contracts/        (Deno)
│   └── ffi/systemd/      Rust systemd shim
└── Cargo.toml            Rust workspace root
```

### Data Flow

```
ER intake → Evidence Envelope → Procedure Plan → Receipt → System Weather
```

## Build System

### Justfile Commands

```bash
just build-all        # Build Rust workspace + Elixir components
just test-all         # Run all tests (Rust + contracts + Elixir)
just build-rust       # Rust workspace only
just test-rust        # Rust tests only
just build-elixir     # Elixir components (observatory + referrals)
just test-elixir      # Elixir tests
just test-contracts   # Contract schema tests (Deno)
just scan             # Hardware scan (hardware-crash-team)
just scan-envelope    # Scan with contract envelope output
just demo             # End-to-end demo flow
just check            # Validate without building (cargo check + deno check)
just clean            # Clean all build artifacts
just security         # gitleaks + trivy audit
just audit            # Dependency vulnerability audit
just build-riscv      # Cross-compile for RISC-V (requires cross)
just integration-test # Integration test suite
just sync-metadata    # A2ML -> SCM shadow sync
```

### Cargo Workspace

Root `Cargo.toml` defines the workspace. Members include:
clinician, hardware-crash-team, contracts-rust, displace, personal-sysadmin,
panoptes, czech-file-knife (and sub-crates: cfk-core, cfk-cli, cfk-search,
cfk-vfs, cfk-providers, cfk-integrations, cfk-ios, cfk-cache).

### Elixir Components

| Component | Path | Mix Project |
|-----------|------|-------------|
| Observatory | observatory/ | mix.exs |
| Referrals | records/referrals/ | mix.exs |
| Network Dashboard | network-dashboard/ | mix.exs |
| Total Update | total-update/elixir/ | totalupdate + dnfinition |
| HAR | hybrid-automation-router/ | mix.exs |
| System Observatory | system-tools/monitoring/observatory/ | mix.exs |
| System Observatory v2 | system-tools/monitoring/systems-observatory/ | Justfile |

## Clinician Feature Gates

Heavy dependencies behind optional features for fast default builds:

| Feature | Dependency | Purpose |
|---------|-----------|---------|
| ai | ollama-rs | LLM integration |
| storage | arangors | ArangoDB graph traversal |
| p2p | libp2p | gossipsub mesh (Ed25519, mDNS, TCP+Noise+Yamux) |

```bash
cargo build -p ambientops-clinician                     # Default (none, fast)
cargo build -p ambientops-clinician --features ai       # Ollama
cargo build -p ambientops-clinician --features storage  # ArangoDB
cargo build -p ambientops-clinician --features p2p      # libp2p gossipsub
cargo build -p ambientops-clinician --all-features      # Everything (slow)
```

### p2p Details
Full libp2p mesh: persistent Ed25519 peer identity, gossipsub pub/sub on
`ambientops/solutions/v1` and `ambientops/sync/v1` topics, mDNS local
discovery, TCP+Noise+Yamux transport.

### storage Details
AQL graph queries: category lookup, text search, 2-step find+traverse,
outcome recording. Falls back to no-op when ArangoDB unavailable.

## Hardware Crash Team

Origin: NVIDIA Quadro M2000M zombie GPU causing 43+ reboots in 3 days.

### Capabilities
- Full scanner with BAR enumeration, lspci enrichment, interrupt checking
- 6 remediation strategies: pci-stub, vfio-pci, dual, power-off, disable, unbind
- Multi-device plans
- ATS2 TUI with 5 screens (behind `tui` feature)
- SARIF 2.1.0 output (9 rules HCT001-HCT009)
- 60 tests

### CLI Commands
scan, diagnose, plan, apply, undo, status, tui

### Output Formats
`--format text` (default), `--format json`, `--format sarif`

## zig Components

| Component | Path | Purpose |
|-----------|------|---------|
| Emergency Room | emergency-room/ | Panic-safe intake |
| Volumod | volumod/ | Volume modifier |
| Emergency Button | emergency-button/ | Emergency button |
| System ER | system-tools/recovery/emergency-room/ | System recovery |

Test V: `cd emergency-room && v test src/`

## Contract Schemas

8 JSON schemas in `contracts/`. Tested with Deno:
```bash
cd contracts && deno test --allow-read --no-check
```

Rust serde types in `contracts-rust/` provide typed access.

## Language Policy

### Allowed
Rust (agent/verify boxes), V (emergency/system tools), Elixir (observability only),
Deno (contract tests, automation), ReScript (primary app code), Bash (minimal scripts).

### Banned
TypeScript, Node.js, npm/yarn/pnpm/bun, Go, Python, Java/Kotlin, Swift.

### Rules
- Rust is a scalpel, not default (only agent-rs/verify-rs boxes)
- Elixir only for observability/event hubs -- NEVER source of truth
- No new TypeScript files
- No package.json for runtime deps

## Machine-Readable Files

Located in `.machine_readable/`:
- STATE.a2ml / META.a2ml / ECOSYSTEM.a2ml / AGENTIC.a2ml / NEUROSYM.a2ml / PLAYBOOK.a2ml
- (Also some repos may have .machine_readable/6a2/ variants)

**CRITICAL**: SCM files ONLY in `.machine_readable/` -- NEVER in root.

## Testing

```bash
just test-all          # Everything
just test-rust         # cargo test --workspace
just test-elixir       # mix test (observatory + referrals)
just test-contracts    # deno test (contract schemas)
just integration-test  # E2E integration script
```

## Security

```bash
just security          # gitleaks + trivy
just audit             # cargo audit
just assail            # panic-attacker pre-commit
```

## Satellites (Separate Repos)

| Satellite | Role |
|-----------|------|
| panic-attacker | Pre-commit security scanner |
| verisim | 8-modality versioned database |
| hypatia | Neurosymbolic CI/CD scanner |
| gitbot-fleet | Bot orchestration |
| echidna | Theorem prover dispatch |

## Next Steps (from CLAUDE.md)

1. VeriSimDB/Hypatia integration for hardware-crash-team
2. MCP server for hardware-crash-team external access

## Pre-commit

```bash
just assail            # panic-attacker scan
```
