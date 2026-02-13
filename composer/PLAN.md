# Composer — Orchestration Engine Plan

<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

## Status: Planned (Phase 5)

Composer is the orchestration engine for AmbientOps. It will coordinate multi-step procedures across the Operating Room components.

## Planned Architecture

```
                  ┌─────────────┐
                  │   Composer   │
                  │  Orchestrate │
                  └──────┬──────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
   ┌─────────────┐ ┌──────────┐ ┌──────────┐
   │  HCT Scan   │ │ Clinician│ │ ER Triage│
   │  + Plan     │ │  Apply   │ │  Intake  │
   └─────────────┘ └──────────┘ └──────────┘
```

## Contract Consumption

| Contract | Role | Description |
|----------|------|-------------|
| `procedure-plan` | **Consumer** | Reads plans from HCT/clinician, orchestrates execution |
| `receipt` | **Producer** | Emits receipts after each orchestrated step |
| `run-bundle` | **Producer** | Packages full run output for observatory ingestion |
| `pack-manifest` | **Producer** | Defines scan pack configurations |

## Planned Capabilities

1. **Scan → Plan → Apply chain** — Orchestrate the full diagnostic cycle
2. **Visual macro builder** — Define reusable procedure templates
3. **Parallel step execution** — Run independent steps concurrently
4. **Rollback coordination** — Use undo receipts to reverse failed procedures
5. **Dry-run orchestration** — Preview entire chain without mutations

## Language

**Gleam** — chosen for BEAM supervision trees (alongside observatory), type safety,
and native Elixir/Erlang interop. Compiles to BEAM or JS if needed.

## Dependencies

Composer depends on:
- contracts/ schemas being stable (they are)
- HCT and clinician having `--envelope` and `--procedure` flags (they do)
- Observatory having `ingest-envelope` CLI route (it does)

## Not Before

- Phase 3 (Ward MVP) and Phase 4 (Records MVP) should be complete first
- All 4 wired schemas should have at least 2 producers + 2 consumers
