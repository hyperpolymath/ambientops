# Contract Schema Wiring

<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

How AmbientOps contract schemas connect producers to consumers.

## Wired Schemas

| Schema | Producer(s) | Consumer(s) | Status |
|--------|-------------|-------------|--------|
| `evidence-envelope` | emergency-room (`--envelope`), hardware-crash-team (`scan --envelope`) | observatory (`ingest-envelope`), records/referrals (`submit_from_envelope`) | **Wired** |
| `procedure-plan` | hardware-crash-team (`plan`) | clinician (apply), composer (orchestrate) | **Wired** |
| `receipt` | emergency-room (`write_receipt`), hardware-crash-team (`apply --receipt`) | observatory (`ingest`) | **Wired** |
| `system-weather` | observatory (`weather`) | nafa-app (`GET /api/weather`) | **Wired** |

## Future Schemas

| Schema | Planned Producer | Planned Consumer | Notes |
|--------|------------------|------------------|-------|
| `message-intent` | nafa-app (user actions) | composer (orchestration) | Phase 3: Ward→OR messaging |
| `pack-manifest` | composer (pack builder) | clinician (apply), observatory (ingest) | Phase 4: Deployment bundles |
| `ambient-payload` | composer (ambient compute) | clinician (execute) | Phase 5: Ambient compute payloads |
| `run-bundle` | composer (run orchestrator) | observatory (ingest) | Phase 5: Full run output bundles |

## Data Flow

```
Emergency Room                Operating Room              Ward / Records
─────────────                ──────────────              ──────────────

                          ┌─ hardware-crash-team
emergency-room ──envelope──┤                          ┌─ observatory ──weather──→ nafa-app
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
