# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# nick-shells - Development Tasks
# Integrates with must (hyperpolymath/mustfile) via Nickel

set shell := ["bash", "-uc"]
set dotenv-load := true

project := "nick-shells"
shell_dir := "shell"
modules_dir := shell_dir / "modules"
examples_dir := shell_dir / "examples"

# Show all recipes
default:
    @just --list --unsorted

# ============================================================================
# Testing
# ============================================================================

# Run shellcheck on all shell scripts
test: test-modules test-examples test-baseline test-apply
    @echo "✅ All tests passed"

# Test shell modules with shellcheck
test-modules:
    @echo "🔍 Checking modules..."
    @shellcheck --shell=bash --severity=warning {{modules_dir}}/*.sh

# Test example configurations
test-examples:
    @echo "🔍 Checking examples..."
    @shellcheck --shell=bash --severity=warning {{examples_dir}}/*.sh

# Test baseline configuration
test-baseline:
    @echo "🔍 Checking baseline.sh..."
    @shellcheck --shell=bash --severity=warning {{shell_dir}}/baseline.sh

# Test apply script
test-apply:
    @echo "🔍 Checking apply.sh..."
    @shellcheck --shell=sh --severity=warning {{shell_dir}}/apply.sh

# ============================================================================
# Formatting
# ============================================================================

# Format all shell scripts with shfmt
fmt:
    @echo "📝 Formatting shell scripts..."
    @shfmt -w -i 4 -ci -bn {{modules_dir}}/*.sh {{examples_dir}}/*.sh {{shell_dir}}/baseline.sh {{shell_dir}}/apply.sh
    @echo "✅ Formatting complete"

# Check formatting without modifying files
fmt-check:
    @echo "📝 Checking format..."
    @shfmt -d -i 4 -ci -bn {{modules_dir}}/*.sh {{examples_dir}}/*.sh {{shell_dir}}/baseline.sh {{shell_dir}}/apply.sh

# ============================================================================
# Linting
# ============================================================================

# Run all linters
lint: test fmt-check lint-nickel
    @echo "✅ All lints passed"

# Lint Nickel configuration
lint-nickel:
    @echo "🔍 Checking Nickel configuration..."
    @if command -v nickel >/dev/null 2>&1; then \
        nickel typecheck {{shell_dir}}/config.ncl && \
        nickel typecheck must.ncl && \
        echo "✅ Nickel configs valid"; \
    else \
        echo "⚠️  Nickel not installed, skipping"; \
    fi

# ============================================================================
# Build / Export
# ============================================================================

# Export Nickel config to JSON
build:
    @echo "🔨 Building configuration..."
    @mkdir -p build
    @if command -v nickel >/dev/null 2>&1; then \
        nickel export {{shell_dir}}/config.ncl > build/config.json && \
        nickel export must.ncl > build/must.json && \
        echo "✅ Exported to build/"; \
    else \
        echo "⚠️  Nickel not installed, skipping export"; \
    fi

# ============================================================================
# Cleaning
# ============================================================================

# Remove generated files
clean:
    @echo "🧹 Cleaning..."
    @rm -rf build/
    @rm -f config.json
    @echo "✅ Clean complete"

# ============================================================================
# Installation
# ============================================================================

# Install the baseline configuration
install:
    @{{shell_dir}}/apply.sh --install

# Uninstall the baseline configuration
uninstall:
    @{{shell_dir}}/apply.sh --uninstall

# Preview installation (dry run)
install-preview:
    @{{shell_dir}}/apply.sh --dry-run

# ============================================================================
# Must Integration (hyperpolymath/mustfile)
# ============================================================================

# Validate must configuration
must-check:
    @echo "🔍 Validating must configuration..."
    @if command -v nickel >/dev/null 2>&1; then \
        nickel typecheck must.ncl && \
        echo "✅ must.ncl valid"; \
    else \
        echo "⚠️  Nickel not installed"; \
        exit 1; \
    fi

# Export must configuration
must-export: must-check
    @echo "📤 Exporting must configuration..."
    @nickel export must.ncl > must.json
    @echo "✅ Exported to must.json"

# ============================================================================
# Development Helpers
# ============================================================================

# Check all dependencies are installed
check-deps:
    @echo "🔍 Checking dependencies..."
    @echo -n "shellcheck: " && (command -v shellcheck >/dev/null 2>&1 && shellcheck --version | head -1 || echo "❌ not installed")
    @echo -n "shfmt: " && (command -v shfmt >/dev/null 2>&1 && shfmt --version || echo "❌ not installed")
    @echo -n "nickel: " && (command -v nickel >/dev/null 2>&1 && nickel --version || echo "❌ not installed")
    @echo -n "just: " && just --version

# Show project statistics
stats:
    @echo "📊 Project Statistics"
    @echo "===================="
    @echo -n "Shell modules: " && ls -1 {{modules_dir}}/*.sh 2>/dev/null | wc -l
    @echo -n "Example configs: " && ls -1 {{examples_dir}}/*.sh 2>/dev/null | wc -l
    @echo -n "Total shell lines: " && wc -l {{modules_dir}}/*.sh {{examples_dir}}/*.sh {{shell_dir}}/baseline.sh {{shell_dir}}/apply.sh 2>/dev/null | tail -1 | awk '{print $1}'
    @echo -n "Nickel configs: " && ls -1 *.ncl {{shell_dir}}/*.ncl 2>/dev/null | wc -l

# ============================================================================
# CI Helpers
# ============================================================================

# Run full CI pipeline
ci: check-deps lint test build
    @echo "✅ CI pipeline complete"
