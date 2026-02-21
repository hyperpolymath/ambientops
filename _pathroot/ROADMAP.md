# _pathroot Roadmap

**Project:** Mustfile - Global Devtools Authority
**Current Version:** 1.0.0
**Status:** Released (2026-02-05)

---

## Released: v1.0.0 (2026-02-05)

### ✅ Core Features
- [x] Mustfile specification complete
- [x] Global `_pathroot` marker system
- [x] `_envbase` JSON metadata format
- [x] 22-shell compatibility matrix
- [x] Cross-platform discovery (Windows, Linux, macOS, WSL, Android, Minix)
- [x] ReScript/Deno implementation (624 lines)
- [x] Rust mustorch orchestrator (825 lines)
- [x] Ada TUI with GNAT 15.2.1 compatibility
- [x] POSIX symlink bindings for modern GNAT
- [x] Comprehensive documentation

### ✅ Platform Support
- [x] Windows (batch, PowerShell)
- [x] Linux (bash, POSIX)
- [x] macOS (bash, zsh)
- [x] WSL
- [x] Android (Termux)
- [x] Minix

### ✅ Ada TUI
- [x] Interactive management interface
- [x] Transaction mode for scripting
- [x] GNAT 15.2.1+ compatibility
- [x] Universal ABI/FFI standard (Idris2 + Zig)
- [x] Formal verification with dependent types
- [x] Memory-safe Zig FFI implementation
- [x] Zero compilation errors/warnings

---

## v1.1.0 (Q2 2026) - Enhanced Discovery

### Planned Features
- [ ] Python binding library
- [ ] Ruby binding library
- [ ] Zig native implementation
- [ ] Discovery caching for performance
- [ ] Multi-root support (multiple devtools locations)
- [ ] Version negotiation protocol

### Ada TUI Enhancements
- [ ] Color terminal output
- [ ] Interactive symlink repair wizard
- [ ] Batch symlink operations
- [ ] Environment validation reports
- [ ] Shell integration helpers

### Documentation
- [ ] Video walkthrough
- [ ] Docker/Podman examples
- [ ] CI/CD integration guide
- [ ] VSCode extension tutorial

---

## v1.2.0 (Q3 2026) - Integration Layer

### must Integration
- [ ] Direct `must` binary integration
- [ ] Template-based scaffolding
- [ ] Automated environment setup
- [ ] Project bootstrapping

### Tooling Support
- [ ] Guix package definition
- [ ] Nix flake
- [ ] Homebrew formula
- [ ] Scoop manifest
- [ ] Chocolatey package

### API Stability
- [ ] Stable ReScript API (1.0)
- [ ] Stable Ada TUI protocol
- [ ] JSON schema versioning
- [ ] Migration guides

---

## v2.0.0 (Q4 2026) - Enterprise Features

### Advanced Discovery
- [ ] Network-mounted devtools
- [ ] Cloud storage discovery
- [ ] Container environment detection
- [ ] Multi-tenant support

### Security
- [ ] Signed `_pathroot` files
- [ ] Integrity verification
- [ ] Audit logging
- [ ] Access control policies

### Monitoring
- [ ] Health check API
- [ ] Usage metrics
- [ ] Environment drift detection
- [ ] Automated remediation

---

## Future Considerations

### Platform Expansion
- [ ] FreeBSD support
- [ ] OpenBSD support
- [ ] Haiku OS support
- [ ] Plan 9 support

### Language Bindings
- [ ] C/C++ header library
- [ ] Go module
- [ ] Elixir/Erlang library
- [ ] OCaml module
- [ ] Haskell package

### Ecosystem
- [ ] VS Code extension
- [ ] JetBrains IDE plugin
- [ ] Emacs package
- [ ] Vim/Neovim plugin

---

## Completed Milestones

### Phase 1: Specification (Q4 2025)
**Status:** ✅ Complete

- Defined Mustfile format
- Established `_pathroot` / `_envbase` contract
- Documented 22-shell matrix
- Created reference implementation

### Phase 2: TypeScript → ReScript Migration (Q1 2026)
**Status:** ✅ Complete

- Converted all TypeScript to ReScript (519 lines)
- Implemented nicaug engine (624 lines)
- Created Deno runtime shims
- Zero runtime type errors

### Phase 3: Ada TUI Modernization (Q1 2026)
**Status:** ✅ Complete (2026-02-05)

- GNAT 15.2.1 compatibility
- POSIX symlink bindings
- Removed deprecated `GNAT.OS_Lib` functions
- Clean compilation

---

## Known Limitations

### Current
- Single devtools root per filesystem
- JSON-only metadata format
- No built-in migration tools
- Manual shell integration required

### Future Resolution
These limitations will be addressed in future versions based on user feedback and real-world usage patterns.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute to this roadmap.

Feature requests: [GitHub Issues](https://github.com/hyperpolymath/_pathroot/issues)

---

## Version History

| Version | Date | Milestone |
|---------|------|-----------|
| 1.0.0 | 2026-02-05 | Initial release with full platform support |
| 1.0.0-rc1 | 2025-12-27 | Release candidate |
| 0.9.0 | 2025-12-15 | Beta with ReScript implementation |

---

*Roadmap subject to change based on community feedback and evolving requirements.*
