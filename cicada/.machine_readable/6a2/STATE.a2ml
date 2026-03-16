;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for CIcaDA (Crypto Identity)
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2024-12-28")
    (updated "2026-02-19")
    (project "CIcaDA")
    (repo "github.com/hyperpolymath/ambientops")
    (subpath "cicada/"))

  (project-context
    (name "CIcaDA - Palimpsest Crypto Identity")
    (tagline "Securing Digital Identities with Quantum-Resistant Precision")
    (tech-stack ("Julia 1.9+" "ArgParse" "HTTP.jl" "JSON3" "Nettle" "OpenSSH_jll" "TOML" "UUIDs"))
    (uuid "449d71e4-0569-4032-8a3c-f519b3386ebb"))

  (current-position
    (phase "phase-1-complete")
    (overall-completion 65)
    (components
      (key-generation
        (status "complete")
        (completion 100)
        (algorithms "Ed25519" "RSA-2048" "RSA-4096" "ECDSA-P256" "ECDSA-P384")
        (pqc-stubs "Dilithium2" "Dilithium3" "Dilithium5" "Kyber512" "Kyber768" "Kyber1024")
        (hybrid "Ed25519+Dilithium3"))
      (key-management
        (status "complete")
        (completion 100)
        (features "list" "info" "validate" "audit" "fingerprint"))
      (storage-and-backup
        (status "complete")
        (completion 100)
        (features "secure-storage" "json-metadata" "uuid-tracking" "individual-backup"
                  "bulk-backup" "retention-management" "full-restore"))
      (key-rotation
        (status "complete")
        (completion 100)
        (features "manual-rotation" "auto-rotation" "emergency-rotation" "rotation-reports"))
      (github-integration
        (status "complete")
        (completion 100)
        (features "upload-keys" "list-keys" "delete-keys" "token-validation"))
      (cli-interface
        (status "complete")
        (completion 100)
        (commands 11)
        (features "argparse" "help" "version" "verbose" "json-output" "error-handling" "logging"))
      (configuration
        (status "complete")
        (completion 100)
        (features "toml-config" "env-vars" "custom-paths" "security-settings" "github-token"))
      (documentation
        (status "complete")
        (completion 100)
        (features "quickstart" "user-guide" "examples" "install-script" "readme" "architecture"))
      (ci-cd
        (status "complete")
        (completion 100)
        (features "github-actions" "multi-julia-version" "cross-platform" "quality-checks" "security-scanning"))
      (multi-factor-auth
        (status "planned")
        (completion 0)
        (target "phase-2")
        (planned-features "totp" "hardware-keys" "yubikey"))
      (pqc-production
        (status "stub")
        (completion 15)
        (note "Current PQC is stub implementation; needs NistyPQC.jl for production")
        (target "phase-2"))
      (malware-scanner
        (status "submodule")
        (completion 10)
        (note "Git submodule at malware-scanner/, not yet integrated")))

    (working-features
      "classical-ssh-keygen"
      "pqc-stub-keygen"
      "hybrid-quantum-resistant"
      "automated-key-rotation"
      "security-auditing"
      "backup-and-recovery"
      "github-api-integration"
      "cli-with-11-commands"
      "toml-configuration"
      "comprehensive-test-suite"
      "cross-platform-ci"))

  (route-to-mvp
    (milestones
      (phase-1-mvp
        (status "complete")
        (target "2026-Q1")
        (deliverables
          "classical-keygen"
          "pqc-stubs"
          "key-management"
          "backup-recovery"
          "key-rotation"
          "github-integration"
          "cli-interface"
          "test-suite"
          "documentation"
          "ci-cd"))
      (phase-2-enhanced-security
        (status "planned")
        (target "2026-Q2")
        (deliverables
          "full-pqc-implementation"
          "multi-factor-auth-totp"
          "hardware-security-keys"
          "backup-encryption-passphrase"
          "key-sharing-delegation"
          "email-notifications-expiry"
          "malware-scanner-integration"))
      (phase-3-enterprise
        (status "planned")
        (target "2026-Q3")
        (deliverables
          "team-management"
          "rbac"
          "centralized-key-server"
          "compliance-reporting"
          "vault-integrations"
          "web-gui"
          "siem-export"
          "api-server-mode"))))

  (blockers-and-issues
    (critical
      (pqc-stub-only
        (description "Post-quantum cryptography is stub implementation only")
        (impact "Cannot be used for production PQC keys")
        (resolution "Integrate NistyPQC.jl when available and stable")))
    (high
      (no-mfa
        (description "Multi-factor authentication not yet implemented")
        (impact "Single-factor key access")
        (resolution "Phase 2: implement TOTP and hardware key support"))
      (no-backup-encryption
        (description "Backups not encrypted at rest")
        (impact "Backup files readable without passphrase")
        (resolution "Phase 2: add passphrase-based backup encryption")))
    (medium
      (malware-scanner-not-integrated
        (description "malware-scanner submodule exists but not integrated into workflow")
        (resolution "Phase 2: integrate scanning into key operations"))
      (cross-platform-installers
        (description "Platform-specific installers not yet built")
        (resolution "Phase 2: create Windows/macOS/Linux installers")))
    (low
      (ed448-not-supported
        (description "Ed448 mentioned in handover but not implemented; Ed25519 used instead")
        (resolution "Evaluate Ed448 vs Ed25519 trade-offs; Ed25519 is currently adequate"))))

  (critical-next-actions
    (immediate
      "integrate-handover-documentation"
      "update-scm-files-with-real-data"
      "verify-test-suite-passes")
    (this-week
      "evaluate-nistyPQC-jl-status"
      "design-totp-mfa-module"
      "integrate-malware-scanner-submodule")
    (this-month
      "begin-phase-2-implementation"
      "create-platform-installers"
      "implement-backup-encryption"))

  (session-history
    (session
      (date "2026-02-19")
      (agent "claude-opus-4-6")
      (actions
        "integrated-handover-documentation"
        "populated-machine-readable-scm-files"
        "created-wiki-index-and-topology"
        "updated-ai-manifest"))))
