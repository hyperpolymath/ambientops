# CLAUDE.md - AmbientOps AI Assistant Instructions

## Project Overview

AmbientOps is a hospital-model operations framework (hybrid monorepo). Components are organized by hospital department:

```
ambientops/                      ← Hybrid monorepo
├── clinician/            (Rust, ~4400 LOC) — Operating Room: AI-assisted sysadmin
├── emergency-room/       (V, ~1800 LOC)    — Emergency Room: panic-safe intake
├── hardware-crash-team/  (Rust, ~700 LOC)  — Operating Room: hardware diagnostics
├── observatory/          (Elixir, ~600 LOC)— Ward: metrics, weather, monitoring
├── contracts/            (JSON+Deno)       — Data Backbone: 8 JSON schemas
├── contracts-rust/       (Rust)            — Data Backbone: serde types + conversions
├── records/referrals/    (Elixir, ~400 LOC)— Records: multi-platform bug reporting
├── composer/             (stubs)           — Operating Room: orchestration
└── Cargo.toml            (workspace)       — Rust workspace root
```

**Data flow:** ER intake → Evidence Envelope → Procedure Plan → Receipt → System Weather

**Satellites (separate repos):** panic-attacker, verisimdb, hypatia, gitbot-fleet, echidna

## Build

```bash
just build-all                   # Build everything (Rust + Elixir + contracts)
just test-all                    # Run all tests
cargo build --workspace          # Rust crates only
cargo test --workspace           # Rust tests only
cd observatory && mix test       # Elixir observatory tests
cd records/referrals && mix test # Elixir referrals tests
cd contracts && deno test --allow-read  # Contract schema tests
cd emergency-room && v test src/ # V emergency-room tests
```

## hardware-crash-team (Added 2026-02-08)

Rust-based hardware diagnostic tool. See `hardware-crash-team/.claude/CLAUDE.md` for full details.

**Origin**: NVIDIA Quadro M2000M zombie GPU caused 43+ reboots in 3 days. Tool generalizes the fix.

**Key commands**: `scan`, `diagnose`, `plan`, `apply`, `undo`, `status`, `tui`

**Current state**: Full scanner with BAR enumeration, lspci enrichment, interrupt checking. All 6 remediation strategies working (pci-stub, vfio-pci, dual, power-off, disable, unbind). Multi-device plans. ATS2 TUI with 5 screens (behind `tui` feature). SARIF 2.1.0 output (9 rules HCT001-HCT009). 60 tests.

**Output formats**: `--format text` (default), `--format json`, `--format sarif`

**Next steps**:
1. VeriSimDB/Hypatia integration
2. MCP server for external tool access

## clinician feature gates

Heavy dependencies (arangors, redis, ollama-rs, libp2p, ndarray, scraper, tantivy) are behind optional cargo features. Default build compiles fast with no features enabled.

```bash
cargo build -p ambientops-clinician                    # Fast: default features (none)
cargo build -p ambientops-clinician --features ai      # Enable ollama-rs
cargo build -p ambientops-clinician --features storage  # Enable arangors (ArangoDB graph traversal)
cargo build -p ambientops-clinician --features p2p     # Enable libp2p (gossipsub mesh)
cargo build -p ambientops-clinician --all-features     # Everything (slow)
```

**p2p (gossipsub)**: Full libp2p mesh with persistent Ed25519 peer identity, gossipsub pub/sub on `ambientops/solutions/v1` and `ambientops/sync/v1` topics, mDNS local discovery, TCP+Noise+Yamux transport.

**storage (ArangoDB)**: Graph traversal via AQL queries — category lookup, text search, 2-step find+traverse for related solutions, outcome recording. Falls back to no-op when ArangoDB unavailable.

## Language Policy (Hyperpolymath Standard — January 2026)

### The D/V Layer Model

| Layer | Mnemonic | Responsibility | Primary Language |
|-------|----------|----------------|------------------|
| **D** | Drivers/Deployment/Delivery | Execution, IO, adapters | D |
| **V** | Verification/Validation/Veridicality | Policy, proofs, schemas | V |

### ALLOWED Languages & Tools

| Language/Tool | Use Case | Notes |
|---------------|----------|-------|
| **D** | Driver/deployment layer | Adapters, execution, IO boundaries |
| **V** | Verification layer | Policy, plan verification, schema conformance |
| **ReScript** | Primary application code | Compiles to JS, type-safe; AmbientOps primary |
| **Deno** | Runtime & package management | Replaces Node/npm/bun |
| **Rust** | Agent/verify boxes only | Isolated repos (`*-agent-rs/`, `*-verify-rs/`) |
| **Elixir** | Observability/event hub only | NEVER source of truth |
| **Gleam** | Backend services | Runs on BEAM or compiles to JS |
| **Bash/POSIX Shell** | Scripts, automation | Keep minimal |
| **JavaScript** | Only where ReScript cannot | MCP protocol glue, Deno APIs |
| **Nickel** | Configuration language | For complex configs |
| **Guile Scheme** | State/meta files | STATE.scm, META.scm, ECOSYSTEM.scm |
| **Julia** | Batch scripts, data processing | Per RSR |
| **OCaml** | AffineScript compiler | Language-specific |
| **V** | Emergency Room, system tools | Vlang.io, fast compilation |
| **Ada** | Safety-critical systems | Where required |
| **Bebop** | Wire serialization | JS+Rust peers; TS only as generated artifacts |
| **Protobuf** | Wire serialization | If Elixir must be a peer |

### BANNED - Do Not Use

| Banned | Replacement | Reason |
|--------|-------------|--------|
| TypeScript | ReScript | Type safety without JS baggage |
| Node.js | Deno | Security-first runtime |
| npm/yarn/pnpm/bun | Deno | Deno manages deps |
| Go | Rust | Memory safety without GC |
| **Python** | ReScript/Rust/D/V | **Completely banned** (SaltStack abandoned) |
| Java/Kotlin | Rust/Tauri | No JVM |
| Swift | Tauri/Dioxus | No Apple lock-in |

### Rust Usage Rules

Rust is a **scalpel, not default**. Only allowed in:
- `*-agent-rs/` repos (hardened local agents)
- `*-verify-rs/` repos (high-assurance verification)
- Isolated agent/verify components within larger repos

### Elixir Usage Rules

Elixir is allowed **only for observability/event hubs**:
- Long-running supervision trees
- Event ingestion and fanout
- Live dashboards
- **MUST NOT** become policy engine, IR authority, or config truth

### Enforcement Rules

1. **No new TypeScript files** - Convert existing TS to ReScript
2. **No package.json for runtime deps** - Use deno.json imports
3. **No node_modules in production** - Deno caches deps automatically
4. **No Go code** - Use Rust instead
5. **No Python anywhere** - Completely banned
6. **No Kotlin/Swift for mobile** - Use Tauri 2.0+ or Dioxus

### Package Management

- **Primary**: Guix (guix.scm)
- **Fallback**: Nix (flake.nix)
- **JS deps**: Deno (deno.json imports)

### Security Requirements

- No MD5/SHA1 for security (use SHA256+)
- HTTPS only (no HTTP URLs)
- No hardcoded secrets
- SHA-pinned dependencies
- SPDX license headers on all files

### SCM Checkpoint Files

Every repo should have at root:
- `STATE.scm` — current project state (update every session)
- `META.scm` — architecture decisions
- `ECOSYSTEM.scm` — project relationships

See `docs/SCM-FILES-GUIDE.adoc` for format and maintenance rules.
