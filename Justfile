# SPDX-License-Identifier: MPL-2.0
# AmbientOps unified build and test orchestration

set shell := ["bash", "-euo", "pipefail", "-c"]

import? "contractile.just"

repo := justfile_directory()

# Default: show available recipes
default:
    @just --list

# Build all components
build-all: build-rust build-elixir
    @echo "All components built."

# Test all components
test-all: test-rust test-contracts test-elixir
    @echo "All tests passed."

# Build Rust workspace (clinician, hardware-crash-team, contracts-rust)
build-rust:
    cargo build --workspace --manifest-path {{repo}}/Cargo.toml

# Test Rust workspace
test-rust:
    cargo test --workspace --manifest-path {{repo}}/Cargo.toml

# Build Elixir components (observatory, records/referrals)
build-elixir:
    cd {{repo}}/observatory && mix deps.get --quiet && mix compile --no-deps-check
    cd {{repo}}/records/referrals && mix deps.get --quiet && mix compile --no-deps-check

# Test Elixir components
test-elixir:
    cd {{repo}}/observatory && mix deps.get --quiet && mix test
    cd {{repo}}/records/referrals && mix deps.get --quiet && mix test

# Test contract schemas (Deno)
test-contracts:
    cd {{repo}}/contracts && deno test --no-check

# Run hardware scan
scan *ARGS:
    cargo run --manifest-path {{repo}}/Cargo.toml -p hardware-crash-team -- scan {{ARGS}}

# Run hardware scan with contract envelope output
scan-envelope:
    cargo run --manifest-path {{repo}}/Cargo.toml -p hardware-crash-team -- scan --envelope

# Run end-to-end demo
demo:
    {{repo}}/scripts/demo-flow.sh --build

# Check all (no build, just validate)
check:
    cargo check --workspace --manifest-path {{repo}}/Cargo.toml
    cd {{repo}}/contracts && deno check mod.js

# Clean build artifacts
clean:
    cargo clean --manifest-path {{repo}}/Cargo.toml
    rm -rf {{repo}}/observatory/_build
    rm -rf {{repo}}/records/referrals/_build

# Run integration test suite
integration-test:
    {{repo}}/scripts/integration-test.sh

# Synchronize A2ML metadata to SCM (Shadow Sync)
sync-metadata:
    #!/usr/bin/env bash
    echo "Synchronizing metadata (A2ML -> SCM)..."
    if [ -f .machine_readable/STATE.a2ml ]; then
        COMPLETION=$(grep "completion-percentage:" .machine_readable/STATE.a2ml | awk '{print $2}')
        sed -i "s/(overall-completion [0-9]\+)/(overall-completion $COMPLETION)/" .machine_readable/STATE.scm
        echo "✓ Metadata synchronized"
    fi

# --- SECURITY ---

# Run security audit suite
security:
    @echo "=== Security Audit ==="
    @command -v gitleaks >/dev/null && gitleaks detect --source . --verbose || echo "gitleaks not found"
    @command -v trivy >/dev/null && trivy fs --severity HIGH,CRITICAL . || echo "trivy not found"
    @echo "Security audit complete"

# Scan for vulnerabilities in dependencies
audit:
    @echo "=== Dependency Audit ==="
    @if [ -f Cargo.toml ]; then cargo audit; fi
    @echo "Dependency audit complete"

# [AUTO-GENERATED] Multi-arch / RISC-V target
build-riscv:
	@echo "Building for RISC-V..."
	cross build --target riscv64gc-unknown-linux-gnu

# --- PLANNED COMPONENTS (stubs for future use) ---

# Run nvme-sentinel health check
nvme-sentinel *ARGS:
    @echo "nvme-sentinel: NVMe SMART monitoring"
    @echo "Component not yet built — see panll/panels-needed.md for spec"

# Run boot-guardian boot health analysis
boot-guardian *ARGS:
    @echo "boot-guardian: Boot health monitoring"
    @echo "Component not yet built — see panll/panels-needed.md for spec"

# Run service-autopsy on failed services
service-autopsy *ARGS:
    @echo "service-autopsy: Service failure analysis"
    @echo "Component not yet built — see panll/panels-needed.md for spec"

# Run shutdown-marshal for clean shutdown orchestration
shutdown-marshal *ARGS:
    @echo "shutdown-marshal: Shutdown sequencing"
    @echo "Component not yet built"

# Run session-sentinel session health monitor
session-sentinel *ARGS:
    @echo "session-sentinel: Session health monitoring (Ephapax WIP)"
    @echo "Currently disabled locally — see session-sentinel/ for code"

# --- PRE-COMMIT ---

# Run panic-attacker pre-commit scan
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"

# ═══════════════════════════════════════════════════════════════════════════════
# ONBOARDING & DIAGNOSTICS
# ═══════════════════════════════════════════════════════════════════════════════

# Check all required toolchain dependencies and report health
doctor:
    #!/usr/bin/env bash
    echo "═══════════════════════════════════════════════════"
    echo "  AmbientOps Doctor — Toolchain Health Check"
    echo "═══════════════════════════════════════════════════"
    echo ""
    PASS=0; FAIL=0; WARN=0
    check() {
        local name="$1" cmd="$2" min="$3"
        if command -v "$cmd" >/dev/null 2>&1; then
            VER=$("$cmd" --version 2>&1 | head -1)
            echo "  [OK]   $name — $VER"
            PASS=$((PASS + 1))
        else
            echo "  [FAIL] $name — not found (need $min+)"
            FAIL=$((FAIL + 1))
        fi
    }
    check "Rust (cargo)"      cargo     "1.80"
    check "Elixir"            elixir    "1.16"
    check "Erlang (erl)"      erl       "26"
    check "Mix"               mix       "1.16"
    check "V (vlang)"         v         "0.4.4"
    check "Deno"              deno      "2.0"
    check "just"              just      "1.25"
    # Optional tools
    if command -v cross >/dev/null 2>&1; then
        echo "  [OK]   cross (optional) — available for RISC-V builds"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] cross (optional) — not found (needed for RISC-V builds)"
        WARN=$((WARN + 1))
    fi
    if command -v panic-attack >/dev/null 2>&1; then
        echo "  [OK]   panic-attack — available"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] panic-attack — not found (pre-commit scanner)"
        WARN=$((WARN + 1))
    fi
    if command -v gitleaks >/dev/null 2>&1; then
        echo "  [OK]   gitleaks (optional) — available"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] gitleaks (optional) — not found (secret scanning)"
        WARN=$((WARN + 1))
    fi
    if command -v trivy >/dev/null 2>&1; then
        echo "  [OK]   trivy (optional) — available"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] trivy (optional) — not found (vulnerability scanning)"
        WARN=$((WARN + 1))
    fi
    echo ""
    echo "  Result: $PASS passed, $FAIL failed, $WARN warnings"
    if [ "$FAIL" -gt 0 ]; then
        echo "  Run 'just heal' to attempt automatic repair."
        exit 1
    fi
    echo "  All required tools present."

# Attempt to automatically install missing tools
heal:
    #!/usr/bin/env bash
    echo "═══════════════════════════════════════════════════"
    echo "  AmbientOps Heal — Automatic Tool Installation"
    echo "═══════════════════════════════════════════════════"
    echo ""
    if ! command -v cargo >/dev/null 2>&1; then
        echo "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    if ! command -v elixir >/dev/null 2>&1; then
        echo "Elixir not found."
        if command -v asdf >/dev/null 2>&1; then
            echo "  Installing via asdf..."
            asdf install erlang latest
            asdf install elixir latest
        else
            echo "  Install manually: https://elixir-lang.org/install.html"
            echo "  Or via asdf: asdf plugin add elixir && asdf install elixir latest"
        fi
    fi
    if ! command -v v >/dev/null 2>&1; then
        echo "V (vlang) not found."
        if command -v asdf >/dev/null 2>&1; then
            echo "  Installing via asdf..."
            asdf install vlang latest
        else
            echo "  Install manually: https://vlang.io"
        fi
    fi
    if ! command -v deno >/dev/null 2>&1; then
        echo "Installing Deno..."
        curl -fsSL https://deno.land/install.sh | sh
    fi
    if ! command -v just >/dev/null 2>&1; then
        echo "Installing just..."
        cargo install just
    fi
    echo ""
    echo "Heal complete. Run 'just doctor' to verify."

# Guided tour of the project structure and key concepts
tour:
    #!/usr/bin/env bash
    echo "═══════════════════════════════════════════════════"
    echo "  AmbientOps — Guided Tour"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "AmbientOps is a hospital-model operations framework."
    echo "Components are organized by hospital department:"
    echo ""
    echo "  clinician/           (Rust ~4400 LOC)"
    echo "    AI-assisted sysadmin with feature gates:"
    echo "    --features ai       Ollama integration"
    echo "    --features storage  ArangoDB graph traversal"
    echo "    --features p2p      libp2p gossipsub mesh"
    echo ""
    echo "  emergency-room/      (V ~1800 LOC)"
    echo "    Panic-safe intake, evidence envelopes"
    echo ""
    echo "  hardware-crash-team/ (Rust ~700 LOC)"
    echo "    Hardware diagnostics (PCI BAR, lspci, SARIF output)"
    echo "    Origin: Zombie NVIDIA GPU causing 43+ reboots"
    echo ""
    echo "  observatory/         (Elixir ~600 LOC)"
    echo "    Metrics, system weather, monitoring"
    echo ""
    echo "  contracts/           (JSON + Deno)"
    echo "    8 JSON schemas for data backbone"
    echo ""
    echo "  records/referrals/   (Elixir ~400 LOC)"
    echo "    Multi-platform bug reporting"
    echo ""
    echo "Data flow:"
    echo "  ER intake → Evidence Envelope → Procedure Plan → Receipt → System Weather"
    echo ""
    echo "Quick commands:"
    echo "  just build-all     Build everything"
    echo "  just test-all      Run all tests"
    echo "  just scan          Hardware scan"
    echo "  just demo          End-to-end demo"
    echo "  just security      Security audit"
    echo ""
    RUST_LOC=$(find . -name '*.rs' -not -path './target/*' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    echo "Approximate Rust LOC: ${RUST_LOC:-unknown}"
    echo ""
    echo "Read more: QUICKSTART-USER.adoc"

# Show help for common workflows
help-me:
    #!/usr/bin/env bash
    echo "═══════════════════════════════════════════════════"
    echo "  AmbientOps — Common Workflows"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "FIRST TIME SETUP:"
    echo "  just doctor           Check toolchain"
    echo "  just heal             Fix missing tools"
    echo ""
    echo "BUILD:"
    echo "  just build-all        Build Rust + Elixir"
    echo "  just build-rust       Build Rust workspace only"
    echo "  just build-elixir     Build Elixir components only"
    echo ""
    echo "TEST:"
    echo "  just test-all         Run all tests"
    echo "  just test-rust        Rust workspace tests"
    echo "  just test-elixir      Elixir component tests"
    echo "  just test-contracts   Contract schema tests (Deno)"
    echo ""
    echo "HARDWARE DIAGNOSTICS:"
    echo "  just scan             Run hardware scan"
    echo "  just scan-envelope    Scan with contract envelope"
    echo ""
    echo "SECURITY:"
    echo "  just security         Run gitleaks + trivy audit"
    echo "  just audit            Dependency vulnerability audit"
    echo ""
    echo "DEMO:"
    echo "  just demo             End-to-end demo flow"
    echo "  just integration-test Integration test suite"
    echo ""
    echo "PRE-COMMIT:"
    echo "  just assail           Run panic-attacker scan"
    echo ""
    echo "OTHER:"
    echo "  just clean            Clean all build artifacts"
    echo "  just check            Validate without building"
    echo "  just build-riscv      Cross-compile for RISC-V"
    echo ""
    echo "LEARN:"
    echo "  just tour             Guided project tour"
    echo "  just default          List all recipes"


# Print the current CRG grade (reads from READINESS.md '**Current Grade:** X' line)
crg-grade:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    echo "$$grade"

# Generate a shields.io badge markdown for the current CRG grade
# Looks for '**Current Grade:** X' in READINESS.md; falls back to X
crg-badge:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    case "$$grade" in \
      A) color="brightgreen" ;; B) color="green" ;; C) color="yellow" ;; \
      D) color="orange" ;; E) color="red" ;; F) color="critical" ;; \
      *) color="lightgrey" ;; esac; \
    echo "[![CRG $$grade](https://img.shields.io/badge/CRG-$$grade-$$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"
