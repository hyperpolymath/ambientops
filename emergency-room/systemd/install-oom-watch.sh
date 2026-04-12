#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Compatibility wrapper: install-oom-watch.sh -> install-pulse.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "install-oom-watch.sh is deprecated; forwarding to install-pulse.sh"
exec "$SCRIPT_DIR/install-pulse.sh" "$@"
