# TotalUpdate & DNFinition - Universal Package Management
# https://just.systems/man/en/
#
# TotalUpdate: Automated background daemon for keeping everything up-to-date
# DNFinition: Interactive TUI package manager with reversibility
#
# Run `just` to see all available recipes
# Run `just build` to build all components

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

# Project metadata
project := "totalupdate"
version := "0.1.0"
tier := "infrastructure"

# Build configuration
ada_mode := env_var_or_default("BUILD_MODE", "debug")

# ═══════════════════════════════════════════════════════════════════════════════
# DEFAULT & HELP
# ═══════════════════════════════════════════════════════════════════════════════

# Show all available recipes with descriptions
default:
    @just --list --unsorted

# Show detailed help for a specific recipe
help recipe="":
    #!/usr/bin/env bash
    if [ -z "{{recipe}}" ]; then
        just --list --unsorted
        echo ""
        echo "Usage: just help <recipe>"
        echo "       just cookbook     # Generate full documentation"
    else
        just --show "{{recipe}}" 2>/dev/null || echo "Recipe '{{recipe}}' not found"
    fi

# Show this project's info
info:
    @echo "╔═══════════════════════════════════════════════════════════╗"
    @echo "║  TotalUpdate & DNFinition                                ║"
    @echo "║  Universal Package Management with Reversibility         ║"
    @echo "╚═══════════════════════════════════════════════════════════╝"
    @echo ""
    @echo "Version: {{version}}"
    @echo "Build Mode: {{ada_mode}}"
    @echo ""
    @echo "Components:"
    @echo "  DNFinition  - TUI package manager (Ada 2022 + ncurses)"
    @echo "  TotalUpdate - Background update daemon (Elixir/OTP)"

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD & COMPILE
# ═══════════════════════════════════════════════════════════════════════════════

# Build everything (DNFinition + TotalUpdate)
build: build-dnfinition build-totalupdate
    @echo "Build complete!"

# Build DNFinition (Ada TUI)
build-dnfinition:
    @echo "Building DNFinition (Ada)..."
    @mkdir -p ada/dnfinition/obj ada/dnfinition/bin
    cd ada/dnfinition && gprbuild -P dnfinition.gpr -XBUILD_MODE={{ada_mode}} -j0

# Build TotalUpdate (Elixir daemon)
build-totalupdate: build-dnfinition
    @echo "Building TotalUpdate (Elixir)..."
    cd elixir/dnfinition && mix deps.get && mix compile
    cd elixir/totalupdate && mix deps.get && mix compile

# Build in release mode with optimizations
build-release:
    BUILD_MODE=release just build

# Build with SPARK verification
build-spark:
    @echo "Building with SPARK verification..."
    @mkdir -p ada/dnfinition/obj ada/dnfinition/bin
    cd ada/dnfinition && gprbuild -P dnfinition.gpr -XBUILD_MODE=spark -j0

# Run SPARK proofs
prove:
    @echo "Running SPARK proofs..."
    cd ada/dnfinition && gnatprove -P dnfinition.gpr --level=2

# Clean build artifacts [reversible: rebuild with `just build`]
clean:
    @echo "Cleaning..."
    rm -rf ada/dnfinition/obj ada/dnfinition/bin
    rm -rf ada/totalupdate/obj ada/totalupdate/bin
    rm -rf elixir/dnfinition/_build elixir/dnfinition/deps
    rm -rf elixir/totalupdate/_build elixir/totalupdate/deps

# Deep clean including caches [reversible: rebuild]
clean-all: clean
    rm -rf .cache .tmp

# ═══════════════════════════════════════════════════════════════════════════════
# TEST & QUALITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run all tests
test: test-ada test-elixir test-skeleton
    @echo "All tests passed!"

# Run Ada tests (AUnit)
test-ada:
    @echo "Running Ada tests..."
    @echo "(Ada tests not yet implemented)"

# Run walking skeleton integration tests
test-skeleton:
    @echo "Running walking skeleton tests..."
    @chmod +x test/skeleton_test.sh
    ./test/skeleton_test.sh

# Run Elixir tests
test-elixir:
    @echo "Running Elixir tests..."
    cd elixir/dnfinition && mix test
    cd elixir/totalupdate && mix test

# Run Elixir dialyzer
dialyzer:
    @echo "Running Dialyzer..."
    cd elixir/dnfinition && mix dialyzer
    cd elixir/totalupdate && mix dialyzer

# Run all quality checks
quality: fmt-check lint test prove
    @echo "All quality checks passed!"

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format all source files [reversible: git checkout]
fmt:
    @echo "Formatting..."
    cd elixir/dnfinition && mix format
    cd elixir/totalupdate && mix format

# Check formatting without changes
fmt-check:
    @echo "Checking format..."
    cd elixir/dnfinition && mix format --check-formatted
    cd elixir/totalupdate && mix format --check-formatted

# Run linter
lint:
    @echo "Linting..."
    cd elixir/dnfinition && mix credo --strict
    cd elixir/totalupdate && mix credo --strict

# ═══════════════════════════════════════════════════════════════════════════════
# RUN & EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════

# Run DNFinition TUI
run-dnfinition *args: build-dnfinition
    @echo "Starting DNFinition..."
    ./ada/dnfinition/bin/dnfinition {{args}}

# Run TotalUpdate daemon
run-totalupdate: build-totalupdate
    @echo "Starting TotalUpdate daemon..."
    cd elixir/totalupdate && mix run --no-halt

# Run DNFinition with Elixir coordinator
run *args: build
    @echo "Starting DNFinition with OTP supervisor..."
    cd elixir/dnfinition && iex -S mix

# Run in development mode
dev:
    @echo "Starting dev mode..."
    cd elixir/dnfinition && iex -S mix

# Run Elixir REPL
repl:
    @echo "Starting Elixir REPL..."
    cd elixir/dnfinition && iex -S mix

# ═══════════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════

# Install all dependencies
deps:
    @echo "Installing dependencies..."
    @echo "Elixir dependencies:"
    cd elixir/dnfinition && mix deps.get
    cd elixir/totalupdate && mix deps.get

# Check system prerequisites
prereqs:
    #!/usr/bin/env bash
    echo "Checking prerequisites..."
    MISSING=""

    # Ada/GNAT
    command -v gnat >/dev/null || MISSING="$MISSING gnat"
    command -v gprbuild >/dev/null || MISSING="$MISSING gprbuild"
    command -v gnatprove >/dev/null || echo "  gnatprove not found (optional for SPARK proofs)"

    # Elixir
    command -v elixir >/dev/null || MISSING="$MISSING elixir"
    command -v mix >/dev/null || MISSING="$MISSING mix"

    # ncurses
    pkg-config --exists ncurses 2>/dev/null || MISSING="$MISSING ncurses-devel"

    # Optional tools
    command -v aria2c >/dev/null || echo "  aria2 not found (optional for parallel downloads)"
    command -v ipfs >/dev/null || echo "  kubo/ipfs not found (optional for IPFS support)"

    if [ -n "$MISSING" ]; then
        echo ""
        echo "Missing required packages:$MISSING"
        echo ""
        echo "Install on Fedora:  sudo dnf install$MISSING"
        echo "Install on Debian:  sudo apt install$MISSING"
        echo "Install on Arch:    sudo pacman -S$MISSING"
        exit 1
    fi
    echo "All prerequisites satisfied!"

# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

# Generate all documentation
docs:
    @mkdir -p docs/generated docs/man docs/api
    just cookbook
    just man
    cd elixir/dnfinition && mix docs
    cd elixir/totalupdate && mix docs
    @echo "Documentation generated in docs/"

# Generate justfile cookbook documentation
cookbook:
    #!/usr/bin/env bash
    mkdir -p docs
    OUTPUT="docs/just-cookbook.adoc"
    echo "= TotalUpdate & DNFinition Justfile Cookbook" > "$OUTPUT"
    echo ":toc: left" >> "$OUTPUT"
    echo ":toclevels: 3" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "Generated: $(date -Iseconds)" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "== Recipes" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    just --list --unsorted | while read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([a-z_-]+) ]]; then
            recipe="${BASH_REMATCH[1]}"
            echo "=== $recipe" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
            echo "[source,bash]" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "just $recipe" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
        fi
    done
    echo "Generated: $OUTPUT"

# Generate man pages
man:
    #!/usr/bin/env bash
    mkdir -p docs/man
    cat > docs/man/dnfinition.1 << 'EOF'
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
AGPL-3.0-or-later
EOF

    cat > docs/man/totalupdate.1 << 'EOF'
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
AGPL-3.0-or-later
EOF
    echo "Generated: docs/man/dnfinition.1"
    echo "Generated: docs/man/totalupdate.1"

# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINERS (Podman)
# ═══════════════════════════════════════════════════════════════════════════════

# Build container image
container-build tag="latest":
    @if [ -f Containerfile ]; then \
        podman build -t {{project}}:{{tag}} -f Containerfile .; \
    else \
        echo "No Containerfile found"; \
    fi

# Run container
container-run tag="latest" *args:
    podman run --rm -it {{project}}:{{tag}} {{args}}

# Push container image
container-push registry="ghcr.io/hyperpolymath" tag="latest":
    podman tag {{project}}:{{tag}} {{registry}}/{{project}}:{{tag}}
    podman push {{registry}}/{{project}}:{{tag}}

# ═══════════════════════════════════════════════════════════════════════════════
# CI & AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run full CI pipeline locally
ci: prereqs deps build quality
    @echo "CI pipeline complete!"

# Install git hooks
install-hooks:
    @mkdir -p .git/hooks
    @cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
just fmt-check || exit 1
just lint || exit 1
EOF
    @chmod +x .git/hooks/pre-commit
    @echo "Git hooks installed"

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run security audit
security:
    @echo "=== Security Audit ==="
    cd elixir/dnfinition && mix deps.audit
    cd elixir/totalupdate && mix deps.audit
    @command -v gitleaks >/dev/null && gitleaks detect --source . --verbose || true
    @echo "Security audit complete"

# Generate SBOM
sbom:
    @mkdir -p docs/security
    @command -v syft >/dev/null && syft . -o spdx-json > docs/security/sbom.spdx.json || echo "syft not found"

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATION & COMPLIANCE
# ═══════════════════════════════════════════════════════════════════════════════

# Validate RSR compliance
validate-rsr:
    #!/usr/bin/env bash
    echo "=== RSR Compliance Check ==="
    MISSING=""
    for f in .editorconfig .gitignore justfile README.adoc; do
        [ -f "$f" ] || MISSING="$MISSING $f"
    done
    if [ -n "$MISSING" ]; then
        echo "MISSING:$MISSING"
        exit 1
    fi
    echo "RSR compliance: PASS"

# Full validation suite
validate: validate-rsr
    @echo "All validations passed!"

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION CONTROL
# ═══════════════════════════════════════════════════════════════════════════════

# Show git status
status:
    @git status --short

# Show recent commits
log count="20":
    @git log --oneline -{{count}}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Count lines of code
loc:
    @echo "Ada:"
    @find ada -name "*.ads" -o -name "*.adb" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0"
    @echo "Elixir:"
    @find elixir -name "*.ex" -o -name "*.exs" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0"

# Show TODO comments
todos:
    @echo "=== TODOs ==="
    @grep -rn "TODO\|FIXME" --include="*.ads" --include="*.adb" --include="*.ex" . 2>/dev/null || echo "No TODOs"

# Open in editor
edit:
    ${EDITOR:-code} .

# ═══════════════════════════════════════════════════════════════════════════════
# INSTALL
# ═══════════════════════════════════════════════════════════════════════════════

# Install to ~/.local/bin
install: build-release
    @echo "Installing to ~/.local/bin..."
    @mkdir -p ~/.local/bin
    cp ada/dnfinition/bin/dnfinition ~/.local/bin/
    @echo "Installed: ~/.local/bin/dnfinition"
    @echo ""
    @echo "Make sure ~/.local/bin is in your PATH"

# Uninstall
uninstall:
    rm -f ~/.local/bin/dnfinition
    @echo "Uninstalled dnfinition"
