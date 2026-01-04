# CLAUDE.md - AI Assistant Instructions

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
