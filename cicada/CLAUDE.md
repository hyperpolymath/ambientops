# CIcaDA - Palimpsest Crypto Identity

## Project Overview

CIcaDA (Palimpsest Crypto Identity) is a Julia-based cryptographic identity management system focused on quantum-resistant SSH key generation and advanced security protocols.

**Project Name**: PalimpsestCryptoIdentity
**Language**: Julia 1.9+
**License**: Palimpsest License v0.4
**UUID**: 449d71e4-0569-4032-8a3c-f519b3386ebb

## Core Features

- 🌐 Quantum-Resistant SSH Key Generation
- 🔑 Multi-Factor Authentication
- 🛡️ Advanced Security Protocols
- 🖥️ Cross-Platform Support
- 🔍 Integrated Malware Scanner (submodule)

## Project Structure

```
CIcaDA/
├── src/
│   ├── main.jl                  # Main entry point and CLI (670+ lines)
│   ├── config.jl                # Configuration management
│   ├── keygen/
│   │   ├── types.jl             # Key types and metadata
│   │   ├── classical.jl         # Classical SSH key generation
│   │   └── postquantum.jl       # PQC stub implementation
│   ├── storage/
│   │   ├── keystore.jl          # Key storage and retrieval
│   │   ├── backup.jl            # Backup and recovery
│   │   └── rotation.jl          # Automated key rotation
│   ├── validation/
│   │   └── verify.jl            # Key validation and auditing
│   ├── integrations/
│   │   └── github.jl            # GitHub API integration
│   └── utils/
│       ├── errors.jl            # Custom error types
│       └── logging.jl           # Logging utilities
├── test/
│   ├── runtests.jl              # Test suite entry point
│   ├── test_types.jl            # Type system tests
│   ├── test_config.jl           # Configuration tests
│   ├── test_keygen.jl           # Key generation tests
│   ├── test_storage.jl          # Storage and backup tests
│   └── test_validation.jl       # Validation tests
├── docs/
│   ├── QUICKSTART.md            # Quick start guide
│   ├── USER_GUIDE.md            # Comprehensive user guide
│   └── examples/
│       ├── daily_workflow.sh    # Daily development workflow
│       ├── security_incident.sh # Security incident response
│       └── hybrid_setup.sh      # Hybrid QR key setup
├── .github/
│   └── workflows/
│       └── ci.yml               # GitHub Actions CI/CD
├── malware-scanner/             # Git submodule
├── install.sh                   # Installation script
├── Project.toml                 # Julia dependencies
├── README.md                    # User documentation
├── LICENSE                      # Palimpsest License v0.4
└── CLAUDE.md                    # This file
```

**Total Implementation**: ~3,500+ lines of Julia code + tests + documentation

## Dependencies

Current dependencies (from Project.toml):
- **ArgParse** (v1.1+): Command-line argument parsing
- **Logging**: Built-in Julia logging functionality
- **Dates**: Date and time handling for expiration
- **HTTP** (v1): GitHub API integration
- **JSON3** (v1): JSON serialization for metadata and GitHub
- **Nettle** (v0.2): Cryptographic hashing
- **OpenSSH_jll**: SSH key generation binaries
- **TOML**: Configuration file parsing
- **UUIDs**: Unique key identifiers

## Development Guidelines

### Running the Project

```bash
# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run the main application
julia --project=. src/main.jl

# Generate SSH key (planned feature)
julia --project=. src/main.jl generate-key --email you@example.com
```

### Code Organization

- **Module Structure**: Code is organized in the `PalimpsestCryptoIdentity` module
- **Entry Point**: `src/main.jl` contains the main() function that serves as the application entry point
- **Script Mode**: The file can be run both as a module and as a standalone script

### Current Implementation Status

Phase 1 (MVP) is **COMPLETE**:
- ✅ Basic project structure established
- ✅ Module and entry point created
- ✅ Dependencies configured and expanded
- ✅ Core cryptographic functionality implemented
- ✅ SSH key generation (Ed25519, RSA, ECDSA)
- ✅ Post-quantum cryptography support (stub architecture)
- ✅ Key storage and management
- ✅ Backup and recovery system
- ✅ Automated key rotation
- ✅ Key validation and security auditing
- ✅ GitHub API integration
- ✅ Comprehensive CLI with ArgParse
- ✅ Full test suite
- ✅ Documentation and examples
- ✅ CI/CD pipeline (GitHub Actions)
- 🚧 Multi-factor authentication (planned Phase 2)

## Git Submodules

This project uses git submodules:
- **malware-scanner**: Located at `https://github.com/hyperpolymath/malware-scanner.git`

When working with this repo, remember to initialize and update submodules:
```bash
git submodule update --init --recursive
```

## Architecture Notes

### Security Focus
This project deals with cryptographic operations and identity management. When making changes:
- Prioritize security best practices
- Use established cryptographic libraries
- Validate all inputs
- Follow Julia security guidelines for handling sensitive data
- Consider quantum-resistance in cryptographic choices

### Julia Specific Considerations
- Use Julia 1.9+ features
- Follow Julia style guide conventions
- Leverage multiple dispatch for clean API design
- Use type stability for performance
- Add docstrings to all public functions

## Testing

Comprehensive test suite implemented:
- `test/runtests.jl`: Main test runner
- `test/test_types.jl`: Key type system tests (17 tests)
- `test/test_config.jl`: Configuration management tests
- `test/test_keygen.jl`: Key generation tests (all algorithms)
- `test/test_storage.jl`: Storage, backup, and recovery tests
- `test/test_validation.jl`: Validation and auditing tests

Run tests:
```bash
julia --project=. test/runtests.jl
```

All tests use temporary directories for isolation and cleanup.

## Implemented Features

### Phase 1 (MVP) - COMPLETE

1. ✅ **Key Generation**
   - Ed25519, RSA-2048/4096, ECDSA-P256/P384
   - Post-quantum stub (Dilithium2/3/5, Kyber512/768/1024)
   - Hybrid quantum-resistant (Ed25519 + Dilithium3)
   - Expiration dates, comments, custom names

2. ✅ **Key Management**
   - List keys (table/JSON output)
   - View detailed key information
   - Validate key pairs
   - Security auditing with strength assessment
   - Fingerprint computation

3. ✅ **Storage & Backup**
   - Secure key storage (0600/0700 permissions)
   - JSON metadata with UUIDs
   - Individual and bulk backups
   - Backup retention management
   - Full restore capabilities

4. ✅ **Key Rotation**
   - Manual rotation with backup
   - Auto-rotation for expiring keys
   - Emergency rotation (all keys)
   - Rotation reports and tracking

5. ✅ **GitHub Integration**
   - Upload keys to GitHub via API
   - List GitHub SSH keys
   - Delete keys from GitHub
   - Token validation
   - Configuration-based and CLI-based tokens

6. ✅ **CLI Interface**
   - 10 commands with full argument parsing
   - Help system and version info
   - Verbose and JSON output modes
   - Error handling with custom exceptions
   - Logging with multiple verbosity levels

7. ✅ **Configuration**
   - TOML configuration files
   - Environment variable support
   - Customizable storage paths
   - Security settings
   - GitHub token management

8. ✅ **Documentation**
   - Quick start guide
   - Comprehensive user guide
   - Working examples (3 shell scripts)
   - Installation script
   - README with architecture overview

9. ✅ **CI/CD**
   - GitHub Actions workflow
   - Multi-Julia version testing (1.9, 1.10, nightly)
   - Cross-platform testing (Ubuntu, macOS, Windows)
   - Code quality checks
   - Security scanning

## Future Development Areas (Phase 2+)

### Phase 2: Enhanced Security
1. Full PQC implementation (integrate NistyPQC.jl)
2. Multi-factor authentication (TOTP, hardware keys)
3. Hardware security module (HSM) support
4. Backup encryption with passphrase
5. Key sharing and delegation
6. Email notifications for expiration
7. Malware scanner integration (use submodule)

### Phase 3: Enterprise Features
1. Team management and collaboration
2. Role-based access control (RBAC)
3. Centralized key management server
4. Compliance reporting (SOC2, ISO 27001)
5. Integration with vaults (HashiCorp Vault, AWS Secrets Manager)
6. GUI interface (web-based)
7. Audit log export (SIEM integration)
8. API server mode

## Working with Claude Code

When implementing features:
- Read relevant Julia documentation for cryptographic operations
- Check for existing Julia packages that provide quantum-resistant algorithms
- Consider using established libraries like `Nettle.jl`, `LibSodium.jl`, or similar
- Ensure all cryptographic operations follow current best practices
- Add appropriate logging using the Logging module
- Update this CLAUDE.md as the project evolves

## References

- Julia Documentation: https://docs.julialang.org/
- Quantum-Resistant Cryptography: NIST Post-Quantum Cryptography Project
- SSH Protocol: RFC 4251-4254
