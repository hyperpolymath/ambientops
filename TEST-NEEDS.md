# Test & Benchmark Requirements

## CRG Grade: C — ACHIEVED 2026-04-04

## Current State (Updated 2026-04-04)

### CRG C Achievement ✓

**contracts-rust/**: CRG Grade C ACHIEVED
- Unit tests: 15 (lib.rs)
- Property-based tests (proptest): 12 tests
- E2E tests: 5 full contract lifecycle tests
- Contract/invariant tests: 12 referential integrity & state validation tests
- Aspect tests: 13 (security, performance, correctness)
- Benchmarks: 12 criterion benchmarks baselined (envelope, plan, receipt, weather operations)
- **Total: 72 passing tests** ✓

### Remaining Components
- Unit tests: ~69 Elixir test files + 2 Gleam test files + ~17 Zig integration tests — counts unknown (cannot run mix test / gleam test without correct versions)
- Integration tests: partial (Zig FFI integration tests exist)
- panic-attack scan: NEVER RUN

## What's Missing
### Point-to-Point (P2P)
This is a monorepo with 20+ components. Coverage is extremely uneven:

#### Tested (Elixir — 69 test files)
- observatory/ — has tests
- network-dashboard/ — has tests
- composer/ — has Gleam tests (2 files)

#### UNTESTED Components
- **clinician/** (Rust) — Cargo.toml exists, 0 test files
- **hardware-crash-team/** (Rust) — Cargo.toml exists, 0 test files
- **contracts-rust/** (Rust) — Cargo.toml exists, 0 test files
- **czech-file-knife/** (Rust) — bench file exists but 0 test files
- **displace/** — no tests
- **emergency-button/** — no tests
- **emergency-room/** — no tests
- **nano-aider/** — no tests
- **nerdsafe-restart/** — no tests
- **network-orchestrator/** — no tests
- **nick-shells/** — no tests
- **panoptes/** — no tests
- **session-sentinel/** — no tests (Ephapax rewrite WIP)
- **broad-spectrum/** — no tests
- **cicada/** — no tests
- **ambulances/** — no tests
- **immutable-linux-auditor/** — no tests
- **hybrid-automation-router/** — no tests
- **ffi/fuse/** (Zig — 7+ files) — only template integration test
- **ffi/systemd/** (Zig) — only template integration test
- **monitoring/systems-observatory/** (Julia) — no tests
- **contracts/** (Deno) — no tests

Total: 163 Rust + 121 Elixir + 73 Zig + 46 Julia + 79 AffineScript + 44 V source files.
Test coverage concentrated in Elixir components only.

### End-to-End (E2E)
- Full system health monitoring pipeline (observatory -> alerts -> emergency-room)
- Network dashboard monitoring cycle
- Hardware crash detection and recovery workflow
- Immutable Linux audit cycle
- Session sentinel lifecycle
- FUSE filesystem mount/unmount/operations cycle
- Systemd unit management workflow
- Composer plan execution

### Aspect Tests
- [ ] Security (FUSE filesystem privilege escalation, network dashboard auth, systemd unit injection)
- [ ] Performance (monitoring overhead, FUSE latency, systemd watcher CPU usage)
- [ ] Concurrency (multiple monitoring agents, concurrent FUSE operations, race conditions)
- [ ] Error handling (hardware failures, network timeouts, service crashes)
- [ ] Accessibility (N/A — infrastructure tools)

### Build & Execution
- [ ] cargo build for all Rust components — not verified
- [ ] mix compile for Elixir components — not verified (version mismatch)
- [ ] gleam build for composer — not verified
- [ ] zig build for FFI — not verified
- [ ] Self-diagnostic — none

### Benchmarks Needed
- FUSE filesystem throughput (read/write/metadata)
- Monitoring agent resource overhead (CPU, memory)
- Czech file knife benchmarks (file exists — verify it runs)
- Systems observatory database benchmarks (file exists — verify it runs)
- Network orchestration latency
- Alert propagation time

### Self-Tests
- [ ] panic-attack assail on own repo
- [ ] Built-in health check for each component
- [ ] Systemd unit file validation

## Priority
- **HIGH** — Massive monorepo (163 Rust + 121 Elixir + 73 Zig + 46 Julia files across 20+ components) with tests concentrated only in the Elixir components. The Rust, Zig, Julia, and AffineScript components are essentially untested. Infrastructure tools need especially high reliability.

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
