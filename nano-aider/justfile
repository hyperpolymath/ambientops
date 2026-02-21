# nano-aider - Development Tasks
set shell := ["bash", "-uc"]
set dotenv-load := true

project := "nano-aider"
gpr := "nano_aider.gpr"

# Show all recipes
default:
    @just --list --unsorted

# Build in debug mode
build:
    @echo "Building {{project}} (debug)..."
    gprbuild -P {{gpr}} -XNANO_AIDER_BUILD_MODE=debug

# Build in release mode
release:
    @echo "Building {{project}} (release)..."
    gprbuild -P {{gpr}} -XNANO_AIDER_BUILD_MODE=release

# Build using Alire
alr-build:
    @echo "Building {{project}} with Alire..."
    alr build

# Run the application
run: build
    @echo "Running {{project}}..."
    ./bin/nano-aider

# Run with list flag
list: build
    @echo "Listing all options..."
    ./bin/nano-aider --list

# Run tests
test: build
    @echo "Running tests..."
    ./ci-scripts/test.sh

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf obj/ bin/ alire/

# Format Ada code
fmt:
    @echo "Formatting Ada code..."
    find src/ -name "*.ads" -o -name "*.adb" | xargs -I {} gnatpp {}

# Run SPARK verification
prove:
    @echo "Running GNATprove..."
    gnatprove -P {{gpr}} --level=2 --report=all

# Check style
lint:
    @echo "Checking style..."
    gprbuild -P {{gpr}} -XNANO_AIDER_BUILD_MODE=debug -gnatyg -gnatwe

# Generate documentation
docs:
    @echo "Generating documentation..."
    gnatdoc -P {{gpr}} --output=docs/api

# Install to ~/.local/bin
install: release
    @echo "Installing to ~/.local/bin..."
    mkdir -p ~/.local/bin
    cp bin/nano-aider ~/.local/bin/
    @echo "Installed! Make sure ~/.local/bin is in your PATH"

# Uninstall from ~/.local/bin
uninstall:
    @echo "Removing from ~/.local/bin..."
    rm -f ~/.local/bin/nano-aider

# Show project information
info:
    @echo "Project: {{project}}"
    @echo "GPR File: {{gpr}}"
    @echo ""
    @echo "Ada Source Files:"
    @find src/ -name "*.ads" -o -name "*.adb" | wc -l
    @echo ""
    @echo "Build Modes: debug, release, spark"

# Create a new release
tag version:
    @echo "Creating tag v{{version}}..."
    git tag -a "v{{version}}" -m "Release v{{version}}"
    @echo "Run 'git push origin v{{version}}' to push the tag"
