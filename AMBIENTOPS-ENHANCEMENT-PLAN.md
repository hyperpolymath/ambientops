<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) -->
<!-- AMBIENTOPS-ENHANCEMENT-PLAN.md — System log analysis findings and build plan -->
<!-- Created: 2026-03-20 -->

# AmbientOps Enhancement Plan: System Log Analysis (2026-03-20)

## Purpose

This document records the findings from a deep system log analysis performed
on 2026-03-20 against the primary development workstation (Fedora 43 Atomic,
dual NVMe, KDE/Wayland). It maps discovered chronic conditions to new
ambientops components that need building.

**Audience:** Any AI agent or human contributor working on ambientops.

**Context:** AmbientOps uses a hospital model (see `HOSPITAL_MODEL.adox`).
Components live in departments: Ward (observatory), Emergency Room, Operating
Room (clinician), and Records. The system is a hybrid monorepo — all new
components belong here, never in standalone repos.

---

## Executive Summary: 5 Chronic Conditions

The system log analysis revealed five chronic conditions affecting the
workstation. These range from critical hardware degradation to minor usability
annoyances. Together they paint a picture of a system under stress from aging
NVMe hardware, accumulated unsafe shutdowns, and service instability.

| ID     | Condition                         | Severity | Root Cause                                         |
|--------|-----------------------------------|----------|-----------------------------------------------------|
| CC-001 | Samsung 960 EVO aging             | HIGH     | 52% life remaining, 15,965 media/data errors       |
| CC-002 | Unsafe shutdown epidemic          | HIGH     | 2,677 unsafe shutdowns across both NVMe drives     |
| CC-003 | Boot storm / NVMe probe failure   | CRITICAL | PCIe link training fails, causing boot loops        |
| CC-004 | session-sentinel D-Bus crash loop | MEDIUM   | Service starts before D-Bus session bus is ready    |
| CC-005 | Bluetooth A2DP contention         | LOW      | PipeWire/WirePlumber codec negotiation conflicts    |

---

## Condition Details

### CC-001: Samsung 960 EVO Aging

**Drive:** `nvme1n1` (Samsung 960 EVO 250GB)
**Mount points:** `/` (root), `/boot`, `/home`
**SMART data:**
- Available spare: 52% (was 100% at manufacture)
- Media and Data Integrity Errors: 15,965
- Temperature: intermittent throttling observed

**Risk:** This is the Fedora OS drive. Total failure loses the operating system,
boot configuration, and home directory. The Eclipse drive (`nvme0n1`, SK hynix
477GB) holds repos and data, so code is safe, but the system would be unbootable.

**What ambientops needs to do:**
1. Continuously monitor SMART attributes (`nvme-sentinel`)
2. Alert when spare drops below 30% (warning) or 15% (critical)
3. Track error rate trends — a spike means imminent failure
4. Generate a migration plan when critical threshold is reached

### CC-002: Unsafe Shutdown Epidemic

**Scope:** Both NVMe drives combined: 2,677 unsafe shutdowns
**Impact:** Each unsafe shutdown risks:
- Filesystem metadata corruption (btrfs is resilient but not immune)
- NVMe FTL table damage
- Accelerated flash cell wear

**What ambientops needs to do:**
1. Track shutdown quality — was it clean or forced? (`shutdown-marshal`)
2. Ensure filesystems are synced and flushed before power-off
3. Alert when unsafe shutdown rate spikes (>5 in 24h)
4. Correlate with boot failures (CC-003) and crash loops (CC-004)

### CC-003: Boot Storm / NVMe Probe Failure

**Symptoms:** During early boot, the kernel logs:
```
nvme nvme0: PCIe link not ready
nvme nvme0: Removing after probe failure
```

The NVMe controller fails to negotiate a stable PCIe link. The kernel retries,
sometimes succeeding after delays, sometimes failing entirely. When the root
filesystem probe fails, the system enters a boot loop — each reboot adds
another unsafe shutdown (feeding CC-002).

**What ambientops needs to do:**
1. Detect boot loops — N failed boots in a row (`boot-guardian`, HCT011)
2. Detect PCIe link failures in dmesg (`hardware-crash-team`, HCT010)
3. Trigger safe-mode or fallback boot entry after threshold
4. Capture dmesg evidence for each failed boot attempt

### CC-004: session-sentinel D-Bus Crash Loop

**Service:** `session-sentinel.service` (systemd user unit)
**Trigger:** Starts before D-Bus session bus is available
**Behavior:** crash-restart-crash-restart loop for ~30-60 seconds at login
**Impact:** Delays session readiness, floods journal, wastes CPU

**What ambientops needs to do:**
1. Detect crash-looping services (`service-autopsy`)
2. Collect crash context: journal, coredumps, D-Bus state
3. Produce structured autopsy report
4. Clinician rule: disable non-critical services after 3 restarts in 5 minutes

### CC-005: Bluetooth A2DP Contention

**Subsystem:** PipeWire + WirePlumber + BlueZ
**Symptoms:** Brief audio drops when switching between paired Bluetooth devices
**Impact:** Usability annoyance only — no stability or data risk

**What ambientops needs to do:**
1. Monitor profile switch frequency in observatory
2. Alert if switches exceed 5/hour (something is flapping)
3. Low priority — address after CC-001 through CC-004

---

## Condition-to-Component Mapping

```
CC-001 (NVMe aging)          ──► nvme-sentinel (observatory)
                              ──► clinician rules (nvme-wear-critical, nvme-temp-throttle)
                              ──► HCT010 (hardware-crash-team)

CC-002 (unsafe shutdowns)    ──► shutdown-marshal (emergency-room)
                              ──► nvme-sentinel (tracking delta)
                              ──► clinician rules (unsafe-shutdown-spike)

CC-003 (boot storm)          ──► boot-guardian (emergency-room)
                              ──► HCT010 (PCIe link failure detection)
                              ──► HCT011 (boot loop detection)
                              ──► clinician rules (boot-loop-detected)

CC-004 (service crash loop)  ──► service-autopsy (records)
                              ──► clinician rules (service-crash-loop)
                              ──► observatory thresholds (restart rate)

CC-005 (Bluetooth A2DP)      ──► observatory thresholds (profile switch rate)
```

---

## New Components to Build

### 1. nvme-sentinel (Priority 1)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Department  | Observatory (Ward)                                  |
| Language    | Elixir                                              |
| Purpose     | Continuous NVMe SMART health monitoring             |
| Location    | `observatory/lib/nvme_sentinel/`                    |
| Contracts   | `system-weather.schema.json`, `evidence-envelope.schema.json` |
| Addresses   | CC-001, CC-002                                      |

**Responsibilities:**
- Poll NVMe SMART data via `nvme smart-log` at configurable intervals
- Track: available spare, temperature, media errors, unsafe shutdowns
- Compute deltas and trend lines
- Emit system-weather updates (Calm/Watch/Act)
- Fire alerts when thresholds are crossed
- Feed data to the NVMe Health PanLL panel

### 2. boot-guardian (Priority 1)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Department  | Emergency Room                                      |
| Language    | V                                                   |
| Purpose     | Boot health monitoring and loop detection            |
| Location    | `emergency-room/src/boot_guardian/`                 |
| Contracts   | `evidence-envelope.schema.json`, `run-bundle.schema.json` |
| Addresses   | CC-002, CC-003                                      |

**Responsibilities:**
- Record boot timestamps and outcomes (success/failure)
- Detect boot loops (N failures in M minutes)
- Capture early dmesg for failed boots
- Trigger safe-mode or fallback boot entries
- Produce evidence envelopes for each boot failure
- Integrate with systemd boot-complete.target

### 3. service-autopsy (Priority 2)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Department  | Records                                             |
| Language    | Elixir                                              |
| Purpose     | Post-mortem analysis of crashed services             |
| Location    | `records/service_autopsy/`                          |
| Contracts   | `evidence-envelope.schema.json`, `receipt.schema.json` |
| Addresses   | CC-004                                              |

**Responsibilities:**
- Watch for systemd service failures (OnFailure= hooks or journal monitoring)
- Collect: journal entries, coredumps, D-Bus state, dependency graph
- Identify crash patterns (time-of-day, trigger correlation)
- Produce structured autopsy reports
- Feed crash frequency data to observatory

### 4. shutdown-marshal (Priority 2)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Department  | Emergency Room                                      |
| Language    | V                                                   |
| Purpose     | Graceful shutdown orchestration                      |
| Location    | `emergency-room/src/shutdown_marshal/`              |
| Contracts   | `receipt.schema.json`, `run-bundle.schema.json`     |
| Addresses   | CC-002                                              |

**Responsibilities:**
- Intercept shutdown/reboot signals
- Ensure filesystem sync + NVMe flush before power-off
- Log shutdown quality (clean vs. forced vs. timeout)
- Produce receipt for each shutdown event
- Track shutdown duration and flag degradation

### 5. HCT010 — NVMe PCIe Link Failure (Priority 1)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Component   | hardware-crash-team                                 |
| Type        | SARIF rule                                          |
| Language    | Rust                                                |
| Addresses   | CC-003                                              |

**Detection:** Scan dmesg/journal for `nvme.*PCIe link not ready` and
`nvme.*Removing after probe failure` patterns. Emit SARIF result with
device path, timestamp, and link speed/width info.

### 6. HCT011 — Boot Loop Detection (Priority 2)

| Property    | Value                                              |
|-------------|-----------------------------------------------------|
| Component   | hardware-crash-team                                 |
| Type        | SARIF rule                                          |
| Language    | Rust                                                |
| Addresses   | CC-003                                              |

**Detection:** Read boot-guardian's boot history. If N consecutive boots
failed within M minutes, emit SARIF warning with boot timestamps and
failure reasons.

---

## Auto-Remediation Rules (Clinician)

These are `procedure-plan` contracts that the clinician can execute
automatically or with user consent.

| Rule ID                | Trigger                              | Action                                         | Consent? | Severity |
|------------------------|--------------------------------------|-------------------------------------------------|----------|----------|
| nvme-temp-throttle     | Temperature > 70C for > 60s         | Reduce IO scheduler priority; alert user        | No       | Warning  |
| nvme-wear-critical     | Life remaining < 20%                 | Generate migration plan; escalate to OR         | Yes      | Critical |
| unsafe-shutdown-spike  | >5 unsafe shutdowns in 24h           | Enable shutdown-marshal aggressive mode         | No       | Warning  |
| service-crash-loop     | >3 restarts in 5 minutes             | Collect autopsy; disable if non-critical        | Yes      | Warning  |
| boot-loop-detected     | >2 consecutive failed boots          | Trigger safe-mode; preserve dmesg evidence      | No       | Critical |

**Consent model:** Rules marked "No" are defensive/non-destructive. Rules
marked "Yes" require explicit user approval via the Operating Room consent
flow (scan -> plan -> approve -> apply -> receipt).

---

## Alerting Thresholds (Observatory)

| Metric                          | Warning     | Critical    | Unit          | Poll Interval |
|----------------------------------|-------------|-------------|---------------|---------------|
| NVMe composite temperature       | 65          | 75          | Celsius       | 30s           |
| NVMe available spare             | 30%         | 15%         | Percent       | 1h            |
| NVMe media errors (daily delta)  | 100         | 1,000       | Count/day     | 1h            |
| Unsafe shutdown rate              | 3           | 5           | Count/24h     | 1h            |
| Boot duration                     | 120s        | 300s        | Seconds       | Per boot      |
| Service restart rate              | 3           | 5           | Count/5min    | 60s           |
| BT profile switch rate            | 5           | 10          | Count/hour    | 5min          |

---

## Priority Ordering

**Priority 1 (build first — addresses critical/high conditions):**
1. `nvme-sentinel` — CC-001 is the highest long-term risk
2. `boot-guardian` — CC-003 causes active boot loops
3. HCT010 SARIF rule — enables detection of PCIe link failures

**Priority 2 (build next — addresses medium conditions and prevention):**
4. `service-autopsy` — CC-004 degrades login experience
5. `shutdown-marshal` — CC-002 prevention
6. HCT011 SARIF rule — boot loop detection
7. Clinician auto-remediation rules

**Priority 3 (polish — low severity and dashboards):**
8. Observatory alerting thresholds for all metrics
9. Bluetooth A2DP monitoring (CC-005)
10. PanLL panels for all new data sources

---

## File References

| File | Purpose |
|------|---------|
| `.machine_readable/6a2/STATE.a2ml` | Machine-readable state with all conditions, components, and thresholds |
| `HOSPITAL_MODEL.adox` | Hospital department model and safety boundaries |
| `TOPOLOGY.md` | Architecture diagram and completion dashboard |
| `contracts/schemas/` | 8 JSON schemas (system-weather, evidence-envelope, procedure-plan, etc.) |
| `panll/panels-needed.md` | PanLL panel specifications for all new data sources |
| `hardware-crash-team/` | Existing SARIF scanner (HCT001-HCT009); needs HCT010, HCT011 |

---

## Notes for AI Visitors

1. **Never create standalone repos** for any of these components. Everything
   lives in the ambientops monorepo.
2. **Language assignments are deliberate:** Elixir for long-running observers
   (observatory, records), V for fast early-boot and shutdown-path code
   (emergency-room), Rust only in hardware-crash-team (scalpel rule).
3. **Contracts are the data backbone.** Every component reads and writes via
   the JSON schemas in `contracts/schemas/`. Check `contracts/WIRING.md` for
   the data flow.
4. **Hospital model safety rules apply.** Ward never mutates. Emergency Room
   defaults non-destructive. Operating Room requires consent. Every apply
   produces a receipt. See `HOSPITAL_MODEL.adox`.
5. **PanLL panels use "panels" never "panes".** See `panll/panels-needed.md`.
