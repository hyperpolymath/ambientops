#!/usr/bin/env bash
#
# CIcaDA Installation Script
# Installs PalimpsestCryptoIdentity and its dependencies

set -e

echo "====================================="
echo "CIcaDA Installation"
echo "Palimpsest Crypto Identity Manager"
echo "====================================="
echo ""

# Check for Julia
if ! command -v julia &> /dev/null; then
    echo "ERROR: Julia is not installed"
    echo "Please install Julia 1.9+ from https://julialang.org/downloads/"
    exit 1
fi

# Check Julia version
JULIA_VERSION=$(julia --version | grep -oP '\d+\.\d+' | head -1)
REQUIRED_VERSION="1.9"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$JULIA_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "ERROR: Julia $REQUIRED_VERSION or higher is required"
    echo "Current version: $JULIA_VERSION"
    exit 1
fi

echo "✓ Julia $JULIA_VERSION detected"
echo ""

# Check for ssh-keygen
if ! command -v ssh-keygen &> /dev/null; then
    echo "WARNING: ssh-keygen not found"
    echo "Classical SSH key generation may not work"
    echo ""
fi

# Install dependencies
echo "Installing Julia dependencies..."
julia --project=. -e 'using Pkg; Pkg.instantiate()'

if [ $? -eq 0 ]; then
    echo "✓ Dependencies installed successfully"
else
    echo "ERROR: Failed to install dependencies"
    exit 1
fi

echo ""

# Initialize configuration
echo "Initializing CIcaDA configuration..."
julia --project=. src/main.jl init

echo ""
echo "====================================="
echo "Installation complete!"
echo "====================================="
echo ""
echo "Quick start:"
echo "  1. Generate a key:    julia --project=. src/main.jl generate -e your@email.com"
echo "  2. List keys:         julia --project=. src/main.jl list"
echo "  3. Get help:          julia --project=. src/main.jl --help"
echo ""
echo "Configuration: ~/.cicada/config.toml"
echo "Keys stored in: ~/.cicada/keys"
echo ""
