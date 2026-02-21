# Changelog

All notable changes to _pathroot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-05

### Added

#### Core Engine
- **nicaug Engine** - Complete Nickel-Augmented configuration engine in ReScript (624 lines)
  - Platform detection (6 target types: EdgeASIC, KinoiteLayered, AppleDarwin, StandardPC, etc.)
  - Multi-platform command generation (Fedora, Debian, Android, macOS, Windows, Minix)
  - Nickel/JSON parser with validation
  - CLI with commands: `info`, `validate`, `build`, `deploy`

#### Mustfile Orchestration
- **mustorch Binary** - Complete Mustfile orchestrator in Rust (825 lines)
  - TOML Mustfile parser (must-spec v1.0 compliant)
  - Dependency-aware task execution (topological sort)
  - Requirement validation (must_have/must_not_have)
  - Platform adapter integration with nicaug
  - CLI commands: `validate`, `deploy`, `info`

#### Shell Compatibility
- **22-Shell Matrix** - Universal shell support across all major environments
  - POSIX: bash, dash, ash, ksh, mksh, yash
  - Modern: zsh, fish, nushell, elvish, ion, oil, xonsh
  - Classic: csh, tcsh
  - Cross-platform: powershell, pwsh, cmd
  - Specialized: rc, es, scsh, minix-sh
  - Shell detection & routing (`detect-shell.sh`)
  - Test suites (bash & Julia)

#### Runtime & Integration
- **ReScript Runtime Shims** - Deno-compatible runtime (7 modules)
  - Belt_Array, Belt_Option, Js_array, Js_dict, Js_json
  - Primitive_exceptions, Stdlib_Exn
  - Zero external dependencies

#### Ecosystem Clarification
- **must/mustfile Relationship** - Clear specification vs implementation distinction
  - mustfile repo = format specification
  - must repo = execution engine (Ada 2022)
  - Relationship: `Mustfile:must :: Justfile:just`

### Changed
- Converted all TypeScript to ReScript (519 → 681 lines)
- Updated build system for ReScript compilation
- Modernized Deno configuration with proper import maps

### Technical Details

**Languages & Tools:**
- ReScript: Core _pathroot logic + nicaug engine
- Rust: mustorch orchestrator
- Deno: Runtime environment
- Ada: Ada TUI (partial, GNAT issues)

**Architecture:**
```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│   nicaug     │─────▶│   mustorch   │─────▶│     must     │
│  (ReScript)  │      │    (Rust)    │      │    (Ada)     │
└──────────────┘      └──────────────┘      └──────────────┘
Platform detection    Orchestration         Deployment exec
```

**Metrics:**
- ReScript modules: 10 (6 core + 4 nicaug)
- Lines of ReScript: ~1,300
- Rust crate: mustfile_orchestrator (825 lines)
- Shell scripts: 22 complete implementations
- Workflows: 17/17 RSR compliant

**Platform Coverage:**
- Linux: 13 shells, rpm-ostree, nala
- macOS: 6 shells, brew
- Windows: 3 shells, scoop/winget
- BSD: 6 shells
- Minix: 3 shells, static binaries
- Mobile: Android (pkg/mksh), iOS (brew/IPA)

### Documentation
- Complete README with Mustfile specification
- Integrated Just/Must/Nickel cookbook
- 22-shell compatibility matrix documentation
- Sample Mustfiles and examples
- OPSM integration notes

### Known Issues
- Ada TUI compilation blocked on GNAT 15.2.1 compatibility
  - Missing: OS_Lib.Read_Symbolic_Link, Create_Symbolic_Link
  - Non-critical: Core CLI tools fully functional

## [Unreleased]

### Planned
- OPSM (Operations Substrate Management) integration
- Production deployment testing across all platforms
- Enhanced deployment examples
- Performance optimization
- Comprehensive test coverage

---

[1.0.0]: https://github.com/hyperpolymath/_pathroot/releases/tag/v1.0.0
