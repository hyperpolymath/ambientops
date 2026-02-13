# Contract Schema Wiring

<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

How AmbientOps contract schemas connect producers to consumers.

## Wired Schemas

| Schema | Producer(s) | Consumer(s) | Status |
|--------|-------------|-------------|--------|
| `evidence-envelope` | emergency-room (`--envelope`), hardware-crash-team (`scan --envelope`) | observatory (`ingest-envelope`), records/referrals (`submit_from_envelope`) | **Wired** |
| `procedure-plan` | hardware-crash-team (`plan`) | clinician (apply), composer (orchestrate) | **Wired** |
| `receipt` | emergency-room (`write_receipt`), hardware-crash-team (`apply --receipt`) | observatory (`ingest`) | **Wired** |
| `system-weather` | observatory (`weather`) | nafa-app (satellite: `GET /api/weather`) | **Wired** |

## Typed Schemas (Rust types, producers/consumers pending)

| Schema | Planned Producer | Planned Consumer | Status |
|--------|------------------|------------------|--------|
| `message-intent` | nafa-app (satellite: user actions) | composer (orchestration) | **Typed** — Rust serde types in `contracts-rust/src/message_intent.rs` |
| `pack-manifest` | composer (pack builder) | clinician (apply), observatory (ingest) | **Typed** — Rust serde types in `contracts-rust/src/pack_manifest.rs` |
| `ambient-payload` | observatory (ambient) | nafa-app (satellite: Ward UI) | **Typed** — Rust serde types in `contracts-rust/src/ambient_payload.rs` |
| `run-bundle` | composer (run orchestrator) | observatory (ingest) | **Typed** — Rust serde types in `contracts-rust/src/run_bundle.rs` |

## Data Flow

```
Emergency Room                Operating Room              Ward / Records
─────────────                ──────────────              ──────────────

                          ┌─ hardware-crash-team
emergency-room ──envelope──┤                          ┌─ observatory ──weather──→ (nafa-app satellite)
                          └─ clinician                │
                               │                      │
                            plan/apply ──receipt──────┘
                               │
                          records/referrals ◄──envelope── (submit findings)
```

## Validation

All schemas are validated by `contracts/` (Deno + JSON Schema) and `contracts-rust/` (serde types).

```bash
cd contracts && deno test   # Schema validation tests
cargo test -p contracts     # Rust type round-trip tests
```
