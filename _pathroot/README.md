# _pathroot

**Modular Devtools Environment Management**

A cross-platform system for managing development tool environments with discoverable paths, environment metadata, and automation support.

## Overview

_pathroot solves the "where are my tools?" problem by establishing:

1. **`_pathroot`** - A global marker file at the drive/filesystem root pointing to your devtools
2. **`_envbase`** - Local JSON metadata describing the environment

```
C:\_pathroot          → Contains: "C:\devtools"
C:\devtools\_envbase  → Contains: {"env": "devtools", "profile": "default", ...}
```

## Quick Start

### Windows

```batch
:: Run the scaffolder
scripts\windows\automkdir.bat

:: Inspect your environment
powershell -File scripts\windows\envbase.ps1
```

### Linux/macOS/WSL

```bash
# Initialize
./scripts/posix/pathroot.sh init /opt/devtools

# Inspect
./scripts/posix/pathroot.sh info

# Add to shell (bash/zsh)
eval $(./scripts/posix/pathroot.sh env)
```

### Deno + ReScript (Cross-platform)

```bash
# Build ReScript modules
deno task build

# Validate installation
deno task validate

# Use as library
deno add @pathroot/tools
```

```rescript
// ReScript usage
let result = await Discovery.discover()
if result.found {
  switch result.devtoolsRoot {
  | Some(root) => {
      let envbase = await Envbase.loadEnvbase(root)
      switch envbase {
      | Some(eb) => Js.log(`Profile: ${eb.profile}`)
      | None => ()
      }
    }
  | None => ()
  }
}
```

## Directory Structure

```
C:\devtools\
├── bin\        # Executables (add to PATH)
├── scripts\    # Utility scripts
├── config\     # Configuration files
├── logs\       # Log outputs
├── temp\       # Temporary files
├── tools\      # Installed packages
├── _envbase    # Environment metadata

C:\_pathroot    # Global root marker
```

## Documentation

- [Wiki](wiki/Home.md) - Full documentation
- [PDF Guide](docs/pathroot-guide.adoc) - Printable reference (build with asciidoctor-pdf)
- [FAQ](wiki/FAQ.md) - Frequently Asked Questions

## Components

| Component | Description |
|-----------|-------------|
| `scripts/windows/` | Windows batch and PowerShell scripts |
| `scripts/posix/` | Bash scripts for Linux/macOS/WSL |
| `ada/tui/` | Ada-based Terminal User Interface |
| `src/` | ReScript library (compiles to JS for Deno runtime) |

## Integration

- **[RapidEE](https://www.rapidee.com/)** - Visual Windows environment variable management
- **[modshells](https://gitlab.com/hyperpolymath/modshells)** - Modular shell configurations
- **[nano-aider](https://gitlab.com/hyperpolymath/nano-aider)** - AI-assisted development

See [Integration Guide](wiki/Integration.md) for details.

## TUI

The Ada-based TUI provides interactive management:

```bash
# Build (requires GNAT 15.2.1+)
cd ada/tui && gprbuild -P pathroot_tui.gpr

# Run
./pathroot-tui

# Transaction mode (for scripting)
echo "PATHROOT:QUERY:ENV" | ./pathroot-tui --transaction
```

**GNAT 15.2.1+ Compatibility:** The TUI now uses POSIX bindings for symbolic link operations, replacing deprecated `GNAT.OS_Lib` functions. All modules compile with zero errors on modern GNAT versions.

**ABI/FFI Architecture:** Implements the universal Idris2 ABI + Zig FFI standard:
- **Idris2 ABI**: Dependent type proofs for path length validation and interface correctness
- **Zig FFI**: Memory-safe POSIX symlink implementation with zero overhead
- **No C code, no header files**: Pure verified implementations
- See [ABI-FFI-SYMLINKS.md](ABI-FFI-SYMLINKS.md) for complete documentation

## Building the PDF

```bash
# Install asciidoctor-pdf
gem install asciidoctor-pdf

# Generate PDF
asciidoctor-pdf docs/pathroot-guide.adoc -o docs/pathroot-guide.pdf
```

## License

PMPL-1.0-or-later

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

*Because your Head of DevOps deserves joy.*
