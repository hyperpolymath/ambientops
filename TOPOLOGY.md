<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-03-23 -->

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
                        │ (panic-attacker, verisim, hypatia,    │
                        │  gitbot-fleet, echidna)                 │
                        └─────────────────────────────────────────┘
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
─────────────────────────────────  ──────────────────  ─────────────────────────────────
HOSPITAL DEPARTMENTS
  Ward (observatory)                ████████░░  85%    Metrics and weather stable
  Emergency Room (V)                ███████░░░  75%    Panic-safe intake functional
  Operating Room (clinician)        █████░░░░░  55%    Procedure logic refining
  Hardware Crash Team (Rust)        ███████░░░  75%    PCI zombie detection active
  Records (referrals, Elixir)       ██████░░░░  65%    Bug reporting MCP functional

DATA & CONTRACTS
  contracts (JSON/Deno)             ████████░░  80%    9 schemas (incl. ambient-payload)
  contracts-rust                    ████████░░  80%    Serde types matching schemas
  composer (Gleam)                  █░░░░░░░░░  10%    Orchestration stubs

SYSTEM TOOLS (ambientops monorepo members)
  broad-spectrum (AffineScript)         ██████░░░░  60%    Link/SEO/accessibility checker
  cicada                            ██░░░░░░░░  20%    Stub
  czech-file-knife                  ██░░░░░░░░  20%    File utilities
  displace                          ██░░░░░░░░  20%    Displacement tool
  emergency-button                  ██░░░░░░░░  20%    Emergency stop
  hybrid-automation-router          ██░░░░░░░░  20%    HAR integration
  nano-aider                        ██░░░░░░░░  20%    Lightweight aider
  nerdsafe-restart                  ██░░░░░░░░  20%    Safe restart orchestration
  network-dashboard                 ██░░░░░░░░  20%    Network monitoring
  network-orchestrator              ██░░░░░░░░  20%    Network automation
  nick-shells                       ██░░░░░░░░  20%    Shell utilities
  panoptes                          ██░░░░░░░░  20%    All-seeing monitoring
  personal-sysadmin                 ██░░░░░░░░  20%    Personal sysadmin scripts
  reasonably-good-token-vault       ██░░░░░░░░  20%    Token/secret storage
  session-sentinel (Ephapax WIP)    ███░░░░░░░  30%    Session health — disabled locally
  slopctl                           ██░░░░░░░░  20%    Slop control
  system-tools                      ██░░░░░░░░  20%    System utilities
  total-recall                      ██░░░░░░░░  20%    History/audit
  total-update                      ██░░░░░░░░  20%    Update orchestration
  traffic-conditioner               ██░░░░░░░░  20%    Network traffic shaping
  volumod                           ██░░░░░░░░  20%    Volume management

PLANNED (not yet built)
  nvme-sentinel                     ░░░░░░░░░░   0%    NVMe SMART monitoring
  boot-guardian                     ░░░░░░░░░░   0%    Boot health analysis
  service-autopsy                   ░░░░░░░░░░   0%    Service failure analysis
  shutdown-marshal                  ░░░░░░░░░░   0%    Shutdown sequencing

PANLL INTEGRATION
  panll/panels-needed.md            ████████░░  80%    6 panel specs defined

REPO INFRASTRUCTURE
  Justfile                          ██████████ 100%    Build/test + planned stubs
  .machine_readable/                ██████████ 100%    STATE.scm, ECOSYSTEM.scm
  Cargo Workspace                   ██████████ 100%    Monorepo management
  CI Workflows (18)                 ██████████ 100%    All SHA-pinned, SPDX headers

─────────────────────────────────────────────────────────────────────────────
OVERALL:                            ███████░░░  ~70%   Core departments operational
                                                        Many system-tools at stub stage
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
