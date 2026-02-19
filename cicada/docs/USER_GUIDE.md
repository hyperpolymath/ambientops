# CIcaDA User Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Key Concepts](#key-concepts)
3. [Configuration](#configuration)
4. [Key Generation](#key-generation)
5. [Key Management](#key-management)
6. [Security Features](#security-features)
7. [GitHub Integration](#github-integration)
8. [Best Practices](#best-practices)

## Introduction

CIcaDA (Palimpsest Crypto Identity) is a quantum-resistant cryptographic identity management system. It provides:

- Classical SSH key generation (Ed25519, RSA, ECDSA)
- Post-quantum cryptography support (Dilithium, Kyber)
- Hybrid quantum-resistant keys
- Automated key rotation
- GitHub integration
- Backup and recovery
- Security auditing

## Key Concepts

### Key Algorithms

**Classical Algorithms:**
- **Ed25519**: Modern, fast, secure (recommended for most use cases)
- **RSA-2048/4096**: Traditional, widely supported
- **ECDSA-P256/P384**: Elliptic curve, compact

**Post-Quantum Algorithms:**
- **Dilithium2/3/5**: Digital signatures (NIST standardized)
- **Kyber512/768/1024**: Key encapsulation (NIST standardized)
- **Hybrid**: Combines Ed25519 + Dilithium3 for maximum security

### Key Purposes

- **SSH_AUTH**: SSH authentication
- **CODE_SIGNING**: Code signing
- **ENCRYPTION**: Data encryption
- **HYBRID_QR**: Hybrid quantum-resistant operations

### Key Metadata

Each key includes:
- Unique ID (UUID)
- Algorithm type
- Creation date
- Expiration date (optional)
- Email address
- Comment
- Fingerprint
- Quantum-resistant flag

## Configuration

### Configuration File

Located at `~/.cicada/config.toml`:

```toml
[storage]
key_dir = "/home/user/.cicada/keys"
backup_dir = "/home/user/.cicada/backups"

[security]
key_size = 4096
quantum_resistant = true
require_mfa = false

[github]
token = "your_github_token"
username = "your_username"

[logging]
verbosity = 2  # 0=errors, 1=warnings, 2=info, 3=debug
```

### Environment Variables

- `CICADA_CONFIG`: Override config file path
- `CICADA_KEY_DIR`: Override key directory
- `GITHUB_TOKEN`: GitHub personal access token

## Key Generation

### Generate Ed25519 Key (Recommended)

```bash
julia --project=. src/main.jl generate \
  -e your@email.com \
  -c "Work laptop" \
  --expires 2025-12-31
```

### Generate RSA Key

```bash
# RSA-4096 (recommended)
julia --project=. src/main.jl generate -e your@email.com -a rsa4096

# RSA-2048 (less secure, not recommended)
julia --project=. src/main.jl generate -e your@email.com -a rsa2048
```

### Generate ECDSA Key

```bash
# ECDSA-P256
julia --project=. src/main.jl generate -e your@email.com -a ecdsa256

# ECDSA-P384
julia --project=. src/main.jl generate -e your@email.com -a ecdsa384
```

### Generate Post-Quantum Keys

```bash
# Dilithium3 (recommended PQC level)
julia --project=. src/main.jl generate -e your@email.com -a dilithium3

# Kyber768 (for encryption)
julia --project=. src/main.jl generate -e your@email.com -a kyber768

# Hybrid (classical + PQC)
julia --project=. src/main.jl generate -e your@email.com -a hybrid
```

**Note**: Current PQC implementation is a stub. For production use, install NistyPQC.jl.

### Custom Key Name

```bash
julia --project=. src/main.jl generate \
  -e your@email.com \
  -n my_custom_key
```

## Key Management

### List Keys

```bash
# Table format
julia --project=. src/main.jl list

# JSON format
julia --project=. src/main.jl list --format json

# Verbose (show paths and fingerprints)
julia --project=. src/main.jl list --verbose
```

### View Key Information

```bash
julia --project=. src/main.jl info --id YOUR_KEY_ID
```

### Validate Key

```bash
julia --project=. src/main.jl validate --id YOUR_KEY_ID
```

Validation checks:
- Public key format
- Private key format
- Key pair match
- Expiration status
- Algorithm strength

### Backup Keys

Backup single key:

```bash
julia --project=. src/main.jl backup --id YOUR_KEY_ID
```

Backup all keys:

```bash
julia --project=. src/main.jl backup
```

Clean old backups (keep 5 most recent per key):

```bash
julia --project=. src/main.jl backup --clean 5
```

### Restore Keys

```bash
julia --project=. src/main.jl restore \
  --backup-path ~/.cicada/backups/backup_XXXXX_20240101_120000
```

### Key Rotation

Rotate specific key:

```bash
julia --project=. src/main.jl rotate --id YOUR_KEY_ID
```

Auto-rotate expiring keys (default: 30 days before expiration):

```bash
julia --project=. src/main.jl rotate --auto
```

Custom warning period (60 days):

```bash
julia --project=. src/main.jl rotate --auto --warning-days 60
```

Emergency rotation (all keys):

```bash
julia --project=. src/main.jl rotate --all
```

## Security Features

### Security Audit

Audit all keys:

```bash
julia --project=. src/main.jl audit
```

Audit specific key (JSON output):

```bash
julia --project=. src/main.jl audit --id YOUR_KEY_ID --format json
```

Audit report includes:
- Algorithm strength assessment
- Key age
- Expiration status
- Validation results
- Quantum-resistance status
- Security recommendations

### Post-Quantum Cryptography

Check PQC support:

```bash
julia --project=. src/main.jl pqc-info
```

### Automatic Key Rotation

Set up cron job for automatic rotation:

```bash
# Add to crontab (runs daily at midnight)
0 0 * * * cd /path/to/CIcaDA && julia --project=. src/main.jl rotate --auto
```

## GitHub Integration

### Setup

Add GitHub token to config:

```toml
[github]
token = "ghp_YOUR_TOKEN"
username = "your_username"
```

Or use command-line:

```bash
--token ghp_YOUR_TOKEN
```

### Upload Key to GitHub

```bash
julia --project=. src/main.jl github \
  --action upload \
  --id YOUR_KEY_ID \
  --token ghp_YOUR_TOKEN \
  --title "My CIcaDA Key"
```

### List GitHub Keys

```bash
julia --project=. src/main.jl github \
  --action list \
  --token ghp_YOUR_TOKEN
```

### Delete Key from GitHub

```bash
julia --project=. src/main.jl github \
  --action delete \
  --github-key-id 12345 \
  --token ghp_YOUR_TOKEN
```

### Verify Token

```bash
julia --project=. src/main.jl github \
  --action verify-token \
  --token ghp_YOUR_TOKEN
```

## Best Practices

### Key Selection

1. **General use**: Ed25519 (fast, secure, modern)
2. **Legacy systems**: RSA-4096 (widely supported)
3. **High security**: Hybrid (classical + PQC)
4. **Future-proofing**: Dilithium3

### Key Lifecycle

1. Generate with expiration (90-365 days)
2. Back up immediately
3. Upload to GitHub
4. Set up auto-rotation
5. Regular audits (monthly)

### Security

1. **Always set expiration dates**
2. **Never share private keys**
3. **Regular backups** (automated)
4. **Monitor expiration** (auto-rotate)
5. **Audit regularly** (check for weak keys)
6. **Use quantum-resistant keys** for long-term security

### Performance

- Ed25519: Fastest
- ECDSA: Fast
- RSA: Slower
- PQC: Slowest (but most secure long-term)

### Storage

- Keys stored in `~/.cicada/keys` (mode 0700)
- Private keys have mode 0600
- Public keys have mode 0644
- Backups in `~/.cicada/backups` (mode 0700)

### Compliance

- NIST post-quantum standards (Dilithium, Kyber)
- SSH RFC 4251-4254 compatibility
- Secure by default configurations
- Audit trail for all operations
