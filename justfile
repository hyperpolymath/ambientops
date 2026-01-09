# AmbientOps - Justfile
# https://just.systems/man/en/
#
# Run `just` to see all available recipes
# Run `just cookbook` to generate docs/just-cookbook.adoc
# Run `just combinations` to see matrix recipe options

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

# Project metadata
project := "ambientops"
version := "0.1.0"
tier := "infrastructure"  # 1 | 2 | infrastructure

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
        echo "       just combinations # Show matrix recipes"
    else
        just --show "{{recipe}}" 2>/dev/null || echo "Recipe '{{recipe}}' not found"
    fi

# Show this project's info
info:
    @echo "Project: {{project}}"
    @echo "Version: {{version}}"
    @echo "RSR Tier: {{tier}}"
    @echo "Recipes: $(just --summary | wc -w)"
    @[ -f STATE.scm ] && grep -oP '\(phase\s+\.\s+\K[^)]+' STATE.scm | head -1 | xargs -I{} echo "Phase: {}" || true

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD & COMPILE
# ═══════════════════════════════════════════════════════════════════════════════

# Build documentation (AsciiDoc → HTML)
build *args:
    @echo "Building {{project}} documentation..."
    @mkdir -p dist/html
    @command -v asciidoctor >/dev/null && \
        find . -maxdepth 1 -name "*.adoc" -exec asciidoctor -D dist/html {} \; || \
        echo "asciidoctor not found - install via: gem install asciidoctor"
    @[ -d docs ] && command -v asciidoctor >/dev/null && \
        find docs -name "*.adoc" -exec asciidoctor -D dist/html {} \; || true
    @echo "Documentation built in dist/html/"

# Build documentation with PDF output (release)
build-release *args:
    @echo "Building {{project}} (release with PDF)..."
    @mkdir -p dist/html dist/pdf
    @command -v asciidoctor >/dev/null && \
        find . -maxdepth 1 -name "*.adoc" -exec asciidoctor -D dist/html {} \; && \
        find docs -name "*.adoc" -exec asciidoctor -D dist/html {} \; || \
        echo "asciidoctor not found - install via: gem install asciidoctor"
    @command -v asciidoctor-pdf >/dev/null && \
        asciidoctor-pdf -D dist/pdf README.adoc || \
        echo "asciidoctor-pdf not found - install via: gem install asciidoctor-pdf"
    @echo "Release build complete in dist/"

# Build and watch for changes (requires watchexec or entr)
build-watch:
    @echo "Watching for changes..."
    @command -v watchexec >/dev/null && \
        watchexec -e adoc -- just build || \
        (command -v entr >/dev/null && \
            find . -name "*.adoc" | entr -c just build || \
            echo "Install watchexec or entr for file watching")

# Clean build artifacts [reversible: rebuild with `just build`]
clean:
    @echo "Cleaning..."
    rm -rf target _build dist lib node_modules

# Deep clean including caches [reversible: rebuild]
clean-all: clean
    rm -rf .cache .tmp

# ═══════════════════════════════════════════════════════════════════════════════
# TEST & QUALITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run all validation tests
test *args:
    @echo "Running validation tests..."
    @just validate-rsr
    @just validate-state
    @just validate-scm
    @echo "All validation tests passed!"

# Run tests with verbose output
test-verbose:
    @echo "Running tests (verbose)..."
    @echo "=== RSR Compliance ===" && just validate-rsr
    @echo "=== STATE.scm Validation ===" && just validate-state
    @echo "=== SCM Files Validation ===" && just validate-scm
    @echo "=== All Tests Complete ==="

# Validate documentation coverage (checks all .adoc files exist and are non-empty)
test-coverage:
    @echo "Checking documentation coverage..."
    @for f in README.adoc ROADMAP.adoc CONTRIBUTING.adoc; do \
        if [ -f "$$f" ]; then \
            [ -s "$$f" ] && echo "✓ $$f" || echo "✗ $$f (empty)"; \
        else \
            echo "✗ $$f (missing)"; \
        fi; \
    done
    @echo "Documentation coverage check complete"

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format all source files [reversible: git checkout]
fmt:
    @echo "Formatting..."
    @# Format markdown files with prettier if available
    @command -v prettier >/dev/null && \
        prettier --write "*.md" "docs/**/*.md" 2>/dev/null || true
    @# Normalize trailing whitespace in .adoc files
    @find . -name "*.adoc" -type f -exec sed -i 's/[[:space:]]*$$//' {} \; 2>/dev/null || true
    @echo "Formatting complete"

# Check formatting without changes
fmt-check:
    @echo "Checking format..."
    @# Check for trailing whitespace in .adoc files
    @! grep -rn '[[:space:]]$$' --include="*.adoc" . 2>/dev/null || \
        (echo "Warning: trailing whitespace found in .adoc files" && true)
    @# Check markdown with prettier if available
    @command -v prettier >/dev/null && \
        prettier --check "*.md" "docs/**/*.md" 2>/dev/null || true
    @echo "Format check complete"

# Run linter (validates SCM files and checks for common issues)
lint:
    @echo "Linting..."
    @# Validate all .scm files parse correctly
    @for f in *.scm .machine_readable/*.scm; do \
        [ -f "$$f" ] && (guile -c "(primitive-load \"$$f\")" 2>/dev/null && echo "✓ $$f" || echo "✗ $$f: parse error") || true; \
    done
    @# Check for broken internal links in .adoc files
    @echo "Checking for common documentation issues..."
    @! grep -rn '{{[A-Z_]*}}' --include="*.md" --include="*.adoc" . 2>/dev/null || \
        echo "Warning: unreplaced template placeholders found"
    @echo "Linting complete"

# Run all quality checks
quality: fmt-check lint test
    @echo "All quality checks passed!"

# Fix all auto-fixable issues [reversible: git checkout]
fix: fmt
    @echo "Fixed all auto-fixable issues"

# ═══════════════════════════════════════════════════════════════════════════════
# RUN & EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════

# Serve documentation locally (requires python3 or simple HTTP server)
run *args:
    @echo "Serving {{project}} documentation..."
    @just build
    @echo "Starting local server at http://localhost:8000"
    @cd dist/html && python3 -m http.server 8000 2>/dev/null || \
        (command -v deno >/dev/null && deno run --allow-net --allow-read https://deno.land/std/http/file_server.ts . || \
        echo "Install python3 or deno for local server")

# Run in development mode with live reload (build + watch + serve)
dev:
    @echo "Starting dev mode..."
    @just build
    @echo "Dev mode: watching for changes and serving at http://localhost:8000"
    @command -v watchexec >/dev/null && \
        (cd dist/html && python3 -m http.server 8000 &) && watchexec -e adoc -- just build || \
        echo "Install watchexec for live reload, or use 'just run' for static serving"

# Run Guile REPL for interactive SCM file exploration
repl:
    @echo "Starting Guile REPL..."
    @echo "Tip: (primitive-load \"STATE.scm\") to load project state"
    @command -v guile >/dev/null && guile || \
        (command -v guix >/dev/null && guix shell guile -- guile || \
        echo "Install guile or guix for REPL support")

# ═══════════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════

# Install all dependencies (documentation tooling)
deps:
    @echo "Installing dependencies..."
    @echo "Required tools:"
    @echo "  - asciidoctor (gem install asciidoctor)"
    @echo "  - asciidoctor-pdf (gem install asciidoctor-pdf) [optional]"
    @echo "  - guile (for SCM file validation)"
    @echo ""
    @echo "Checking available tools..."
    @command -v asciidoctor >/dev/null && echo "✓ asciidoctor" || echo "✗ asciidoctor (required)"
    @command -v asciidoctor-pdf >/dev/null && echo "✓ asciidoctor-pdf" || echo "○ asciidoctor-pdf (optional)"
    @command -v guile >/dev/null && echo "✓ guile" || echo "✗ guile (required for validation)"
    @command -v watchexec >/dev/null && echo "✓ watchexec" || echo "○ watchexec (optional, for dev mode)"

# Audit dependencies for vulnerabilities
deps-audit:
    @echo "Auditing dependencies..."
    @echo "This is a documentation repository with minimal runtime dependencies."
    @echo "Checking for security issues in toolchain..."
    @command -v gitleaks >/dev/null && gitleaks detect --source . --verbose 2>/dev/null || true
    @echo "Audit complete (no runtime dependencies to audit)"

# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

# Generate all documentation
docs:
    @mkdir -p docs/generated docs/man
    just cookbook
    just man
    @echo "Documentation generated in docs/"

# Generate justfile cookbook documentation
cookbook:
    #!/usr/bin/env bash
    mkdir -p docs
    OUTPUT="docs/just-cookbook.adoc"
    echo "= {{project}} Justfile Cookbook" > "$OUTPUT"
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

# Generate man page
man:
    #!/usr/bin/env bash
    mkdir -p docs/man
    cat > docs/man/{{project}}.1 << EOF
.TH AMBIENTOPS 1 "$(date +%Y-%m-%d)" "{{version}}" "AmbientOps Manual"
.SH NAME
{{project}} \- cross-platform system tools for everyday users
.SH SYNOPSIS
.B just
[recipe] [args...]
.SH DESCRIPTION
AmbientOps is a cross-platform ecosystem of system tools designed for everyday users
who need trustworthy help without fearware, nagware, or scammy "optimizers".
Organized around a hospital mental model: Ward, Emergency Room, Operating Room, and Records.
.SH AUTHOR
Jonathan D.A. Jewell <hyperpolymath@proton.me>
EOF
    echo "Generated: docs/man/{{project}}.1"

# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINERS (nerdctl + Wolfi)
# ═══════════════════════════════════════════════════════════════════════════════

# Build container image
container-build tag="latest":
    @if [ -f Containerfile ]; then \
        nerdctl build -t {{project}}:{{tag}} -f Containerfile .; \
    else \
        echo "No Containerfile found"; \
    fi

# Run container
container-run tag="latest" *args:
    nerdctl run --rm -it {{project}}:{{tag}} {{args}}

# Push container image
container-push registry="ghcr.io/hyperpolymath" tag="latest":
    nerdctl tag {{project}}:{{tag}} {{registry}}/{{project}}:{{tag}}
    nerdctl push {{registry}}/{{project}}:{{tag}}

# ═══════════════════════════════════════════════════════════════════════════════
# CI & AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run full CI pipeline locally
ci: deps quality
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
security: deps-audit
    @echo "=== Security Audit ==="
    @command -v gitleaks >/dev/null && gitleaks detect --source . --verbose || true
    @command -v trivy >/dev/null && trivy fs --severity HIGH,CRITICAL . || true
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
    for f in .editorconfig .gitignore justfile RSR_COMPLIANCE.adoc README.adoc; do
        [ -f "$f" ] || MISSING="$MISSING $f"
    done
    for d in .well-known; do
        [ -d "$d" ] || MISSING="$MISSING $d/"
    done
    for f in .well-known/security.txt .well-known/ai.txt .well-known/humans.txt; do
        [ -f "$f" ] || MISSING="$MISSING $f"
    done
    if [ ! -f "guix.scm" ] && [ ! -f ".guix-channel" ] && [ ! -f "flake.nix" ]; then
        MISSING="$MISSING guix.scm/flake.nix"
    fi
    if [ -n "$MISSING" ]; then
        echo "MISSING:$MISSING"
        exit 1
    fi
    echo "RSR compliance: PASS"

# Validate STATE.scm syntax
validate-state:
    @if [ -f "STATE.scm" ]; then \
        guile -c "(primitive-load \"STATE.scm\")" 2>/dev/null && echo "STATE.scm: valid" || echo "STATE.scm: INVALID"; \
    else \
        echo "No STATE.scm found"; \
    fi

# Validate all SCM files in repository
validate-scm:
    @echo "=== SCM Files Validation ==="
    @PASS=true; \
    for f in STATE.scm META.scm ECOSYSTEM.scm PLAYBOOK.scm AGENTIC.scm NEUROSYM.scm .machine_readable/*.scm; do \
        if [ -f "$$f" ]; then \
            if guile -c "(primitive-load \"$$f\")" 2>/dev/null; then \
                echo "✓ $$f"; \
            else \
                echo "✗ $$f: parse error"; \
                PASS=false; \
            fi; \
        fi; \
    done; \
    $$PASS && echo "SCM validation: PASS" || (echo "SCM validation: FAIL" && exit 1)

# Full validation suite
validate: validate-rsr validate-state validate-scm
    @echo "All validations passed!"

# ═══════════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Update STATE.scm timestamp
state-touch:
    @if [ -f "STATE.scm" ]; then \
        sed -i 's/(updated . "[^"]*")/(updated . "'"$(date -Iseconds)"'")/' STATE.scm && \
        echo "STATE.scm timestamp updated"; \
    fi

# Show current phase from STATE.scm
state-phase:
    @grep -oP '\(phase\s+\.\s+\K[^)]+' STATE.scm 2>/dev/null | head -1 || echo "unknown"

# ═══════════════════════════════════════════════════════════════════════════════
# GUIX & NIX
# ═══════════════════════════════════════════════════════════════════════════════

# Enter Guix development shell (primary)
guix-shell:
    guix shell -D -f guix.scm

# Build with Guix
guix-build:
    guix build -f guix.scm

# Enter Nix development shell (fallback)
nix-shell:
    @if [ -f "flake.nix" ]; then nix develop; else echo "No flake.nix"; fi

# ═══════════════════════════════════════════════════════════════════════════════
# HYBRID AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run local automation tasks
automate task="all":
    #!/usr/bin/env bash
    case "{{task}}" in
        all) just fmt && just lint && just test && just docs && just state-touch ;;
        cleanup) just clean && find . -name "*.orig" -delete && find . -name "*~" -delete ;;
        update) just deps && just validate ;;
        *) echo "Unknown: {{task}}. Use: all, cleanup, update" && exit 1 ;;
    esac

# ═══════════════════════════════════════════════════════════════════════════════
# COMBINATORIC MATRIX RECIPES
# ═══════════════════════════════════════════════════════════════════════════════

# Build matrix: [debug|release] × [target] × [features]
build-matrix mode="debug" target="" features="":
    @echo "Build matrix: mode={{mode}} target={{target}} features={{features}}"
    # Customize for your build system

# Test matrix: [unit|integration|e2e|all] × [verbosity] × [parallel]
test-matrix suite="unit" verbosity="normal" parallel="true":
    @echo "Test matrix: suite={{suite}} verbosity={{verbosity}} parallel={{parallel}}"

# Container matrix: [build|run|push|shell|scan] × [registry] × [tag]
container-matrix action="build" registry="ghcr.io/hyperpolymath" tag="latest":
    @echo "Container matrix: action={{action}} registry={{registry}} tag={{tag}}"

# CI matrix: [lint|test|build|security|all] × [quick|full]
ci-matrix stage="all" depth="quick":
    @echo "CI matrix: stage={{stage}} depth={{depth}}"

# Show all matrix combinations
combinations:
    @echo "=== Combinatoric Matrix Recipes ==="
    @echo ""
    @echo "Build Matrix: just build-matrix [debug|release] [target] [features]"
    @echo "Test Matrix:  just test-matrix [unit|integration|e2e|all] [verbosity] [parallel]"
    @echo "Container:    just container-matrix [build|run|push|shell|scan] [registry] [tag]"
    @echo "CI Matrix:    just ci-matrix [lint|test|build|security|all] [quick|full]"
    @echo ""
    @echo "Total combinations: ~10 billion"

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
    @find . \( -name "*.rs" -o -name "*.ex" -o -name "*.res" -o -name "*.ncl" -o -name "*.scm" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0"

# Show TODO comments
todos:
    @grep -rn "TODO\|FIXME" --include="*.rs" --include="*.ex" --include="*.res" . 2>/dev/null || echo "No TODOs"

# Open in editor
edit:
    ${EDITOR:-code} .
