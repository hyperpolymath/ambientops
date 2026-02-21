#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# run-constrained.sh - Run nerdsafe-restart container with system-matched constraints
#
# This script detects your system's actual resources and constrains the
# validation container to match, ensuring the simulation is realistic.
#
# Usage:
#   ./run-constrained.sh [check|simulate|--paranoid|...]

set -euo pipefail

# =============================================================================
# SYSTEM RESOURCE DETECTION
# =============================================================================

echo "=== DETECTING SYSTEM RESOURCES ==="

# Memory (in bytes)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_BYTES=$((TOTAL_MEM_KB * 1024))
AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
AVAILABLE_MEM_BYTES=$((AVAILABLE_MEM_KB * 1024))

# Use 50% of available memory as limit (conservative)
CONTAINER_MEM_LIMIT=$((AVAILABLE_MEM_BYTES / 2))

echo "  Total RAM: $((TOTAL_MEM_KB / 1024)) MB"
echo "  Available RAM: $((AVAILABLE_MEM_KB / 1024)) MB"
echo "  Container limit: $((CONTAINER_MEM_LIMIT / 1024 / 1024)) MB"

# CPU
TOTAL_CPUS=$(nproc)
# Use half the CPUs or at least 1
CONTAINER_CPUS=$((TOTAL_CPUS / 2))
[[ $CONTAINER_CPUS -lt 1 ]] && CONTAINER_CPUS=1

echo "  Total CPUs: $TOTAL_CPUS"
echo "  Container CPUs: $CONTAINER_CPUS"

# Disk I/O - detect device for home
HOME_DEVICE=$(df "$HOME" | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//')
# Get base device without partition number
HOME_DEVICE_BASE=$(echo "$HOME_DEVICE" | sed 's/p$//')

echo "  Home device: $HOME_DEVICE"

# Swap
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
CONTAINER_SWAP_LIMIT=$((SWAP_TOTAL_KB * 1024 / 4)) # 25% of swap

echo "  Swap limit: $((CONTAINER_SWAP_LIMIT / 1024 / 1024)) MB"

# =============================================================================
# SECURITY CONSTRAINTS
# =============================================================================

echo ""
echo "=== SECURITY CONSTRAINTS ==="

# No new privileges
echo "  - No privilege escalation (--security-opt=no-new-privileges)"

# Read-only root filesystem
echo "  - Read-only root filesystem (--read-only)"

# Drop all capabilities except minimal set
echo "  - Dropped capabilities (--cap-drop=ALL)"

# No network (validation doesn't need it)
echo "  - Network isolated (--network=none)"

# Temporary filesystems for /tmp and /run
echo "  - tmpfs for /tmp and /run"

# PID limit to prevent fork bombs
PID_LIMIT=256
echo "  - PID limit: $PID_LIMIT"

# ulimits
NOFILE_LIMIT=1024
NPROC_LIMIT=64
echo "  - Open files limit: $NOFILE_LIMIT"
echo "  - Process limit: $NPROC_LIMIT"

# =============================================================================
# TIMEOUT
# =============================================================================

# Maximum validation time (5 minutes should be plenty)
TIMEOUT=300
echo "  - Timeout: ${TIMEOUT}s"

# =============================================================================
# BUILD CONTAINER IF NEEDED
# =============================================================================

echo ""
echo "=== CONTAINER SETUP ==="

IMAGE_NAME="nerdsafe-restart:kinoite"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if image exists
if ! nerdctl image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Building container image..."
    nerdctl build \
        -t "$IMAGE_NAME" \
        -f "$SCRIPT_DIR/Containerfile.kinoite" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        --build-arg USER_NAME="$(whoami)" \
        "$SCRIPT_DIR"
else
    echo "Using existing image: $IMAGE_NAME"
fi

# =============================================================================
# RUN CONSTRAINED CONTAINER
# =============================================================================

echo ""
echo "=== RUNNING CONSTRAINED VALIDATION ==="
echo ""

# Construct nerdctl run command
NERDCTL_ARGS=(
    run
    --rm
    --interactive

    # Resource limits (matching system)
    --memory="${CONTAINER_MEM_LIMIT}"
    --memory-swap="$((CONTAINER_MEM_LIMIT + CONTAINER_SWAP_LIMIT))"
    --cpus="${CONTAINER_CPUS}"
    --pids-limit="${PID_LIMIT}"

    # Security constraints
    --security-opt=no-new-privileges
    --cap-drop=ALL
    --read-only
    --network=none

    # ulimits
    --ulimit="nofile=${NOFILE_LIMIT}:${NOFILE_LIMIT}"
    --ulimit="nproc=${NPROC_LIMIT}:${NPROC_LIMIT}"

    # Temporary filesystems
    --tmpfs=/tmp:rw,noexec,nosuid,size=64m
    --tmpfs=/run:rw,noexec,nosuid,size=16m
    --tmpfs=/home/"$(whoami)"/.cache:rw,noexec,nosuid,size=32m

    # Mount home directory READ-ONLY for validation
    --volume="${HOME}:${HOME}:ro"

    # Mount specific config directories
    --volume="${HOME}/.bashrc:${HOME}/.bashrc:ro"
    --volume="${HOME}/.bashrc.d:${HOME}/.bashrc.d:ro"
    --volume="${HOME}/.config:${HOME}/.config:ro"
    --volume="${HOME}/.local:${HOME}/.local:ro"

    # Mount asdf if present
    ${HOME}/.asdf && --volume="${HOME}/.asdf:${HOME}/.asdf:ro"

    # Environment
    --env="HOME=${HOME}"
    --env="USER=$(whoami)"
    --env="SHELL=/bin/bash"
    --env="TERM=${TERM:-xterm-256color}"

    # User
    --user="$(id -u):$(id -g)"

    # Image
    "$IMAGE_NAME"
)

# Add asdf mount if directory exists
if [[ -d "${HOME}/.asdf" ]]; then
    NERDCTL_ARGS=(
        "${NERDCTL_ARGS[@]:0:$((${#NERDCTL_ARGS[@]}-1))}"
        --volume="${HOME}/.asdf:${HOME}/.asdf:ro"
        "$IMAGE_NAME"
    )
fi

# Add command arguments
NERDCTL_ARGS+=("$@")

# Run with timeout
timeout "${TIMEOUT}" nerdctl "${NERDCTL_ARGS[@]}"
EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "=== VALIDATION COMPLETE (constrained to system resources) ==="
elif [[ $EXIT_CODE -eq 124 ]]; then
    echo "=== VALIDATION TIMED OUT after ${TIMEOUT}s ==="
    exit 2
else
    echo "=== VALIDATION FAILED (exit code: $EXIT_CODE) ==="
    exit $EXIT_CODE
fi
