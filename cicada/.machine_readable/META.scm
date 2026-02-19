;; SPDX-License-Identifier: PMPL-1.0-or-later
;; META.scm - Meta-level information for CIcaDA (Crypto Identity)
;; Media-Type: application/meta+scheme

(meta
  (architecture-decisions
    (adr-001
      (title "Julia as primary language")
      (status "accepted")
      (date "2024-12-28")
      (context "Need a language with strong numerical computing, easy C interop for cryptographic libraries, and rapid prototyping capability")
      (decision "Use Julia 1.9+ as primary implementation language")
      (rationale "Julia provides: multiple dispatch for clean API design, native C FFI for OpenSSH/Nettle bindings, strong type system, cross-platform support, and growing cryptography ecosystem")
      (consequences "Requires Julia runtime; startup latency for CLI; smaller ecosystem than Python/Rust for crypto tooling"))

    (adr-002
      (title "Ed25519 as default classical algorithm")
      (status "accepted")
      (date "2024-12-28")
      (context "Need a default SSH key algorithm that balances security, performance, and compatibility")
      (decision "Default to Ed25519 for classical key generation")
      (rationale "Ed25519 is modern, fast, secure, and widely supported by SSH implementations. Smaller keys than RSA with equivalent security. Recommended by OpenSSH.")
      (consequences "May need RSA fallback for legacy systems"))

    (adr-003
      (title "Dilithium and Kyber for post-quantum cryptography")
      (status "accepted")
      (date "2024-12-28")
      (context "Need quantum-resistant algorithms following NIST PQC standardization")
      (decision "Support Dilithium (signatures) and Kyber (key encapsulation) with stub implementation, production via NistyPQC.jl")
      (rationale "Dilithium and Kyber are NIST-selected PQC standards (FIPS 204/203). Hybrid mode (Ed25519+Dilithium3) provides defense in depth during transition period.")
      (consequences "Stub implementation until NistyPQC.jl matures; hybrid mode doubles key material"))

    (adr-004
      (title "TOML for configuration files")
      (status "accepted")
      (date "2024-12-28")
      (context "Need a configuration format that is human-readable and well-supported in Julia")
      (decision "Use TOML for configuration at ~/.cicada/config.toml")
      (rationale "TOML is readable, Julia has native TOML support, and it handles nested config well")
      (consequences "Users familiar with INI/YAML may need minor adjustment"))

    (adr-005
      (title "UUID-based key identification")
      (status "accepted")
      (date "2024-12-28")
      (context "Need unique, collision-free identifiers for keys across systems")
      (decision "Use UUIDs (v4) as primary key identifiers")
      (rationale "UUIDs provide global uniqueness without central coordination, important for distributed key management")
      (consequences "Longer IDs than sequential integers; users may need to copy-paste"))

    (adr-006
      (title "Argon2id for planned key derivation")
      (status "proposed")
      (date "2026-02-19")
      (context "Phase 2 backup encryption needs a key derivation function resistant to GPU/ASIC attacks")
      (decision "Use Argon2id for deriving encryption keys from user passphrases")
      (rationale "Argon2id is the OWASP-recommended KDF, resistant to both side-channel and GPU attacks. Winner of the Password Hashing Competition.")
      (consequences "Requires Argon2 Julia binding; adds memory requirement during derivation"))

    (adr-007
      (title "AES-256-GCM for planned backup encryption")
      (status "proposed")
      (date "2026-02-19")
      (context "Phase 2 needs authenticated encryption for backup files at rest")
      (decision "Use AES-256-GCM for encrypting private key backups")
      (rationale "AES-256-GCM provides both confidentiality and integrity, is hardware-accelerated on modern CPUs, and widely audited")
      (consequences "Requires authenticated encryption library; key material from Argon2id"))

    (adr-008
      (title "Component of ambientops monorepo")
      (status "accepted")
      (date "2026-01-03")
      (context "CIcaDA was originally standalone; needs organizational home in hyperpolymath ecosystem")
      (decision "House CIcaDA as a component within the ambientops hybrid monorepo")
      (rationale "Ambientops follows a hospital-model operations framework; CIcaDA provides identity security, analogous to patient identity verification in a hospital")
      (consequences "Subject to ambientops workspace policies; CI/CD integration with ambientops pipeline")))

  (development-practices
    (code-style
      (language "Julia")
      (conventions "Julia style guide")
      (dispatch "Multiple dispatch for clean API")
      (type-stability "Required for performance")
      (docstrings "Required on all public functions"))
    (security
      (principle "Defense in depth")
      (cryptographic-libraries "Established libraries only (Nettle, OpenSSH_jll)")
      (input-validation "All inputs validated")
      (key-storage "0600 permissions for private keys, 0700 for directories")
      (audit-trail "All operations logged")
      (quantum-resistance "Considered in all cryptographic choices"))
    (testing
      (framework "Julia Test stdlib")
      (isolation "Temporary directories for all tests")
      (coverage-target "90%")
      (test-files "test/runtests.jl" "test/test_types.jl" "test/test_config.jl"
                  "test/test_keygen.jl" "test/test_storage.jl" "test/test_validation.jl"))
    (versioning "SemVer")
    (documentation "AsciiDoc primary, Markdown for user-facing guides")
    (branching "main for stable"))

  (design-rationale
    (quantum-resistance "Post-quantum cryptography is not optional; it is a design requirement. Even stub implementations establish the architecture for seamless PQC integration.")
    (hybrid-approach "Hybrid keys (classical + PQC) ensure security during the quantum transition period. If either algorithm is broken, the other provides fallback.")
    (ethical-technology "CIcaDA exists to serve ethical technology development. Secure identity management is foundational to trust in open-source collaboration.")))
