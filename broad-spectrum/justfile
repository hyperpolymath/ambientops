# Broad Spectrum Website Auditor - Justfile
# Cross-platform task runner (Deno + ReScript)
# Install: https://github.com/casey/just
# Usage: just <recipe>

# Default recipe (list all recipes)
default:
    @just --list

# Build the project (compile ReScript to JavaScript)
build:
    @echo "Building ReScript modules..."
    rescript build
    @echo "Build complete"

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rescript clean
    rm -rf lib/
    @echo "Clean complete"

# Full rebuild (clean + build)
rebuild: clean build

# Run all tests
test: build
    @echo "Running tests..."
    deno task test
    @echo "All tests passed"

# Audit a single URL
audit URL: build
    deno task audit --url {{URL}}

# Audit a single URL with JSON output
audit-json URL: build
    deno task audit --url {{URL}} --format json

# Audit a single URL with HTML output
audit-html URL OUTPUT="report.html": build
    deno task audit --url {{URL}} --format html > {{OUTPUT}}
    @echo "HTML report saved to {{OUTPUT}}"

# Audit multiple URLs from file
audit-file FILE: build
    deno task audit --file {{FILE}}

# Audit with verbose output
audit-verbose URL: build
    deno task audit --url {{URL}} --verbose

# Watch mode for development
watch:
    rescript build -w

# Format check (dry run)
format-check:
    @echo "Checking code formatting..."
    deno fmt --check
    @echo "Format check passed"

# Format code
format:
    @echo "Formatting code..."
    deno fmt
    @echo "Code formatted"

# Lint check
lint:
    @echo "Linting code..."
    deno lint
    @echo "Lint check passed"

# Type check (ReScript compilation)
typecheck:
    @echo "Type checking..."
    rescript build
    @echo "Type check passed"

# Run all quality checks
check: format-check lint typecheck test
    @echo "All quality checks passed"

# Generate documentation
docs:
    @echo "Documentation is in:"
    @echo "  - README.adoc (user guide)"
    @echo "  - ARCHITECTURE.md (design docs)"
    @echo "  - CONTRIBUTING.md (contributor guide)"
    @echo "  - API documentation: See source code comments"

# Show project statistics
stats:
    @echo "Project Statistics:"
    @echo "=================="
    @echo ""
    @echo "ReScript Modules:"
    @find src -name "*.res" | wc -l
    @echo ""
    @echo "Lines of ReScript Code:"
    @find src -name "*.res" | xargs wc -l | tail -1
    @echo ""
    @echo "Test Files:"
    @find tests -name "*.res" 2>/dev/null | wc -l
    @echo ""
    @echo "Documentation Files:"
    @find . -maxdepth 1 \( -name "*.md" -o -name "*.adoc" \) | wc -l

# Validate required documentation
validate-docs:
    @echo "Validating documentation..."
    @test -f README.adoc && echo "README.adoc exists"
    @test -f LICENSE.txt && echo "LICENSE.txt exists"
    @test -f SECURITY.md && echo "SECURITY.md exists"
    @test -f CONTRIBUTING.md && echo "CONTRIBUTING.md exists"
    @test -f CODE_OF_CONDUCT.md && echo "CODE_OF_CONDUCT.md exists"
    @test -f MAINTAINERS.md && echo "MAINTAINERS.md exists"
    @test -f CHANGELOG.md && echo "CHANGELOG.md exists"
    @test -f ARCHITECTURE.md && echo "ARCHITECTURE.md exists"

# Full validation
validate: validate-docs check
    @echo "All validation checks passed"

# Example audit (uses example.com)
example: build
    just audit "https://example.com"

# Example with all formats
example-all: build
    @echo "Console output:"
    just audit "https://example.com"
    @echo ""
    @echo "JSON output:"
    just audit-json "https://example.com"
    @echo ""
    @echo "HTML output (saved to example-report.html):"
    just audit-html "https://example.com" "example-report.html"

# Clean everything (including node_modules for ReScript compiler deps)
clean-all: clean
    @echo "Removing node_modules..."
    rm -rf node_modules/
    @echo "All clean"

# Setup development environment
setup:
    @echo "Installing ReScript compiler dependencies..."
    npm install --save-dev @rescript/core rescript gentype
    @echo "Building project..."
    just build
    @echo "Development environment ready"
    @echo "Run 'just test' to verify everything works"

# Run a quick health check
health:
    @echo "Running health check..."
    @echo "Deno version:"
    @deno --version | head -1
    @echo "ReScript compiler:"
    @npx rescript -version 2>/dev/null || echo "Run 'just setup' first"
    @echo "Health check complete"

# Show RSR compliance status
rsr-status:
    @echo "RSR Compliance Status"
    @echo "===================="
    @echo ""
    @echo "Documentation:"
    @test -f README.adoc && echo "  README.adoc" || echo "  README.adoc (missing)"
    @test -f LICENSE.txt && echo "  LICENSE.txt" || echo "  LICENSE.txt (missing)"
    @test -f SECURITY.md && echo "  SECURITY.md" || echo "  SECURITY.md (missing)"
    @test -f CONTRIBUTING.md && echo "  CONTRIBUTING.md" || echo "  CONTRIBUTING.md (missing)"
    @test -f CODE_OF_CONDUCT.md && echo "  CODE_OF_CONDUCT.md" || echo "  CODE_OF_CONDUCT.md (missing)"
    @test -f CHANGELOG.md && echo "  CHANGELOG.md" || echo "  CHANGELOG.md (missing)"
    @echo ""
    @echo "Build System:"
    @test -f rescript.json && echo "  rescript.json" || echo "  rescript.json (missing)"
    @test -f deno.json && echo "  deno.json" || echo "  deno.json (missing)"
    @test -f justfile && echo "  justfile" || echo "  justfile (missing)"
    @test -f Mustfile.ncl && echo "  Mustfile.ncl" || echo "  Mustfile.ncl (missing)"
    @echo ""
    @echo "Language Policy:"
    @echo "  ReScript only (no TypeScript)"
    @echo "  Deno only (no npm/bun runtime)"

# Help message
help:
    @echo "Broad Spectrum Website Auditor - Task Runner"
    @echo ""
    @echo "Common Commands:"
    @echo "  just build           - Build the project"
    @echo "  just test            - Run all tests"
    @echo "  just audit URL       - Audit a website"
    @echo "  just check           - Run all quality checks"
    @echo "  just validate        - Validate documentation"
    @echo ""
    @echo "For full list of commands: just --list"
    @echo "For detailed help: just --help"
