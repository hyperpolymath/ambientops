# SPDX-License-Identifier: PMPL-1.0-or-later
# zig-ffi monorepo justfile
# Copyright (c) 2024-2026 Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>

# List all available recipes
default:
    @just --list

# Build a specific bridge (e.g., just build-bridge rust)
build-bridge name:
    cd bridges/{{name}} && zig build

# Build a specific integration (e.g., just build-integration libgit2)
build-integration name:
    cd integrations/{{name}} && zig build

# Test a specific bridge
test-bridge name:
    cd bridges/{{name}} && zig build test

# Test a specific integration
test-integration name:
    cd integrations/{{name}} && zig build test

# Build all bridges
build-all-bridges:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in bridges/*/; do
        name=$(basename "$dir")
        if [ -f "$dir/build.zig" ]; then
            echo "Building bridge: $name"
            (cd "$dir" && zig build) || echo "WARN: $name build failed"
        else
            echo "SKIP: $name (no build.zig)"
        fi
    done

# Build all integrations
build-all-integrations:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in integrations/*/; do
        name=$(basename "$dir")
        if [ -f "$dir/build.zig" ]; then
            echo "Building integration: $name"
            (cd "$dir" && zig build) || echo "WARN: $name build failed"
        else
            echo "SKIP: $name (no build.zig)"
        fi
    done

# Build everything
build-all: build-all-bridges build-all-integrations

# Test all bridges
test-all-bridges:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in bridges/*/; do
        name=$(basename "$dir")
        if [ -f "$dir/build.zig" ]; then
            echo "Testing bridge: $name"
            (cd "$dir" && zig build test) || echo "WARN: $name tests failed"
        fi
    done

# Test all integrations
test-all-integrations:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in integrations/*/; do
        name=$(basename "$dir")
        if [ -f "$dir/build.zig" ]; then
            echo "Testing integration: $name"
            (cd "$dir" && zig build test) || echo "WARN: $name tests failed"
        fi
    done

# Test everything
test-all: test-all-bridges test-all-integrations

# Clean all build artifacts
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -name ".zig-cache" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "zig-out" -type d -exec rm -rf {} + 2>/dev/null || true
    echo "Cleaned all .zig-cache and zig-out directories"

# List all sub-projects with their status
status:
    #!/usr/bin/env bash
    echo "=== Bridges ==="
    for dir in bridges/*/; do
        name=$(basename "$dir")
        has_build=$([ -f "$dir/build.zig" ] && echo "buildable" || echo "no build.zig")
        echo "  $name: $has_build"
    done
    echo ""
    echo "=== Integrations ==="
    for dir in integrations/*/; do
        name=$(basename "$dir")
        has_build=$([ -f "$dir/build.zig" ] && echo "buildable" || echo "no build.zig")
        echo "  $name: $has_build"
    done
