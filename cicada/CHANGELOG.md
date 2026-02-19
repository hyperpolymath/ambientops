# Changelog

All notable changes to CIcaDA (Palimpsest Crypto Identity) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- RSR Framework compliance improvements
- .well-known/ directory (security.txt, ai.txt, humans.txt)
- Community standards (CODE_OF_CONDUCT.md, CONTRIBUTING.md, MAINTAINERS.md)
- Comprehensive SECURITY.md policy
- justfile for build automation
- RSR compliance verification script

## [0.1.0] - 2025-11-22

### Added - Phase 1 MVP Complete

#### Core Features
- **Key Generation System**
  - Ed25519 SSH key generation
  - RSA-2048/4096 SSH key generation
  - ECDSA-P256/P384 SSH key generation
  - Post-quantum stub (Dilithium2/3/5, Kyber512/768/1024)
  - Hybrid quantum-resistant keys (Ed25519 + Dilithium3)
  - Key metadata with UUID, expiration, comments
  - Fingerprint computation

- **Storage & Management**
  - Secure keystore with JSON metadata
  - Individual and bulk key backups
  - Backup retention management (keep N recent)
  - Full restore from backup
  - Key listing (table and JSON output)
  - Key information display
  - Key deletion with secure cleanup
  - Proper file permissions (0600 private, 0700 dirs)

- **Validation & Security**
  - Public/private key validation
  - Key pair matching verification
  - Expiration detection and warnings
  - Algorithm strength assessment
  - Comprehensive security auditing
  - Audit reports (table and JSON)

- **Key Rotation**
  - Manual key rotation with automatic backup
  - Auto-rotation for expiring keys
  - Emergency rotation (all keys)
  - Rotation reports and tracking
  - Configurable warning periods

- **GitHub Integration**
  - Upload SSH keys to GitHub via API
  - List GitHub SSH keys
  - Delete keys from GitHub
  - GitHub token validation
  - Configuration-based and CLI-based token support

- **CLI Interface**
  - 10 comprehensive commands via ArgParse:
    - `init`: Initialize configuration
    - `generate`: Generate new key pairs
    - `list`: List all stored keys
    - `info`: Show detailed key information
    - `validate`: Validate key pairs
    - `backup`: Backup keys
    - `restore`: Restore from backup
    - `rotate`: Rotate keys (manual/auto/emergency)
    - `github`: GitHub integration commands
    - `audit`: Security audit
    - `pqc-info`: Post-quantum crypto information
  - Help system and version info
  - Verbose and JSON output modes
  - Custom error handling
  - Logging with 4 verbosity levels

- **Configuration**
  - TOML configuration files
  - Environment variable support
  - Customizable storage paths
  - Security settings
  - GitHub token management
  - Default configuration generation

- **Error Handling**
  - Custom error types:
    - ConfigurationError
    - KeyGenerationError
    - KeyValidationError
    - StorageError
    - IntegrationError
    - SecurityError
  - Detailed error messages
  - Proper exception propagation

- **Logging**
  - Structured logging system
  - Timestamped log entries
  - Security event logging
  - Key operation audit trail
  - 4 verbosity levels (0-3)

#### Testing
- Comprehensive test suite (50+ tests):
  - test_types.jl: Key type system (17 tests)
  - test_config.jl: Configuration management
  - test_keygen.jl: Key generation (all algorithms)
  - test_storage.jl: Storage, backup, recovery
  - test_validation.jl: Validation and auditing
- All tests use isolated temporary directories
- 100% test pass rate

#### Documentation
- README.md: Project overview and quick start
- CLAUDE.md: Developer and AI assistant notes
- docs/QUICKSTART.md: 5-minute getting started guide
- docs/USER_GUIDE.md: Comprehensive user documentation (400+ lines)
- docs/examples/: 3 working shell scripts
  - daily_workflow.sh: Development workflow example
  - security_incident.sh: Security incident response
  - hybrid_setup.sh: Hybrid quantum-resistant setup
- DEVELOPMENT_SUMMARY.md: Complete development session summary

#### Infrastructure
- install.sh: Automated installation script
- .github/workflows/ci.yml: GitHub Actions CI/CD
  - Multi-Julia version testing (1.9, 1.10, nightly)
  - Cross-platform (Ubuntu, macOS, Windows)
  - Code quality checks
  - Security scanning
  - Code coverage
- Project.toml: Complete dependency manifest
  - ArgParse, HTTP, JSON3, Nettle
  - OpenSSH_jll, TOML, UUIDs, Dates

#### Security
- Secure file permissions (0600/0700)
- No secrets in logs or errors
- Input validation throughout
- Security audit capabilities
- Vulnerability disclosure policy
- Secure defaults

### Dependencies
- Julia 1.9+ (required)
- ssh-keygen (for classical key generation)
- Git (for repository management)
- Julia packages:
  - ArgParse v1.1+
  - HTTP v1
  - JSON3 v1
  - Nettle v0.2
  - OpenSSH_jll
  - TOML (stdlib)
  - UUIDs (stdlib)
  - Dates (stdlib)
  - Logging (stdlib)

### Known Limitations
- Post-quantum cryptography is stub implementation only
  - Dilithium and Kyber keys are placeholders
  - NOT suitable for production use
  - Full PQC planned for Phase 2 (requires NistyPQC.jl)
- GitHub integration requires network connectivity
- No multi-factor authentication (planned Phase 2)
- No backup encryption (planned Phase 2)
- No HSM support (planned Phase 2)

### Technical Details
- Total implementation: ~3,500 lines of Julia code
- 27 files created in Phase 1
- 9 modules/subsystems
- Architecture: Modular design with clear separation
- License: Palimpsest License v0.4
- Repository: https://github.com/Hyperpolymath/CIcaDA

### Development
- Autonomous AI development (Claude Sonnet 4.5)
- Development date: 2025-11-22
- Single development session
- Complete Phase 1 MVP delivered

### Contributors
- Hyperpolymath (Project Lead)
- Claude (Anthropic) - AI-assisted development

## [0.0.1] - 2025-11-21

### Added
- Initial repository structure
- Basic Project.toml
- Stub main.jl
- README.md
- LICENSE (Palimpsest v0.4)
- malware-scanner submodule

---

## Versioning Scheme

- **Major (X.0.0)**: Breaking changes, major features
- **Minor (0.X.0)**: New features, backward compatible
- **Patch (0.0.X)**: Bug fixes, documentation

## Release Process

1. Update CHANGELOG.md
2. Update version in Project.toml
3. Create git tag (vX.Y.Z)
4. Push tag to trigger release
5. GitHub Actions builds and publishes

## Roadmap

### Phase 2 (v0.2.0) - Enhanced Security
- Full PQC implementation (NistyPQC.jl integration)
- Multi-factor authentication (TOTP, hardware keys)
- Hardware security module (HSM) support
- Backup encryption with passphrase
- Key sharing and delegation
- Email notifications for expiration
- Malware scanner integration

### Phase 3 (v0.3.0) - Enterprise Features
- Team management and collaboration
- Role-based access control (RBAC)
- Centralized key management server
- Compliance reporting (SOC2, ISO 27001)
- Integration with vaults (HashiCorp Vault, AWS Secrets Manager)
- GUI interface (web-based)
- Audit log export (SIEM integration)
- API server mode

---

[Unreleased]: https://github.com/Hyperpolymath/CIcaDA/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Hyperpolymath/CIcaDA/releases/tag/v0.1.0
[0.0.1]: https://github.com/Hyperpolymath/CIcaDA/releases/tag/v0.0.1
