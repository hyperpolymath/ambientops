# SPDX-License-Identifier: PMPL-1.0-or-later
# AmbientOps unified build and test orchestration

set shell := ["bash", "-euo", "pipefail", "-c"]

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
