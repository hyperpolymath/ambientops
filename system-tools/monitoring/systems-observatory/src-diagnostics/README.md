# Juisys Technical Diagnostics Add-on

Developer-focused system diagnostics written in D, integrated with Juisys.

---

## Quick Start

### 1. Install D Compiler

```bash
# macOS
brew install ldc

# Linux (Debian/Ubuntu)
sudo apt install ldc

# Linux (Fedora)
sudo dnf install ldc
```

### 2. Build Diagnostics Library

```bash
cd src-diagnostics/d
make release
```

This creates `libdiagnostics.dylib` (macOS) or `libdiagnostics.so` (Linux).

### 3. Enable in Juisys

```julia
using Juisys.DiagnosticsIntegration

enable_diagnostics(STANDARD)
```

---

## What's Included

### D Source Code (`d/`)

- **diagnostics.d** - Core system diagnostics
- **developer_diagnostics.d** - Developer tools detection
- **dub.json** - DUB package configuration
- **Makefile** - Build system

### Julia Integration (`../src/`)

- **diagnostics_integration.jl** - Julia FFI layer

### Documentation (`../docs/diagnostics/`)

- **DIAGNOSTICS.md** - Comprehensive guide

### Examples (`../examples-diagnostics/`)

- **example_diagnostics_basic.jl** - Basic usage
- **example_diagnostics_developer.jl** - Developer environment analysis

---

## Architecture

```
Julia (Juisys) ←→ C FFI ←→ D (libdiagnostics)
```

The D library provides system diagnostics through a C-compatible interface that Julia can call.

---

## Build Options

### Using Make

```bash
# Release build (optimized)
make release

# Debug build
make debug

# Clean
make clean

# Install system-wide
sudo make install

# Run tests
make test
```

### Using DUB

```bash
dub build --build=release
```

### Compiler Selection

```bash
# Use LDC (default, recommended)
make release

# Use DMD
DC=dmd make

# Use GDC
DC=gdc make
```

---

## Features

### 4 Diagnostic Levels

1. **BASIC** - Essential info (hardware, OS, storage)
2. **STANDARD** - + network, processes, performance
3. **DEEP** - + memory details, kernel, environment
4. **FORENSIC** - + filesystem, security, services

### Diagnostic Categories

- Hardware (CPU, memory, storage)
- Software (OS, installed tools)
- Network (configuration, statistics)
- Performance (load, CPU, memory)
- Processes (running processes, top consumers)
- Developer (compilers, interpreters, build tools, IDEs)
- Environment (shell config, PATH, SSH keys existence)
- Kernel (parameters, loaded extensions)
- Security (firewall, SIP status)

---

## Privacy Guarantees

✅ **100% Local** - No network calls
✅ **Ephemeral** - Data cleared after session
✅ **Consent Required** - Explicit user permission
✅ **Filtered** - No secrets (env vars filtered, SSH keys not read)
✅ **Optional** - Must be explicitly enabled

---

## Usage Examples

### Basic Diagnostics

```julia
include("src/diagnostics_integration.jl")
using .DiagnosticsIntegration

enable_diagnostics(BASIC)
diag = SystemDiagnostics(BASIC)
request_consent(diag)
results = run_diagnostics(diag)
println(format_diagnostic_report(results))
```

### Developer Environment

```julia
enable_diagnostics(DEEP)
diag = SystemDiagnostics(DEEP)
request_consent(diag)
results = run_diagnostics(diag)

# Find specific tools
for r in results[:results]
    if r[:category] == "SOFTWARE"
        println(r[:data])
    end
end
```

### Export Results

```julia
export_diagnostics_report(results, "diagnostics.json", format=:json)
```

---

## Troubleshooting

### "Library not found"

1. Build the library: `make release`
2. Ensure it's in `src-diagnostics/d/`
3. OR install system-wide: `sudo make install`

### Compilation errors

1. Check D compiler: `ldc2 --version`
2. Update compiler: `brew upgrade ldc`
3. Try different compiler: `DC=dmd make`

### Permission denied

Some diagnostics require elevated privileges. The tool gracefully skips inaccessible data rather than failing.

---

## Extending

Add new diagnostics in `diagnostics.d`:

```d
private void collectCustomInfo() {
    JSONValue data = JSONValue.emptyObject();

    // Your collection logic

    results ~= DiagnosticResult(
        DiagnosticCategory.CUSTOM,
        "custom_diagnostic",
        data,
        Clock.currTime(),
        level,
        false
    );
}
```

Call from `runDiagnostics()` based on level.

---

## Performance

| Level | Time | Memory | CPU |
|-------|------|--------|-----|
| BASIC | <1s | <10MB | Minimal |
| STANDARD | 1-2s | <20MB | Low |
| DEEP | 2-5s | <50MB | Moderate |
| FORENSIC | 5-10s | <100MB | Higher |

---

## Documentation

See `../docs/diagnostics/DIAGNOSTICS.md` for comprehensive documentation.

---

## License

MIT License - Same as Juisys core

---

## Support

- Issues: File on GitHub
- Examples: See `../examples-diagnostics/`
- Docs: See `../docs/diagnostics/`

---

**Note**: This is an OPTIONAL add-on. Core Juisys works without it. Enable only when you need detailed technical information.
