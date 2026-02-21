# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Currently supported versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**DO NOT** open a public GitHub issue for security vulnerabilities.

### Preferred Method: Security Advisory

1. Go to the [Security Advisories](https://github.com/Hyperpolymath/broad-spectrum/security/advisories) page
2. Click "Report a vulnerability"
3. Fill out the form with details

### Alternative: Direct Contact

If you prefer email or the advisory system is unavailable:

- **Email**: security@hyperpolymath.org
- **PGP Key**: Available at `.well-known/security.txt`
- **Response Time**: Within 48 hours for acknowledgment, 7 days for triage

### What to Include

Please provide:

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Affected versions**
4. **Potential impact** assessment
5. **Suggested fix** (if available)
6. **CVE request** (if you want to request one)

### Disclosure Policy

We follow **Coordinated Vulnerability Disclosure**:

1. **Report received** - We acknowledge within 48 hours
2. **Investigation** - We confirm and assess severity (7 days)
3. **Fix development** - We create and test a patch (14-30 days)
4. **Pre-disclosure** - We notify you before public release (7 days notice)
5. **Public disclosure** - We release fix and advisory simultaneously
6. **Credit** - We publicly credit reporters (unless you prefer anonymity)

### Embargo Period

We request a **90-day embargo** for critical vulnerabilities to allow:
- Fix development and testing
- Coordination with downstream users
- Patch deployment preparation

### Security Patch Process

1. **Private fix** developed in a private repository fork
2. **Testing** against the vulnerability and regression suite
3. **Release preparation** with CHANGELOG entry
4. **Coordinated release** with security advisory
5. **CVE assignment** (if applicable)

## Security Measures

### Code Security

- **Type Safety**: ReScript provides compile-time type checking
- **No Unsafe Code**: No `eval()`, no arbitrary code execution
- **Dependency Scanning**: Automated vulnerability checks
- **Input Validation**: All user inputs sanitized
- **Output Encoding**: Proper escaping for all outputs

### Network Security

- **HTTPS Only**: All network requests use HTTPS
- **Timeout Enforcement**: Strict timeout on all HTTP requests
- **Rate Limiting**: Configurable concurrency limits
- **No Credentials**: No authentication data stored or transmitted

### Deno Security

- **Explicit Permissions**: Requires `--allow-net`, `--allow-read`
- **Sandboxed Execution**: No filesystem writes without explicit permission
- **No Environment Leakage**: Minimal environment variable access

### Third-Party Dependencies

We minimize dependencies and monitor them for vulnerabilities:

```
Dependencies:
- @rescript/core: Official ReScript standard library
- rescript: ReScript compiler
- gentype: TypeScript FFI generator

Runtime (Deno):
- No npm dependencies at runtime
- Uses Deno standard library
```

## Known Security Considerations

### Not a Security Audit Tool

**Important**: This tool is for website **auditing**, not security **testing**. It:

- ✅ Checks for best practices (HTTPS, headers, meta tags)
- ✅ Validates accessibility and SEO
- ❌ Does NOT perform penetration testing
- ❌ Does NOT scan for SQL injection, XSS, etc.
- ❌ Does NOT test authentication/authorization

For security testing, use dedicated tools like:
- OWASP ZAP
- Burp Suite
- Nuclei
- Nmap

### Rate Limiting

When auditing websites:
- Respect `robots.txt`
- Use reasonable concurrency limits (default: 10)
- Add delays between requests (default: 500ms)
- Set appropriate timeouts (default: 30s)
- Avoid DDoS-like behavior

### Data Privacy

- **No Data Collection**: This tool collects no telemetry
- **No External Requests**: Only fetches URLs you specify
- **No Data Transmission**: Results stay on your machine
- **GDPR Compliant**: No personal data processing

### Audit Logs

For security-sensitive deployments:

```bash
# Log all audits
deno task audit --url $URL --verbose 2>&1 | tee audit.log

# Include timestamps
deno task audit --url $URL 2>&1 | ts '[%Y-%m-%d %H:%M:%S]' | tee audit.log
```

## Security Best Practices

### Running in Production

```bash
# Minimal permissions
deno run \
  --allow-net=example.com \
  --allow-read=./urls.txt \
  src/main.ts --url https://example.com

# Read-only filesystem (when using Docker)
docker run --read-only broad-spectrum

# Drop privileges (when running as service)
sudo -u nobody deno task audit --url $URL
```

### CI/CD Security

```yaml
# GitHub Actions example
- name: Run audit
  run: deno task audit --url ${{ secrets.AUDIT_URL }}
  env:
    # No credentials needed
    DENO_PERMISSIONS: "--allow-net --allow-read"
```

### Sandboxing

For untrusted URLs or maximum isolation:

```bash
# Run in Docker container
docker run --rm \
  --network=host \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  broad-spectrum audit --url https://untrusted.example

# Run with Firejail
firejail --net=none --private deno task audit --file urls.txt
```

## Vulnerability Response Timeline

| Severity | Acknowledgment | Triage | Fix | Disclosure |
|----------|---------------|--------|-----|------------|
| Critical | 24 hours | 2 days | 7 days | 14 days |
| High | 48 hours | 7 days | 14 days | 30 days |
| Medium | 7 days | 14 days | 30 days | 60 days |
| Low | 14 days | 30 days | 90 days | 90 days |

## Security Champions

The following individuals are responsible for security:

- **Security Lead**: [To be assigned]
- **Backup**: All maintainers (see MAINTAINERS.md)

## Security Advisories

Past security advisories: None yet (project is new)

## Third-Party Security Research

We welcome security research! Researchers who report valid vulnerabilities receive:

- Public credit (unless anonymous preferred)
- Entry in our security hall of fame
- Coordinated disclosure process
- (No bug bounty program at this time)

## Compliance

This security policy aims to comply with:

- **RFC 9116**: security.txt standard
- **ISO 29147**: Vulnerability disclosure
- **ISO 30111**: Vulnerability handling
- **CWE/SANS Top 25**: Common weakness enumeration
- **OWASP Top 10**: Web application security

## Updates

This security policy is reviewed quarterly and updated as needed.

Last updated: 2025-11-22

---

For general questions, use GitHub Discussions.
For security issues, use the methods above.
