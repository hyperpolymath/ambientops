#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Generate man pages for dnfinition and totalupdate
set -euo pipefail

mkdir -p docs/man

cat > docs/man/dnfinition.1 << 'MANEOF'
.TH DNFINITION 1 "2025-12-27" "0.1.0" "DNFinition Manual"
.SH NAME
dnfinition \- Universal package manager TUI with reversibility
.SH SYNOPSIS
.B dnfinition
[COMMAND] [OPTIONS]
.SH DESCRIPTION
DNFinition is an interactive TUI package manager that provides a unified
interface to 50+ package managers with built-in reversibility through
snapshots and transaction logging.
.SH COMMANDS
.TP
.B (none)
Start interactive TUI mode
.TP
.B search QUERY
Search for packages
.TP
.B install PKG...
Install packages (creates snapshot first)
.TP
.B remove PKG...
Remove packages
.TP
.B upgrade
Upgrade all packages
.TP
.B snapshots
List available snapshots
.TP
.B rollback [ID]
Rollback to a snapshot
.TP
.B info
Show platform information
.SH AUTHOR
Jonathan D.A. Jewell <jonathan@hyperpolymath.io>
.SH LICENSE
PMPL-1.0-or-later
MANEOF

cat > docs/man/totalupdate.1 << 'MANEOF'
.TH TOTALUPDATE 1 "2025-12-27" "0.1.0" "TotalUpdate Manual"
.SH NAME
totalupdate \- Universal package update daemon
.SH SYNOPSIS
.B totalupdate
[OPTIONS]
.SH DESCRIPTION
TotalUpdate is a background daemon that automatically keeps all your
packages up-to-date across all package managers with safety guarantees.
.SH FEATURES
.IP \(bu 2
Supports 50+ package managers
.IP \(bu 2
aria2 parallel downloads
.IP \(bu 2
IPFS decentralized package distribution
.IP \(bu 2
Strategy engine: whitelist/blacklist/pinning
.IP \(bu 2
Automatic snapshots before updates
.SH AUTHOR
Jonathan D.A. Jewell <jonathan@hyperpolymath.io>
.SH LICENSE
PMPL-1.0-or-later
MANEOF

echo "Generated: docs/man/dnfinition.1"
echo "Generated: docs/man/totalupdate.1"
