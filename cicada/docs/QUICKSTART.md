# CIcaDA Quick Start Guide

## Installation

### Prerequisites
- Julia 1.9 or higher
- `ssh-keygen` (for classical key generation)
- Git (for cloning the repository)

### Install

```bash
git clone https://github.com/Hyperpolymath/CIcaDA.git
cd CIcaDA
git submodule update --init --recursive
./install.sh
```

## Basic Usage

### Initialize CIcaDA

```bash
julia --project=. src/main.jl init
```

This creates:
- Configuration file: `~/.cicada/config.toml`
- Key directory: `~/.cicada/keys`
- Backup directory: `~/.cicada/backups`

### Generate Your First Key

Generate an Ed25519 SSH key (recommended):

```bash
julia --project=. src/main.jl generate -e your@email.com
```

Generate with custom algorithm:

```bash
# RSA-4096
julia --project=. src/main.jl generate -e your@email.com -a rsa4096

# ECDSA-P256
julia --project=. src/main.jl generate -e your@email.com -a ecdsa256

# Hybrid quantum-resistant (Ed25519 + Dilithium3)
julia --project=. src/main.jl generate -e your@email.com -a hybrid
```

### List Your Keys

```bash
julia --project=. src/main.jl list
```

Verbose output:

```bash
julia --project=. src/main.jl list --verbose
```

### View Key Details

```bash
julia --project=. src/main.jl info --id YOUR_KEY_ID
```

### Validate a Key

```bash
julia --project=. src/main.jl validate --id YOUR_KEY_ID
```

### Security Audit

Audit all keys:

```bash
julia --project=. src/main.jl audit
```

Audit specific key:

```bash
julia --project=. src/main.jl audit --id YOUR_KEY_ID
```

### Backup Keys

Backup all keys:

```bash
julia --project=. src/main.jl backup
```

Backup specific key:

```bash
julia --project=. src/main.jl backup --id YOUR_KEY_ID
```

### Restore from Backup

```bash
julia --project=. src/main.jl restore --backup-path ~/.cicada/backups/backup_XXXXX
```

### Key Rotation

Rotate a specific key:

```bash
julia --project=. src/main.jl rotate --id YOUR_KEY_ID
```

Auto-rotate expiring keys:

```bash
julia --project=. src/main.jl rotate --auto
```

### GitHub Integration

Upload key to GitHub:

```bash
julia --project=. src/main.jl github --action upload --id YOUR_KEY_ID --token YOUR_GITHUB_TOKEN
```

List GitHub keys:

```bash
julia --project=. src/main.jl github --action list --token YOUR_GITHUB_TOKEN
```

## Next Steps

- Read the [User Guide](USER_GUIDE.md) for detailed documentation
- Explore [examples](examples/) for common workflows
- Configure GitHub token in `~/.cicada/config.toml`
- Set up automatic key rotation with cron

## Common Workflows

### Daily Development Setup

1. Generate a key
2. Upload to GitHub
3. Set expiration for 90 days
4. Set up auto-rotation

```bash
# Generate with expiration
julia --project=. src/main.jl generate -e dev@example.com --expires 2024-12-31

# Upload to GitHub
julia --project=. src/main.jl github --action upload --id YOUR_KEY_ID --token YOUR_TOKEN

# Schedule rotation check (add to crontab)
0 0 * * * cd /path/to/CIcaDA && julia --project=. src/main.jl rotate --auto
```

### Security Incident Response

```bash
# Rotate ALL keys immediately
julia --project=. src/main.jl rotate --all

# Audit all keys
julia --project=. src/main.jl audit

# Backup everything
julia --project=. src/main.jl backup
```
