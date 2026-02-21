# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.x.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please follow responsible disclosure practices:

### For Non-Critical Issues
Open a GitHub issue with the `security` label, avoiding specific exploit details.

### For Critical/Sensitive Issues
1. **Do NOT** open a public issue
2. Email the maintainers directly (see CODEOWNERS or git log for contact)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Any suggested remediation

### Response Timeline
- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Resolution Target**: Within 30 days (severity dependent)

## Security Measures in This Repository

### CI/CD Pipeline
- GitHub Actions with minimal permissions (`contents: read`)
- Pinned action versions using commit SHA (supply chain protection)
- SSH host key verification (MITM protection)
- Job timeouts to prevent resource exhaustion
- Concurrency controls to prevent race conditions

### Code Practices
- Strict shell scripts (`set -euo pipefail`)
- No credential storage in code
- Secrets managed via GitHub organization secrets
- AGPL-3.0-or-later license ensures transparency

## Security-Related Configuration

### Required GitHub Repository Settings
For optimal security, ensure these repository settings:

1. **Branch Protection** (main/master)
   - Require pull request reviews
   - Require status checks
   - Require signed commits (recommended)
   - Disable force push

2. **Secrets**
   - Use organization-level secrets for SSH keys
   - Rotate keys periodically
   - Use deploy keys with minimal permissions

3. **Actions**
   - Limit actions to selected repositories
   - Require approval for first-time contributors

## Acknowledgments

We thank all security researchers who responsibly disclose vulnerabilities.
