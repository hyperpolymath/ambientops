<!-- SPDX-License-Identifier: MPL-2.0 -->
# CIcaDA - TOPOLOGY

## System Architecture

```
                    +---------------------------+
                    |       CIcaDA CLI          |
                    |   (src/main.jl - 680 LOC) |
                    |   11 commands, ArgParse   |
                    +------+----------+---------+
                           |          |
              +------------+          +-------------+
              |                                     |
    +---------v---------+              +------------v-----------+
    |   Configuration   |              |    Key Generation      |
    |   (config.jl)     |              |    (keygen/)           |
    |                   |              |                        |
    |  TOML config      |              |  classical.jl  [PROD] |
    |  Env vars         |              |  postquantum.jl [STUB]|
    |  ~/.cicada/       |              |  types.jl             |
    +-------------------+              +-----+-------+--+------+
                                             |       |  |
                                 +-----------+  +----+  +--------+
                                 |              |                 |
                        +--------v------+  +----v------+  +------v--------+
                        |   Storage     |  | Validation|  | Integrations  |
                        |  (storage/)   |  | (valid/)  |  | (integr/)     |
                        |               |  |           |  |               |
                        | keystore.jl   |  | verify.jl |  | github.jl     |
                        | backup.jl     |  | audit     |  | GitHub API    |
                        | rotation.jl   |  | strength  |  | upload/list/  |
                        +-------+-------+  +-----------+  |   delete      |
                                |                         +---------------+
                                v
                        +---------------+
                        |  ~/.cicada/   |
                        |  keys/ (0700) |
                        |  backups/     |
                        |  config.toml  |
                        +---------------+

    External Dependencies:
    +-------------+  +-----------+  +--------+  +----------+
    | OpenSSH_jll |  | Nettle.jl |  | HTTP.jl|  | JSON3.jl |
    | (keygen)    |  | (hashing) |  | (API)  |  | (serde)  |
    +-------------+  +-----------+  +--------+  +----------+

    Ecosystem Integration:
    +------------+  +-----------+  +---------+  +----------+
    | ambientops |  |  panic-   |  | hypatia |  | gitbot-  |
    | (parent)   |  |  attacker |  | (CI/CD) |  | fleet    |
    +------------+  +-----------+  +---------+  +----------+
```

## Completion Dashboard

### Phase 1: MVP
```
Key Generation (Classical)   [##########] 100%  Ed25519, RSA, ECDSA
Key Generation (PQC Stubs)   [##########] 100%  Dilithium, Kyber architecture
Key Management               [##########] 100%  list, info, validate, audit
Storage & Backup             [##########] 100%  store, backup, restore, retain
Key Rotation                 [##########] 100%  manual, auto, emergency
GitHub Integration           [##########] 100%  upload, list, delete, verify
CLI Interface                [##########] 100%  11 commands, ArgParse
Configuration                [##########] 100%  TOML, env vars, paths
Documentation                [##########] 100%  quickstart, guide, examples
CI/CD Pipeline               [##########] 100%  Actions, multi-OS, multi-Julia
Test Suite                   [##########] 100%  types, config, keygen, storage, validation
```

### Phase 2: Enhanced Security
```
Full PQC (NistyPQC.jl)      [░░░░░░░░░░]   0%  Blocked on library maturity
Multi-Factor Auth (TOTP)     [░░░░░░░░░░]   0%  Planned
Hardware Security Keys       [░░░░░░░░░░]   0%  Planned (YubiKey)
Backup Encryption            [░░░░░░░░░░]   0%  Argon2id + AES-256-GCM
Platform Installers          [░░░░░░░░░░]   0%  Windows, macOS, Linux
Key Sharing/Delegation       [░░░░░░░░░░]   0%  Planned
Expiry Notifications         [░░░░░░░░░░]   0%  Planned
Malware Scanner Integration  [█░░░░░░░░░]  10%  Submodule exists, not wired
```

### Phase 3: Enterprise
```
Team Management              [░░░░░░░░░░]   0%  Planned
RBAC                         [░░░░░░░░░░]   0%  Planned
Centralized Key Server       [░░░░░░░░░░]   0%  Planned
Compliance Reporting         [░░░░░░░░░░]   0%  SOC2, ISO 27001
Vault Integrations           [░░░░░░░░░░]   0%  HashiCorp, AWS SM
Web GUI                      [░░░░░░░░░░]   0%  Planned
SIEM Export                  [░░░░░░░░░░]   0%  Planned
API Server Mode              [░░░░░░░░░░]   0%  Planned
```

### Overall
```
Phase 1 (MVP)                [##########] 100%  COMPLETE
Phase 2 (Enhanced Security)  [░░░░░░░░░░]   1%  NOT STARTED
Phase 3 (Enterprise)         [░░░░░░░░░░]   0%  NOT STARTED
─────────────────────────────────────────────
Overall Project              [██████░░░░]  65%  Phase 1 done, Phases 2-3 pending
```

## Key Dependencies

| Dependency | Type | Purpose | Status |
|------------|------|---------|--------|
| Julia 1.9+ | Runtime | Primary language | Required |
| OpenSSH_jll | Julia pkg | SSH key generation | Installed |
| Nettle.jl | Julia pkg | Cryptographic hashing | Installed |
| HTTP.jl | Julia pkg | GitHub API calls | Installed |
| JSON3.jl | Julia pkg | JSON serialization | Installed |
| ArgParse.jl | Julia pkg | CLI argument parsing | Installed |
| NistyPQC.jl | Julia pkg | Production PQC | **NOT YET** (Phase 2) |
| TOTP.jl | Julia pkg | MFA implementation | **NOT YET** (Phase 2) |
| ambientops | Parent repo | Monorepo integration | Active |
| malware-scanner | Git submodule | Security scanning | Exists, not integrated |
