#!/usr/bin/env bash
set -Eeuo pipefail
echo "Installing carectl..."
cargo install carectl || echo "carectl install failed"
