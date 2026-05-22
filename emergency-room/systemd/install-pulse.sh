#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Install AmbientOps Pulse user service and binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$ER_DIR/.." && pwd)"

echo "=== AmbientOps Pulse Installer ==="
echo ""

mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/ambientops/pulse"

echo "Building emergency-room (Rust)..."
cargo build --manifest-path "$REPO_DIR/Cargo.toml" -p emergency-room

install -m 0755 "$REPO_DIR/target/debug/emergency-room" "$HOME/.local/bin/emergency-room"
cp "$SCRIPT_DIR/ambientops-pulse.service" "$HOME/.config/systemd/user/"

systemctl --user daemon-reload
systemctl --user disable --now ambientops-oom-watch.service >/dev/null 2>&1 || true
systemctl --user enable --now ambientops-pulse.service

echo ""
echo "Installed and started: ambientops-pulse.service"
echo "Check status:"
echo "  systemctl --user status ambientops-pulse.service"
echo ""
echo "Stream logs:"
echo "  journalctl --user -u ambientops-pulse -f"
