# Security Policy - CIcaDA

## Overview

CIcaDA (Palimpsest Crypto Identity) handles cryptographic key material and should be treated as **security-critical software**. This document describes our security policies, vulnerability disclosure process, and security best practices.

## Supported Versions

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| 0.1.x   | :white_check_mark: | Active |
| < 0.1   | :x:                | N/A    |

We provide security updates for the current minor version only.

## Security Architecture

### Threat Model

CIcaDA protects against:

1. **Key Compromise**
   - Unauthorized access to private keys
   - Key material leakage through logs/errors
   - Insecure key storage

2. **Cryptographic Attacks**
   - Weak algorithm selection
   - Improper key generation
   - Timing attacks on key operations

3. **Quantum Attacks** (Future)
   - Post-quantum cryptography readiness
   - Hybrid classical + PQC keys

4. **Supply Chain Attacks**
   - Dependency vulnerabilities
   - Malicious package injection
   - Build system compromise

### Security Controls

1. **Secure Storage**
   - Private keys: `0600` permissions (owner read/write only)
   - Key directories: `0700` permissions (owner access only)
   - Metadata: `0600` permissions
   - No keys in logs or error messages

2. **Cryptographic Operations**
   - Use established libraries (`ssh-keygen`, `Nettle.jl`)
   - No custom crypto implementations (except PQC stubs)
   - Secure random number generation
   - Constant-time comparisons (where applicable)

3. **Input Validation**
   - All user inputs validated
   - Email format validation
   - UUID validation
   - Path traversal prevention
   - Command injection prevention

4. **Audit Trail**
   - All key operations logged
   - Security events logged
   - Timestamped audit records
   - No sensitive data in logs

## Vulnerability Disclosure

### Reporting a Vulnerability

**DO NOT** create public GitHub issues for security vulnerabilities.

**DO** report privately to: **security@hyperpolymath.org**

Include:
1. **Description**: Detailed vulnerability description
2. **Reproduction**: Step-by-step reproduction steps
3. **Impact**: Potential security impact
4. **Affected Versions**: Which versions are vulnerable
5. **Fix Suggestion**: Proposed fix (if available)
6. **Disclosure Timeline**: Your intended disclosure timeline

### What to Expect

1. **Acknowledgment**: Within 48 hours
2. **Initial Assessment**: Within 7 days
3. **Status Updates**: Every 7 days until resolution
4. **Fix Timeline**:
   - Critical: 7 days
   - High: 30 days
   - Medium: 90 days
   - Low: Next release

### Disclosure Policy

We follow **responsible disclosure**:

1. Report received → Acknowledgment
2. Vulnerability verified → Internal fix development
3. Fix ready → Notification to reporter
4. Fix tested → Security advisory draft
5. Fix released → Public disclosure (with credit)

**Embargo Period**: 90 days from initial report (negotiable)

### Bug Bounty

Currently, CIcaDA does not offer a bug bounty program. We recognize contributions through:
- Public acknowledgment
- CVE credit
- Listed in security hall of fame
- Listed in `SECURITY.md#Acknowledgments`

## Security Best Practices

### For Users

1. **Key Generation**
   ```bash
   # Good: Ed25519 with expiration
   julia --project=. src/main.jl generate \
     -e user@example.com \
     --expires 2026-12-31 \
     -a ed25519

   # Better: Hybrid quantum-resistant
   julia --project=. src/main.jl generate \
     -e user@example.com \
     --expires 2026-12-31 \
     -a hybrid
   ```

2. **Key Storage**
   - Never commit keys to git
   - Use `.gitignore` for key directories
   - Regular backups with encryption
   - Offsite backup storage

3. **Key Rotation**
   ```bash
   # Schedule automatic rotation
   0 0 * * * cd /path/to/CIcaDA && \
     julia --project=. src/main.jl rotate --auto
   ```

4. **GitHub Integration**
   - Use fine-grained Personal Access Tokens
   - Minimum required scopes: `write:public_key`
   - Rotate tokens every 90 days
   - Store tokens in config file (not CLI)

5. **Audit Regularly**
   ```bash
   # Monthly security audit
   julia --project=. src/main.jl audit
   ```

### For Developers

1. **Secure Coding**
   - Never log private keys
   - Validate all inputs
   - Use parameterized commands (prevent injection)
   - Set secure file permissions
   - Handle errors securely

2. **Dependencies**
   - Keep dependencies updated
   - Review dependency advisories
   - Use `Pkg.audit()` regularly
   - Pin critical dependencies

3. **Testing**
   - Test security controls
   - Test error handling
   - Test permission handling
   - Test input validation
   - Test crypto operations

4. **Code Review**
   - Security-critical code requires expert review
   - Check for timing attacks
   - Verify secure defaults
   - Review error messages
   - Check file permissions

## Security Features

### Current (v0.1)

- ✅ Secure key storage (0600/0700 permissions)
- ✅ Key validation and verification
- ✅ Expiration tracking
- ✅ Algorithm strength assessment
- ✅ Audit logging
- ✅ GitHub PAT integration
- ✅ Backup and recovery
- ✅ Key rotation

### Planned (v0.2+)

- 🔲 Multi-factor authentication (TOTP, hardware keys)
- 🔲 Hardware security module (HSM) support
- 🔲 Backup encryption
- 🔲 Key sharing with encryption
- 🔲 Full post-quantum cryptography (NistyPQC.jl)
- 🔲 Email notifications for expiration
- 🔲 Malware scanner integration

## Known Limitations

### Post-Quantum Cryptography

**Current Status**: Stub implementation only

- Dilithium and Kyber keys are placeholders
- NOT suitable for production use
- Architecture ready for NistyPQC.jl integration
- Full PQC planned for Phase 2

**Recommendation**: Use hybrid keys (Ed25519 + Dilithium3) in preparation for future PQC support.

### Offline-First

- GitHub integration requires network access
- Key generation works offline (via `ssh-keygen`)
- Key management fully offline capable
- Backup/restore fully offline

### Julia Security

- Julia is memory-safe (garbage collected)
- No buffer overflows or use-after-free
- Type system provides safety
- FFI to native code (`ssh-keygen`) trusted

## Security Advisories

### Published Advisories

*None yet - project just launched!*

### Subscribe to Advisories

- GitHub: Watch repository → Custom → Security alerts
- Email: security-announce@hyperpolymath.org
- RSS: https://github.com/Hyperpolymath/CIcaDA/security/advisories.atom

## Acknowledgments

We thank the following security researchers:

*None yet - be the first!*

### Hall of Fame

Security researchers who have responsibly disclosed vulnerabilities will be listed here with credit.

## Security Contacts

- **Vulnerability Reports**: security@hyperpolymath.org
- **Security Questions**: security@hyperpolymath.org
- **PGP Key**: https://github.com/Hyperpolymath.gpg
- **Security Policy**: https://github.com/Hyperpolymath/CIcaDA/blob/main/SECURITY.md

## External Security Resources

- **NIST PQC**: https://csrc.nist.gov/Projects/post-quantum-cryptography
- **OpenSSH Security**: https://www.openssh.com/security.html
- **Julia Security**: https://julialang.org/blog/2019/02/julia-entities/
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **CWE Top 25**: https://cwe.mitre.org/top25/

## Compliance

### Standards Followed

- **RFC 9116**: security.txt implementation
- **NIST SP 800-63B**: Digital identity guidelines
- **NIST SP 800-57**: Key management
- **FIPS 186-5**: Digital signature standard
- **RSR Framework**: Rhodium Standard Repository

### Certifications

*None yet - seeking SOC 2, ISO 27001 guidance*

## Security Roadmap

### Q1 2026
- Multi-factor authentication
- HSM support
- Full PQC implementation

### Q2 2026
- Backup encryption
- Email notifications
- Malware scanner integration

### Q3 2026
- SOC 2 Type 1 preparation
- External security audit
- Penetration testing

### Q4 2026
- Bug bounty program
- Security certifications
- Advanced threat detection

---

**Last Updated**: 2025-11-22
**Policy Version**: 1.0
**Next Review**: 2026-02-22

This security policy follows the RSR Framework security guidelines.
