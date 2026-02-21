<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-02-19 -->

# AmbientOps — Project Topology

## System Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              USER / CLIENT              │
                        │        (CLI, Dashboard, Agents)         │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │           HYBRID MONOREPO CORE          │
                        │                                         │
                        │  ┌───────────┐Department: WARD          │
                        │  │Observatory│ Metrics, Weather,        │
                        │  │ (Elixir)  │ Ambient Guidance         │
                        │  └─────┬─────┘                          │
                        │        │                                │
                        │  ┌─────▼─────┐Department: EMERGENCY RM  │
                        │  │ Emergency │ Panic-safe intake,       │
                        │  │   Room (V)│ Stabilization            │
                        │  └─────┬─────┘                          │
                        │        │                                │
                        │  ┌─────▼─────┐Department: OPERATING RM  │
                        │  │ Clinician │ Scan → Plan → Apply      │
                        │  │ (Rust)    │ (hardware-crash-team)    │
                        │  └─────┬─────┘                          │
                        │        │                                │
                        │  ┌─────▼─────┐Department: RECORDS       │
                        │  │ Records   │ Receipts, Undo Tokens,   │
                        │  │ (Elixir)  │ Referrals                │
                        │  └─────┬─────┘                          │
                        └────────│────────────────────────────────┘
                                 │
                                 ▼
                        ┌─────────────────────────────────────────┐
                        │          CONTRACTS LAYER                │
                        │   (Evidence Envelope, Procedure Plan,   │
                        │    Receipt, System Weather, etc.)       │
                        │  ┌───────────┐  ┌───────────────────┐  │
                        │  │ JSON/Deno │  │ Rust / Serde      │  │
                        │  └───────────┘  └───────────────────┘  │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │          SATELLITE ECOSYSTEM            │
                        │ (panic-attacker, verisimdb, hypatia,    │
                        │  gitbot-fleet, echidna)                 │
                        └─────────────────────────────────────────┘
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
─────────────────────────────────  ──────────────────  ─────────────────────────────────
HOSPITAL DEPARTMENTS
  Ward (observatory)                ████████░░  85%    Metrics and weather stable
  Emergency Room                    ███████░░░  75%    Panic-safe intake functional
  Operating Room (clinician)        █████░░░░░  55%    Procedure logic refining
  Hardware Crash Team               ███████░░░  75%    PCI zombie detection active
  Records (referrals)               ██████░░░░  65%    Bug reporting MCP functional

DATA & CONTRACTS
  contracts (JSON/Deno)             ████████░░  80%    8 core schemas defined
  contracts-rust                    ████████░░  80%    Serde types matching schemas
  composer (Gleam)                  █░░░░░░░░░  10%    Orchestration stubs

REPO INFRASTRUCTURE
  Justfile                          ██████████ 100%    Full build/test automation
  .machine_readable/                ██████████ 100%    STATE.scm, ECOSYSTEM.scm
  Cargo Workspace                   ██████████ 100%    Monorepo management

─────────────────────────────────────────────────────────────────────────────
OVERALL:                            ███████░░░  ~75%   Core departments operational
```

## Key Dependencies

```
Evidence Envelope ───► Procedure Plan ───► Execution (OR)
          ▲                                     │
          │                                     ▼
   Hardware Scan                           Receipt (Undo)
          │                                     │
          └─────────────┬───────────────────────┘
                        ▼
                 System Weather (Ward)
```

## Update Protocol

This file is maintained by both humans and AI agents. When updating:

1. **After completing a component**: Change its bar and percentage
2. **After adding a component**: Add a new row in the appropriate section
3. **After architectural changes**: Update the ASCII diagram
4. **Date**: Update the `Last updated` comment at the top of this file

Progress bars use: `█` (filled) and `░` (empty), 10 characters wide.
Percentages: 0%, 10%, 20%, ... 100% (in 10% increments).
