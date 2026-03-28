# Security Policy

## Core Security Guarantees

✅ **100% Local Processing** - Zero network calls, verified by self-audit
✅ **Ephemeral Data Only** - No persistent personal data storage
✅ **Explicit Consent** - No system access without permission
✅ **Self-Auditing** - Built-in privacy verification (Mode 6)
✅ **Open Source** - MIT License, community reviewable

---

## Supported Versions

| Version | Supported | End of Support |
|---------|-----------|----------------|
| 1.0.x   | ✅ Yes    | 2026-11-22     |
| < 1.0   | ❌ Dev    | N/A            |

**Security update timeline:**
- **CRITICAL** (privacy violation): 24-48 hours
- **HIGH** (security vulnerability): 7 days
- **MEDIUM**: 30 days
- **LOW**: Next release

---

## Reporting a Vulnerability

### Severity Levels

**CRITICAL** - Privacy violations (network calls, data persistence, tracking)
**HIGH** - Security vulnerabilities (injection, unauthorized access)
**MEDIUM** - Security issues with workarounds
**LOW** - Hardening opportunities

### How to Report

**Preferred Method:**
1. Create security advisory: https://github.com/Hyperpolymath/jusys/security/advisories/new
2. **DO NOT** create public issues for security vulnerabilities
3. Include:
   - Detailed reproduction steps
   - Affected version (`julia --version`)
   - Affected modules/files
   - For privacy violations: Self-audit output (Mode 6)

**Alternative:**
- Email: (Create issue first for contact)
- PGP: Available upon request for sensitive disclosures

### What to Expect

1. **Acknowledgment**: Within 48 hours
2. **Assessment**: Within 7 days
3. **Fix timeline**: Based on severity (see above)
4. **Disclosure**: Coordinated with reporter
5. **Credit**: Listed in SECURITY.md and release notes

---

## Security Features

### Privacy Architecture

**Hazard Triangle (ELIMINATE → SUBSTITUTE → CONTROL):**

1. **ELIMINATE** - NO PEEK Mode
   - Manual entry only
   - Zero system access
   - No permissions required

2. **SUBSTITUTE** - Local JSON Database
   - No API calls
   - No external dependencies
   - Works offline

3. **CONTROL** - Consent + Ephemeral Storage
   - Explicit permission requests
   - Memory-only processing
   - Automatic cleanup

### GDPR Compliance

Implements all 12 GDPR processing types:
1. Collection (user input, file import)
2. Recording (temporary in-memory)
3. Organization (categorization)
4. Structuring (classification)
5. Storage (ephemeral only)
6. Adaptation (risk scoring)
7. Retrieval (database lookups)
8. Consultation (user queries)
9. Use (analysis/reporting)
10. Disclosure (report exports with consent)
11. Dissemination (file writing with consent)
12. Erasure (automatic session cleanup)

### Self-Audit Capabilities

**Verify privacy compliance:**
```bash
julia --project=. -e 'include("src/cli.jl"); CLI.run()'
# Select Mode 6: Self-Audit
```

**Checks performed:**
- ✅ No network calls
- ✅ No persistent data files
- ✅ Consent framework active
- ✅ Ephemeral storage only
- ✅ Data minimization
- ✅ Auto-cleanup on exit

---

## Security Best Practices

### For Users

**Verify Installation:**
```bash
# Check database integrity
julia --project=. test/test_database.jl

# Run privacy tests
julia --project=. -e 'include("test/test_privacy.jl")'

# Self-audit
julia --project=. -e 'include("src/cli.jl"); CLI.run()'  # Mode 6
```

**Safe Usage:**
- Run in NO PEEK mode for maximum privacy
- Review exported reports before sharing
- Keep Julia and dependencies updated
- Use official releases only

### For Contributors

**Security Review Checklist:**
- [ ] No network calls added
- [ ] No persistent data storage
- [ ] Consent obtained before system access
- [ ] Input validation for all user input
- [ ] No unsafe code blocks (for Rust/other languages)
- [ ] Privacy tests pass
- [ ] Self-audit passes
- [ ] Documentation updated

**Required Tests:**
```bash
# All tests must pass
julia --project=. test/runtests.jl

# Privacy validation (CRITICAL)
julia --project=. -e 'include("test/test_privacy.jl")'

# Database integrity
julia --project=. test/test_database.jl
```

---

## Known Security Considerations

### By Design

**Local File System Access:**
- Required for: Database loading, report generation, import/export
- Scope: User-specified paths only
- Mitigation: Explicit consent, path validation

**Package Manager Queries:**
- Required for: Quick Scan and FULL AUDIT modes
- Scope: Read-only queries (apt list, winget list, etc.)
- Mitigation: Requires explicit consent, NO PEEK mode available

**Report Exports:**
- Required for: XLSX, Markdown, CSV, JSON, HTML generation
- Scope: User-specified output paths only
- Mitigation: Explicit consent, user controls location

### Not Applicable

**Network-Based Attacks:**
- ❌ No network stack
- ❌ No listening ports
- ❌ No external connections
- ✅ **100% immune to network-based attacks**

**Data Exfiltration:**
- ❌ No network calls
- ❌ No telemetry
- ❌ No cloud sync
- ✅ **Data cannot leave your system without explicit export**

---

## Security Audits

### Self-Audit Results

**Last self-audit:** 2025-11-22
**Result:** ✅ ALL CHECKS PASSED

Verified:
- ✅ Zero network calls in codebase
- ✅ No persistent data storage
- ✅ Consent framework operational
- ✅ Ephemeral data only
- ✅ Auto-cleanup on exit

### External Audits

No formal external security audits conducted yet.

**Want to audit?** We welcome security researchers:
- Review source code (MIT License)
- Run self-audit tool
- Report findings via security advisory
- Get credit in this document

---

## Threat Model

### In Scope

**Privacy Violations:**
- Network calls (violates core guarantee)
- Data persistence without consent
- Tracking or telemetry
- Consent bypass

**Security Vulnerabilities:**
- Command injection
- Path traversal
- Arbitrary file read/write
- Unauthorized system access

### Out of Scope

**Third-Party Dependencies:**
- Julia runtime vulnerabilities → Report to JuliaLang
- Package vulnerabilities → Report to package maintainers
- OS vulnerabilities → Report to OS vendor

**User Error:**
- Sharing exported reports (user responsibility)
- Running untrusted code
- Misconfiguration of package managers

**Physical Access:**
- Local privilege escalation (OS security)
- Physical memory access
- Hardware attacks

---

## Security Roadmap

### Completed ✅

- [x] Privacy-first architecture (v1.0.0)
- [x] Self-audit capabilities (v1.0.0)
- [x] Comprehensive testing (v1.0.0)
- [x] Documentation (SECURITY.md, .well-known/security.txt)

### Planned

- [ ] External security audit (Q1 2026)
- [ ] Automated security scanning in CI/CD
- [ ] Cryptographic signing of releases
- [ ] Reproducible builds verification
- [ ] SLSA compliance

---

## Acknowledgments

We thank the following security researchers for responsible disclosure:

_(No reports yet - be the first!)_

---

## References

- **RFC 9116** (security.txt): https://www.rfc-editor.org/rfc/rfc9116
- **GDPR Full Text**: https://gdpr-info.eu/
- **Julia Security**: https://julialang.org/security/
- **Project Ethics**: See [ETHICS.md](ETHICS.md)
- **Privacy Architecture**: See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)

---

## Contact

**Security issues:** https://github.com/Hyperpolymath/jusys/security/advisories/new
**General questions:** https://github.com/Hyperpolymath/jusys/issues
**security.txt:** [.well-known/security.txt](.well-known/security.txt)

---

**Last Updated:** 2025-11-22
**Version:** 1.0.0
**Status:** Production-Ready
