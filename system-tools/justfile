# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>
#
# system-tools monorepo justfile
# Unified task runner for monitoring, recovery, and ambulance components.

# Default: list all available recipes
default:
    @just --list

# --- Monitoring ---

# Run observatory (Elixir) tasks
monitoring-observatory:
    @echo "==> monitoring/observatory"
    @if [ -f monitoring/observatory/justfile ]; then just -f monitoring/observatory/justfile; else echo "No justfile found"; fi

# Run systems-observatory (Julia) tasks
monitoring-systems-observatory:
    @echo "==> monitoring/systems-observatory"
    @if [ -f monitoring/systems-observatory/justfile ]; then just -f monitoring/systems-observatory/justfile; else echo "No justfile found"; fi

# Run flare tasks
monitoring-flare:
    @echo "==> monitoring/flare"
    @if [ -f monitoring/flare/justfile ]; then just -f monitoring/flare/justfile; else echo "No justfile found"; fi

# --- Recovery ---

# Run emergency-room tasks
recovery-emergency-room:
    @echo "==> recovery/emergency-room"
    @if [ -f recovery/emergency-room/justfile ]; then just -f recovery/emergency-room/justfile; else echo "No justfile found"; fi

# Run operating-theatre tasks
recovery-operating-theatre:
    @echo "==> recovery/operating-theatre"
    @if [ -f recovery/operating-theatre/justfile ]; then just -f recovery/operating-theatre/justfile; else echo "No justfile found"; fi

# Run freeze-ejector tasks
recovery-freeze-ejector:
    @echo "==> recovery/freeze-ejector"
    @if [ -f recovery/freeze-ejector/justfile ]; then just -f recovery/freeze-ejector/justfile; else echo "No justfile found"; fi

# --- Ambulances ---

# Run disk ambulance tasks
ambulance-disk:
    @echo "==> ambulances/disk"
    @if [ -f ambulances/disk/justfile ]; then just -f ambulances/disk/justfile; else echo "No justfile found"; fi

# Run network ambulance tasks
ambulance-network:
    @echo "==> ambulances/network"
    @if [ -f ambulances/network/Justfile ]; then just -f ambulances/network/Justfile; elif [ -f ambulances/network/justfile ]; then just -f ambulances/network/justfile; else echo "No justfile found"; fi

# Run performance ambulance tasks
ambulance-performance:
    @echo "==> ambulances/performance"
    @if [ -f ambulances/performance/justfile ]; then just -f ambulances/performance/justfile; else echo "No justfile found"; fi

# Run security ambulance tasks
ambulance-security:
    @echo "==> ambulances/security"
    @if [ -f ambulances/security/justfile ]; then just -f ambulances/security/justfile; else echo "No justfile found"; fi

# --- Contracts ---

# Run contracts tasks
contracts:
    @echo "==> contracts"
    @if [ -f contracts/Mustfile ]; then echo "Contracts uses Mustfile"; elif [ -f contracts/justfile ]; then just -f contracts/justfile; else echo "No justfile found"; fi

# --- Aggregate ---

# Run all monitoring components
monitoring-all: monitoring-observatory monitoring-systems-observatory monitoring-flare

# Run all recovery components
recovery-all: recovery-emergency-room recovery-operating-theatre recovery-freeze-ejector

# Run all ambulance components
ambulance-all: ambulance-disk ambulance-network ambulance-performance ambulance-security

# Show structure of the monorepo
tree:
    @echo "system-tools monorepo structure:"
    @echo "  monitoring/"
    @echo "    observatory/          (from system-observatory)"
    @echo "    systems-observatory/  (from systems-observatory)"
    @echo "    flare/                (from system-flare)"
    @echo "  recovery/"
    @echo "    emergency-room/       (from system-emergency-room)"
    @echo "    operating-theatre/    (from system-operating-theatre)"
    @echo "    freeze-ejector/       (from system-freeze-ejector)"
    @echo "  ambulances/"
    @echo "    disk/                 (from disk-ambulance)"
    @echo "    network/              (from network-ambulance)"
    @echo "    performance/          (from performance-ambulance)"
    @echo "    security/             (from security-ambulance)"
    @echo "  contracts/              (from system-tools-contracts)"
