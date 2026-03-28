# Juisys Technical Diagnostics Add-on

Developer-focused system diagnostics similar to SIW (System Information for Windows), but for macOS and with privacy-first design.

---

## Overview

The Juisys Technical Diagnostics Add-on provides comprehensive system information for developers and technical users. Written in D for performance, it integrates seamlessly with the Julia-based Juisys core while maintaining the same privacy guarantees.

### Key Differences from Core Juisys

| Aspect | Core Juisys | Diagnostics Add-on |
|--------|-------------|-------------------|
| **Target Audience** | General users | Developers/tech users |
| **Language** | Julia | D (with Julia integration) |
| **Focus** | App privacy/cost analysis | System diagnostics |
| **Data Depth** | Application-level | System-level |
| **Activation** | Default | Optional (opt-in) |

### Privacy Guarantees (Maintained)

✅ **100% Local Processing** - No network calls
✅ **Ephemeral Data Only** - Cleared after session
✅ **Explicit Consent** - Required before collection
✅ **No Personal Data** - System config only, no secrets
✅ **Optional Activation** - Must be explicitly enabled

---

## Features

### Hardware Diagnostics

- **CPU Information**
  - Model, cores, architecture
  - Features and capabilities
  - Performance characteristics

- **Memory Details**
  - Total/available RAM
  - Memory pressure
  - Swap usage
  - VM statistics

- **Storage Analysis**
  - Disk usage and capacity
  - Filesystem types
  - Inode utilization

- **GPU Information** (if available)
  - Graphics hardware
  - VRAM capacity

### Software Diagnostics

- **Operating System**
  - Version and build
  - Kernel information
  - Uptime statistics

- **Installed Tools**
  - Compilers (gcc, clang, rustc, go, etc.)
  - Interpreters (python, ruby, node, julia, etc.)
  - Build systems (make, cmake, cargo, npm, etc.)
  - Version control (git, svn, hg)

- **Development Environment**
  - IDEs and editors
  - Package managers
  - Container tools (Docker, Podman)
  - Database clients

### Network Diagnostics

- **Configuration**
  - Network interfaces
  - Routing tables
  - Active connections (count only)

- **Performance**
  - Connection statistics
  - Interface metrics

### Process & Performance

- **Process Information**
  - Total process count
  - Top CPU consumers
  - Top memory consumers

- **Performance Metrics**
  - Load averages
  - CPU usage
  - Memory pressure
  - I/O statistics

### Developer-Specific

- **Build Tools Detection**
  - Installed compilers and versions
  - Build systems and package managers
  - Language runtimes

- **Environment Analysis**
  - Shell configuration files
  - PATH analysis
  - Git repository locations (count only)
  - SSH keys (existence only, no content)

- **Container Detection**
  - Docker/Podman presence
  - Running in container check
  - VirtualBox status

---

## Diagnostic Levels

### BASIC
Essential system information only:
- Hardware specs
- OS version
- Storage summary

**Use when**: Quick overview needed

### STANDARD (Default)
Common diagnostics for developers:
- All BASIC info
- Network configuration
- Process information
- Performance metrics

**Use when**: General development diagnostics

### DEEP
Comprehensive technical analysis:
- All STANDARD info
- Memory details
- CPU specifics
- Kernel parameters
- Environment variables (filtered)

**Use when**: Troubleshooting performance issues

### FORENSIC
Maximum detail (performance intensive):
- All DEEP info
- Filesystem details
- Security configuration
- Service/daemon information

**Use when**: Deep system analysis needed

---

## Installation

### Prerequisites

1. **D Compiler** (choose one):
   ```bash
   # LDC (recommended for performance)
   brew install ldc

   # OR DMD (reference compiler)
   brew install dmd

   # OR GDC (GCC-based)
   brew install gdc
   ```

2. **Julia** (already installed for Juisys core)

### Build Diagnostics Library

```bash
cd jusys/src-diagnostics/d

# Build with make (recommended)
make release

# OR build with DUB
dub build --build=release

# Install system-wide (optional)
sudo make install
```

This creates `libdiagnostics.dylib` (macOS) or `libdiagnostics.so` (Linux).

---

## Usage

### Enable Diagnostics Add-on

```julia
using Juisys.DiagnosticsIntegration

# Enable with default (STANDARD) level
enable_diagnostics()

# OR enable with specific level
enable_diagnostics(DEEP)
```

### Run Diagnostics

```julia
# Create diagnostics instance
diag = SystemDiagnostics(STANDARD)

# Request consent
request_consent(diag)

# Run diagnostics
results = run_diagnostics(diag)

# Display report
report = format_diagnostic_report(results)
println(report)

# Export to file
export_diagnostics_report(results, "diagnostics.json", format=:json)

# Clear data when done
clear_diagnostics_data(diag)
```

### From CLI

```julia
julia --project=. -e '
include("src/diagnostics_integration.jl");
using .DiagnosticsIntegration;

enable_diagnostics(STANDARD);
diag = SystemDiagnostics();
request_consent(diag);
results = run_diagnostics(diag);
println(format_diagnostic_report(results));
'
```

### Integration with Main Juisys

The diagnostics add-on will appear as an additional menu option in Juisys CLI when enabled:

```
  10. Technical Diagnostics  - System diagnostics (developers)
```

---

## Output Example

```
══════════════════════════════════════════════════════════════════════
JUISYS TECHNICAL DIAGNOSTICS REPORT
══════════════════════════════════════════════════════════════════════
Timestamp: 2025-11-22T02:00:00
Level: STANDARD
Total Diagnostics: 8

PRIVACY NOTICE:
  100% local processing, ephemeral data
══════════════════════════════════════════════════════════════════════

──────────────────────────────────────────────────────────────────────
CATEGORY: HARDWARE
──────────────────────────────────────────────────────────────────────

  system_hardware
    Collected: 2025-11-22T02:00:01
    Data fields: cpu_model, cpu_cores, cpu_physical_cores, memory_bytes,
                 memory_gb, machine_model, architecture

──────────────────────────────────────────────────────────────────────
CATEGORY: SOFTWARE
──────────────────────────────────────────────────────────────────────

  system_software
    Collected: 2025-11-22T02:00:02
    Data fields: os_version, os_build, kernel_version, boot_time,
                 default_shell

  development_tools
    Collected: 2025-11-22T02:00:03
    Data fields: compilers, interpreters, build_tools, version_control,
                 package_managers, editors

──────────────────────────────────────────────────────────────────────
CATEGORY: PERFORMANCE
──────────────────────────────────────────────────────────────────────

  performance_metrics
    Collected: 2025-11-22T02:00:04
    Data fields: load_average, cpu_usage, memory_pressure, swap_usage

══════════════════════════════════════════════════════════════════════
End of diagnostics report
══════════════════════════════════════════════════════════════════════
```

---

## Privacy & Security

### What Is Collected

✅ **System configuration** (hardware specs, OS version)
✅ **Installed tools** (compilers, editors, package managers)
✅ **Performance metrics** (CPU/memory usage)
✅ **Process information** (counts and top consumers)
✅ **Network configuration** (interfaces, not traffic)

### What Is NOT Collected

❌ **Personal files or documents**
❌ **Passwords or credentials**
❌ **Environment variables with secrets** (filtered)
❌ **SSH private keys** (only checks existence)
❌ **Network traffic or packet data**
❌ **Browser history or bookmarks**
❌ **Email or messages**
❌ **Source code content**

### Sensitive Data Handling

- **Environment variables**: Filtered to safe prefixes only (LANG, PATH, etc.)
- **SSH keys**: Only reports existence, never reads content
- **Git repositories**: Counts only, no code inspection
- **Database tools**: Detects clients, no credentials/data

### Data Lifecycle

1. **Collection**: With explicit consent
2. **Storage**: In-memory only (ephemeral)
3. **Usage**: Analysis and report generation
4. **Export**: Optional, requires FILE_WRITE consent
5. **Erasure**: Automatic on session end, manual available

---

## Developer Information

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Julia (Juisys Core)                      │
│  ┌────────────────────────────────────────────────────┐     │
│  │     DiagnosticsIntegration Module                  │     │
│  │  - Enable/disable diagnostics                      │     │
│  │  - Consent management                              │     │
│  │  - Report formatting                               │     │
│  └──────────────────────┬─────────────────────────────┘     │
└─────────────────────────┼───────────────────────────────────┘
                          │ C FFI
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                D Library (libdiagnostics)                   │
│  ┌────────────────────────────────────────────────────┐     │
│  │     SystemDiagnostics Class                        │     │
│  │  - Hardware diagnostics                            │     │
│  │  - Software diagnostics                            │     │
│  │  - Network diagnostics                             │     │
│  │  - Performance metrics                             │     │
│  └────────────────────────────────────────────────────┘     │
│  ┌────────────────────────────────────────────────────┐     │
│  │     DeveloperDiagnostics Class                     │     │
│  │  - Development tools detection                     │     │
│  │  - Environment analysis                            │     │
│  │  - Container/VM detection                          │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Why D Language?

1. **Performance**: Compiled, systems-level language
2. **C Interop**: Easy FFI with Julia via C ABI
3. **Memory Safety**: GC + manual memory control options
4. **Expressiveness**: Modern language features
5. **Cross-platform**: Good macOS/Linux support

### Extending Diagnostics

Add new diagnostic categories:

```d
// In diagnostics.d
private void collectCustomDiagnostic() {
    writeln("  Collecting custom diagnostic...");

    JSONValue data = JSONValue.emptyObject();

    // Your collection logic here

    results ~= DiagnosticResult(
        DiagnosticCategory.CUSTOM,  // Add to enum
        "custom_name",
        data,
        Clock.currTime(),
        level,
        false  // Or true if sensitive
    );
}
```

Then call from `runDiagnostics()` based on level.

---

## Troubleshooting

### Library Not Found

**Problem**: `Diagnostics library not found`

**Solutions**:
1. Build the library: `cd src-diagnostics/d && make release`
2. Copy to expected location: `cp libdiagnostics.dylib src-diagnostics/d/`
3. OR install system-wide: `sudo make install`

### Compilation Errors

**Problem**: D compiler errors during build

**Solutions**:
1. Ensure D compiler installed: `dmd --version` or `ldc2 --version`
2. Update compiler: `brew upgrade ldc`
3. Try different compiler: `DC=dmd make`

### Permission Denied

**Problem**: Some diagnostics fail with permission errors

**Expected**: Certain system information requires elevated privileges. This is intentional - diagnostics gracefully skip inaccessible data rather than requiring sudo (privacy principle).

### Incomplete Data

**Problem**: Some fields missing in output

**Normal**: Not all diagnostic checks succeed on all systems. The tool continues and reports what it can access.

---

## Performance Considerations

### Resource Usage

| Level | CPU Impact | Memory Usage | Time |
|-------|-----------|--------------|------|
| BASIC | Minimal | <10 MB | <1s |
| STANDARD | Low | <20 MB | 1-2s |
| DEEP | Moderate | <50 MB | 2-5s |
| FORENSIC | Higher | <100 MB | 5-10s |

### Recommendations

- Use **BASIC** for quick checks
- Use **STANDARD** for routine diagnostics
- Use **DEEP** when troubleshooting specific issues
- Use **FORENSIC** sparingly (performance intensive)

---

## Comparison to SIW

### Similar Features

✅ Hardware information
✅ Software inventory
✅ Network configuration
✅ Process monitoring
✅ Performance metrics

### Differences

| Feature | SIW | Juisys Diagnostics |
|---------|-----|-------------------|
| Platform | Windows | macOS/Linux |
| Network Calls | Some | None (100% local) |
| Data Retention | Configurable | Ephemeral only |
| Consent | Implicit | Explicit (GDPR) |
| Target Users | General | Developers/tech |
| Privacy Focus | Standard | Privacy-first |

---

## Future Enhancements

Planned additions:

- [ ] GPU detailed diagnostics
- [ ] Thermal monitoring
- [ ] Power consumption metrics
- [ ] Bluetooth device information
- [ ] Audio device details
- [ ] External display detection
- [ ] Battery health (laptops)
- [ ] Startup items analysis

---

## License

MIT License - Same as Juisys core

---

## Support

For issues or questions:
1. Check this documentation
2. Review example scripts in `examples-diagnostics/`
3. File an issue on GitHub
4. See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development

---

**Remember**: Diagnostics add-on is optional. Core Juisys works without it. Enable only when you need detailed technical information.
