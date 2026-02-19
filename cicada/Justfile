# justfile for CIcaDA - Palimpsest Crypto Identity
# https://github.com/casey/just

# Default recipe (shows help)
default:
    @just --list

# Install dependencies
install:
    julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run tests
test:
    julia --project=. test/runtests.jl

# Run tests with coverage
test-coverage:
    julia --project=. --code-coverage=user test/runtests.jl
    @echo "Coverage files generated in src/"

# Run specific test file
test-file FILE:
    julia --project=. -e 'include("test/{{FILE}}")'

# Initialize CIcaDA configuration
init:
    julia --project=. src/main.jl init

# Generate a new SSH key
generate EMAIL ALGO="ed25519":
    julia --project=. src/main.jl generate -e {{EMAIL}} -a {{ALGO}}

# List all stored keys
list:
    julia --project=. src/main.jl list

# List keys with verbose output
list-verbose:
    julia --project=. src/main.jl list --verbose

# List keys in JSON format
list-json:
    julia --project=. src/main.jl list --format json

# Show information about a specific key
info KEY_ID:
    julia --project=. src/main.jl info --id {{KEY_ID}}

# Validate a specific key
validate KEY_ID:
    julia --project=. src/main.jl validate --id {{KEY_ID}}

# Run security audit on all keys
audit:
    julia --project=. src/main.jl audit

# Audit specific key
audit-key KEY_ID:
    julia --project=. src/main.jl audit --id {{KEY_ID}}

# Backup all keys
backup:
    julia --project=. src/main.jl backup

# Backup specific key
backup-key KEY_ID:
    julia --project=. src/main.jl backup --id {{KEY_ID}}

# Clean old backups (keep N most recent per key)
backup-clean N="5":
    julia --project=. src/main.jl backup --clean {{N}}

# Restore key from backup
restore BACKUP_PATH:
    julia --project=. src/main.jl restore --backup-path {{BACKUP_PATH}}

# Rotate specific key
rotate KEY_ID:
    julia --project=. src/main.jl rotate --id {{KEY_ID}}

# Auto-rotate expiring keys
rotate-auto DAYS="30":
    julia --project=. src/main.jl rotate --auto --warning-days {{DAYS}}

# Emergency rotation (ALL keys)
rotate-all:
    @echo "WARNING: This will rotate ALL keys!"
    julia --project=. src/main.jl rotate --all

# Upload key to GitHub
github-upload KEY_ID TOKEN TITLE="CIcaDA-key":
    julia --project=. src/main.jl github --action upload --id {{KEY_ID}} --token {{TOKEN}} --title {{TITLE}}

# List GitHub SSH keys
github-list TOKEN:
    julia --project=. src/main.jl github --action list --token {{TOKEN}}

# Delete key from GitHub
github-delete GITHUB_KEY_ID TOKEN:
    julia --project=. src/main.jl github --action delete --github-key-id {{GITHUB_KEY_ID}} --token {{TOKEN}}

# Verify GitHub token
github-verify TOKEN:
    julia --project=. src/main.jl github --action verify-token --token {{TOKEN}}

# Show post-quantum cryptography info
pqc-info:
    julia --project=. src/main.jl pqc-info

# Format Julia code (requires JuliaFormatter)
format:
    julia -e 'using Pkg; Pkg.add("JuliaFormatter"); using JuliaFormatter; format(".", verbose=true)'

# Check code formatting
format-check:
    julia -e 'using Pkg; Pkg.add("JuliaFormatter"); using JuliaFormatter; format(".", verbose=true, overwrite=false) || exit(1)'

# Lint Julia code
lint:
    @echo "Running Julia linter..."
    julia --project=. -e 'using Pkg; Pkg.add("Lint"); using Lint; lintpkg("PalimpsestCryptoIdentity")'

# Run security checks
security-check:
    @echo "Scanning for hardcoded secrets..."
    @! grep -r "password\s*=" src/ test/ || echo "Found potential hardcoded passwords!"
    @! grep -r "secret\s*=" src/ test/ | grep -v "github_token" | grep -v "# GitHub" || echo "Found potential secrets!"
    @echo "Security scan complete"

# Build documentation
docs:
    @echo "Documentation already in docs/"
    @ls -lh docs/

# Clean build artifacts
clean:
    @echo "Cleaning coverage files..."
    @find src -name "*.cov" -delete
    @find test -name "*.cov" -delete
    @echo "Cleaning temporary files..."
    @find . -name ".DS_Store" -delete
    @find . -name "*.swp" -delete
    @echo "Clean complete"

# Clean all generated files (including configs)
clean-all: clean
    @echo "WARNING: This will remove your CIcaDA configuration and keys!"
    @read -p "Are you sure? (y/N): " confirm && [ "$confirm" = "y" ] || exit 1
    @rm -rf ~/.cicada
    @echo "Configuration removed"

# Validate RSR compliance
validate-rsr:
    julia --project=. scripts/verify_rsr.jl

# Run all checks (tests + lint + security + RSR)
check: test format-check lint security-check validate-rsr
    @echo "All checks passed!"

# Create a release (update version, tag, push)
release VERSION:
    @echo "Creating release {{VERSION}}..."
    @echo "Updating Project.toml..."
    @sed -i 's/version = ".*"/version = "{{VERSION}}"/' Project.toml
    @echo "Updating CHANGELOG.md..."
    @echo "Creating git tag..."
    @git add Project.toml CHANGELOG.md
    @git commit -m "Release {{VERSION}}"
    @git tag -a v{{VERSION}} -m "Release {{VERSION}}"
    @echo "Push with: git push && git push --tags"

# Show project stats
stats:
    @echo "=== CIcaDA Project Statistics ==="
    @echo ""
    @echo "Lines of Code:"
    @find src -name "*.jl" | xargs wc -l | tail -1
    @echo ""
    @echo "Test Code:"
    @find test -name "*.jl" | xargs wc -l | tail -1
    @echo ""
    @echo "Documentation:"
    @find docs -name "*.md" | xargs wc -l | tail -1
    @echo ""
    @echo "Total Files:"
    @find . -type f -name "*.jl" -o -name "*.md" | wc -l
    @echo ""
    @echo "Git Commits:"
    @git rev-list --count HEAD
    @echo ""
    @echo "Contributors:"
    @git shortlog -sn

# Development setup (install + init + test)
dev-setup: install init test
    @echo "Development environment ready!"

# CI/CD simulation (run all CI checks locally)
ci: install test format-check security-check validate-rsr
    @echo "CI checks complete!"

# Quick start guide
quickstart:
    @cat docs/QUICKSTART.md

# Show help for a specific command
help COMMAND:
    julia --project=. src/main.jl {{COMMAND}} --help

# Open repository in browser
open-repo:
    @open https://github.com/Hyperpolymath/CIcaDA || xdg-open https://github.com/Hyperpolymath/CIcaDA

# Show version
version:
    @grep 'version =' Project.toml | cut -d'"' -f2

# Watch tests (requires entr)
watch-test:
    @find src test -name "*.jl" | entr -c just test
