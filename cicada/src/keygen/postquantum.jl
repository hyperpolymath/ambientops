# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# postquantum.jl — Post-quantum cryptographic key generation (Dilithium, Kyber)
#
# Implementation strategy:
#   1. Attempt to load liboqs via Libdl for real PQC operations
#   2. Fall back to stub implementation if liboqs is not installed
#
# When liboqs is available, is_stub() returns false and real NIST PQC
# algorithms (ML-DSA / Dilithium, ML-KEM / Kyber) are used for key generation,
# signing, and verification.

"""
Post-quantum cryptographic key generation (Dilithium, Kyber)

Uses liboqs (Open Quantum Safe) when available for real PQC operations.
Falls back to stub implementation when liboqs is not installed.
"""

using Dates
using Random
using Libdl

include("types.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")

# ---------------------------------------------------------------------------
# liboqs FFI layer
# ---------------------------------------------------------------------------

"""
Handle to the liboqs shared library, or nothing if unavailable.
Loaded once at module initialisation time.
"""
const _LIBOQS_HANDLE = Ref{Ptr{Nothing}}(C_NULL)

"""
Whether liboqs was successfully loaded and is usable.
"""
const _LIBOQS_AVAILABLE = Ref{Bool}(false)

"""
Attempt to load liboqs from standard system library paths.
Called once at module load time. Safe to call multiple times (idempotent).
"""
function _try_load_liboqs()::Bool
    if _LIBOQS_AVAILABLE[]
        return true
    end

    # Try several common library names / paths
    candidate_names = [
        "liboqs",
        "liboqs.so",
        "liboqs.so.0",
        "liboqs.so.5",
        "/usr/lib/liboqs.so",
        "/usr/lib64/liboqs.so",
        "/usr/local/lib/liboqs.so",
        "/usr/lib/x86_64-linux-gnu/liboqs.so",
    ]

    for name in candidate_names
        handle = Libdl.dlopen(name; throw_error=false)
        if handle !== nothing && handle != C_NULL
            _LIBOQS_HANDLE[] = handle
            _LIBOQS_AVAILABLE[] = true
            log_security("liboqs loaded successfully from: $name")
            return true
        end
    end

    log_security("liboqs not found — falling back to stub PQC implementation")
    return false
end

# Initialise on include
_try_load_liboqs()

# ---------------------------------------------------------------------------
# liboqs OQS_SIG / OQS_KEM wrappers
# ---------------------------------------------------------------------------

"""
Map Dilithium security level to the liboqs algorithm name string.
liboqs uses the NIST names (ML-DSA) as primary, with Dilithium as alias.
"""
function _oqs_sig_algorithm_name(level::Int)::String
    if level == 2
        return "Dilithium2"
    elseif level == 3
        return "Dilithium3"
    elseif level == 5
        return "Dilithium5"
    else
        throw(KeyGenerationError("Invalid Dilithium level: $level (must be 2, 3, or 5)"))
    end
end

"""
Map Kyber security level to the liboqs algorithm name string.
"""
function _oqs_kem_algorithm_name(level::Int)::String
    if level == 512
        return "Kyber512"
    elseif level == 768
        return "Kyber768"
    elseif level == 1024
        return "Kyber1024"
    else
        throw(KeyGenerationError("Invalid Kyber level: $level (must be 512, 768, or 1024)"))
    end
end

"""
Generate a Dilithium key pair using liboqs.
Returns (public_key_bytes, private_key_bytes) or throws on failure.
"""
function _oqs_dilithium_keygen(level::Int)::Tuple{Vector{UInt8}, Vector{UInt8}}
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_sig_algorithm_name(level)

    # OQS_SIG *OQS_SIG_new(const char *method_name)
    sig_new = Libdl.dlsym(lib, :OQS_SIG_new)
    sig_ptr = ccall(sig_new, Ptr{Nothing}, (Cstring,), alg_name)
    if sig_ptr == C_NULL
        throw(KeyGenerationError("liboqs: OQS_SIG_new failed for $alg_name"))
    end

    try
        # Read public/secret key lengths from the OQS_SIG struct.
        # OQS_SIG layout (first fields after method_name pointer and alg_version pointer):
        #   const char *method_name;           offset 0   (Ptr)
        #   const char *alg_version;           offset 8   (Ptr)
        #   uint8_t claimed_nist_level;        offset 16  (UInt8)
        #   bool euf_cma;                      offset 17  (Bool, 1 byte)
        #   [padding to align]                 offset 18..23
        #   size_t length_public_key;          offset 24
        #   size_t length_secret_key;          offset 32
        #   size_t length_signature;           offset 40
        pk_len = unsafe_load(Ptr{Csize_t}(sig_ptr + 24))
        sk_len = unsafe_load(Ptr{Csize_t}(sig_ptr + 32))

        public_key = Vector{UInt8}(undef, pk_len)
        secret_key = Vector{UInt8}(undef, sk_len)

        # OQS_STATUS OQS_SIG_keypair(const OQS_SIG *sig, uint8_t *pk, uint8_t *sk)
        sig_keypair = Libdl.dlsym(lib, :OQS_SIG_keypair)
        status = ccall(sig_keypair, Cint, (Ptr{Nothing}, Ptr{UInt8}, Ptr{UInt8}),
                       sig_ptr, public_key, secret_key)
        if status != 0  # OQS_SUCCESS == 0
            throw(KeyGenerationError("liboqs: OQS_SIG_keypair failed (status=$status)"))
        end

        return (public_key, secret_key)
    finally
        # OQS_SIG_free(OQS_SIG *sig)
        sig_free = Libdl.dlsym(lib, :OQS_SIG_free)
        ccall(sig_free, Cvoid, (Ptr{Nothing},), sig_ptr)
    end
end

"""
Sign a message using a Dilithium secret key via liboqs.
Returns the signature bytes.
"""
function _oqs_dilithium_sign(
    message::Vector{UInt8},
    secret_key::Vector{UInt8},
    level::Int
)::Vector{UInt8}
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_sig_algorithm_name(level)

    sig_new = Libdl.dlsym(lib, :OQS_SIG_new)
    sig_ptr = ccall(sig_new, Ptr{Nothing}, (Cstring,), alg_name)
    if sig_ptr == C_NULL
        throw(KeyGenerationError("liboqs: OQS_SIG_new failed for $alg_name"))
    end

    try
        sig_len_max = unsafe_load(Ptr{Csize_t}(sig_ptr + 40))
        signature = Vector{UInt8}(undef, sig_len_max)
        sig_len_out = Ref{Csize_t}(0)

        # OQS_STATUS OQS_SIG_sign(const OQS_SIG *sig, uint8_t *signature,
        #     size_t *signature_len, const uint8_t *message, size_t message_len,
        #     const uint8_t *secret_key)
        sig_sign = Libdl.dlsym(lib, :OQS_SIG_sign)
        status = ccall(sig_sign, Cint,
                       (Ptr{Nothing}, Ptr{UInt8}, Ref{Csize_t}, Ptr{UInt8}, Csize_t, Ptr{UInt8}),
                       sig_ptr, signature, sig_len_out, message, length(message), secret_key)
        if status != 0
            throw(SecurityError("liboqs: OQS_SIG_sign failed (status=$status)"))
        end

        return signature[1:sig_len_out[]]
    finally
        sig_free = Libdl.dlsym(lib, :OQS_SIG_free)
        ccall(sig_free, Cvoid, (Ptr{Nothing},), sig_ptr)
    end
end

"""
Verify a Dilithium signature via liboqs.
Returns true if the signature is valid.
"""
function _oqs_dilithium_verify(
    message::Vector{UInt8},
    signature::Vector{UInt8},
    public_key::Vector{UInt8},
    level::Int
)::Bool
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_sig_algorithm_name(level)

    sig_new = Libdl.dlsym(lib, :OQS_SIG_new)
    sig_ptr = ccall(sig_new, Ptr{Nothing}, (Cstring,), alg_name)
    if sig_ptr == C_NULL
        return false
    end

    try
        # OQS_STATUS OQS_SIG_verify(const OQS_SIG *sig, const uint8_t *message,
        #     size_t message_len, const uint8_t *signature, size_t signature_len,
        #     const uint8_t *public_key)
        sig_verify = Libdl.dlsym(lib, :OQS_SIG_verify)
        status = ccall(sig_verify, Cint,
                       (Ptr{Nothing}, Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Ptr{UInt8}),
                       sig_ptr, message, length(message), signature, length(signature), public_key)
        return status == 0  # OQS_SUCCESS
    finally
        sig_free = Libdl.dlsym(lib, :OQS_SIG_free)
        ccall(sig_free, Cvoid, (Ptr{Nothing},), sig_ptr)
    end
end

"""
Generate a Kyber key pair using liboqs KEM API.
Returns (public_key_bytes, secret_key_bytes).
"""
function _oqs_kyber_keygen(level::Int)::Tuple{Vector{UInt8}, Vector{UInt8}}
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_kem_algorithm_name(level)

    # OQS_KEM *OQS_KEM_new(const char *method_name)
    kem_new = Libdl.dlsym(lib, :OQS_KEM_new)
    kem_ptr = ccall(kem_new, Ptr{Nothing}, (Cstring,), alg_name)
    if kem_ptr == C_NULL
        throw(KeyGenerationError("liboqs: OQS_KEM_new failed for $alg_name"))
    end

    try
        # OQS_KEM struct layout (same pattern as OQS_SIG):
        #   const char *method_name;           offset 0
        #   const char *alg_version;           offset 8
        #   uint8_t claimed_nist_level;        offset 16
        #   bool ind_cca;                      offset 17
        #   [padding]                          offset 18..23
        #   size_t length_public_key;          offset 24
        #   size_t length_secret_key;          offset 32
        #   size_t length_ciphertext;          offset 40
        #   size_t length_shared_secret;       offset 48
        pk_len = unsafe_load(Ptr{Csize_t}(kem_ptr + 24))
        sk_len = unsafe_load(Ptr{Csize_t}(kem_ptr + 32))

        public_key = Vector{UInt8}(undef, pk_len)
        secret_key = Vector{UInt8}(undef, sk_len)

        # OQS_STATUS OQS_KEM_keypair(const OQS_KEM *kem, uint8_t *pk, uint8_t *sk)
        kem_keypair = Libdl.dlsym(lib, :OQS_KEM_keypair)
        status = ccall(kem_keypair, Cint, (Ptr{Nothing}, Ptr{UInt8}, Ptr{UInt8}),
                       kem_ptr, public_key, secret_key)
        if status != 0
            throw(KeyGenerationError("liboqs: OQS_KEM_keypair failed (status=$status)"))
        end

        return (public_key, secret_key)
    finally
        kem_free = Libdl.dlsym(lib, :OQS_KEM_free)
        ccall(kem_free, Cvoid, (Ptr{Nothing},), kem_ptr)
    end
end

"""
Perform Kyber encapsulation via liboqs KEM API.
Returns (ciphertext, shared_secret).
"""
function _oqs_kyber_encaps(
    public_key::Vector{UInt8},
    level::Int
)::Tuple{Vector{UInt8}, Vector{UInt8}}
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_kem_algorithm_name(level)

    kem_new = Libdl.dlsym(lib, :OQS_KEM_new)
    kem_ptr = ccall(kem_new, Ptr{Nothing}, (Cstring,), alg_name)
    if kem_ptr == C_NULL
        throw(KeyGenerationError("liboqs: OQS_KEM_new failed for $alg_name"))
    end

    try
        ct_len = unsafe_load(Ptr{Csize_t}(kem_ptr + 40))
        ss_len = unsafe_load(Ptr{Csize_t}(kem_ptr + 48))

        ciphertext = Vector{UInt8}(undef, ct_len)
        shared_secret = Vector{UInt8}(undef, ss_len)

        # OQS_STATUS OQS_KEM_encaps(const OQS_KEM *kem, uint8_t *ciphertext,
        #     uint8_t *shared_secret, const uint8_t *public_key)
        kem_encaps = Libdl.dlsym(lib, :OQS_KEM_encaps)
        status = ccall(kem_encaps, Cint,
                       (Ptr{Nothing}, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}),
                       kem_ptr, ciphertext, shared_secret, public_key)
        if status != 0
            throw(SecurityError("liboqs: OQS_KEM_encaps failed (status=$status)"))
        end

        return (ciphertext, shared_secret)
    finally
        kem_free = Libdl.dlsym(lib, :OQS_KEM_free)
        ccall(kem_free, Cvoid, (Ptr{Nothing},), kem_ptr)
    end
end

"""
Perform Kyber decapsulation via liboqs KEM API.
Returns the shared_secret.
"""
function _oqs_kyber_decaps(
    ciphertext::Vector{UInt8},
    secret_key::Vector{UInt8},
    level::Int
)::Vector{UInt8}
    lib = _LIBOQS_HANDLE[]
    alg_name = _oqs_kem_algorithm_name(level)

    kem_new = Libdl.dlsym(lib, :OQS_KEM_new)
    kem_ptr = ccall(kem_new, Ptr{Nothing}, (Cstring,), alg_name)
    if kem_ptr == C_NULL
        throw(KeyGenerationError("liboqs: OQS_KEM_new failed for $alg_name"))
    end

    try
        ss_len = unsafe_load(Ptr{Csize_t}(kem_ptr + 48))
        shared_secret = Vector{UInt8}(undef, ss_len)

        # OQS_STATUS OQS_KEM_decaps(const OQS_KEM *kem, uint8_t *shared_secret,
        #     const uint8_t *ciphertext, const uint8_t *secret_key)
        kem_decaps = Libdl.dlsym(lib, :OQS_KEM_decaps)
        status = ccall(kem_decaps, Cint,
                       (Ptr{Nothing}, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}),
                       kem_ptr, shared_secret, ciphertext, secret_key)
        if status != 0
            throw(SecurityError("liboqs: OQS_KEM_decaps failed (status=$status)"))
        end

        return shared_secret
    finally
        kem_free = Libdl.dlsym(lib, :OQS_KEM_free)
        ccall(kem_free, Cvoid, (Ptr{Nothing},), kem_ptr)
    end
end

# ---------------------------------------------------------------------------
# Stub implementations (fallback when liboqs is not available)
# ---------------------------------------------------------------------------

"""
Stub key generation for Dilithium — generates placeholder keys.
Retained as fallback when liboqs is not installed.
"""
function _stub_dilithium_keygen(
    email::String,
    level::Int,
    metadata::KeyMetadata
)::Tuple{Vector{UInt8}, Vector{UInt8}}
    log_security("WARNING: Using stub PQC implementation — keys are NOT cryptographically secure")

    public_key = Vector{UInt8}(
        "ssh-dilithium$level STUB_PQC_PUBLIC_KEY_$(string(metadata.id)[1:8]) $email"
    )

    private_key = Vector{UInt8}(
        """-----BEGIN DILITHIUM$level PRIVATE KEY-----
STUB_PQC_IMPLEMENTATION
This is a placeholder for post-quantum Dilithium key.
Install liboqs for real PQC support.
Key ID: $(metadata.id)
-----END DILITHIUM$level PRIVATE KEY-----
"""
    )

    return (public_key, private_key)
end

"""
Stub key generation for Kyber — generates placeholder keys.
Retained as fallback when liboqs is not installed.
"""
function _stub_kyber_keygen(
    email::String,
    level::Int,
    metadata::KeyMetadata
)::Tuple{Vector{UInt8}, Vector{UInt8}}
    log_security("WARNING: Using stub PQC implementation — keys are NOT cryptographically secure")

    public_key = Vector{UInt8}(
        "kyber$level STUB_PQC_PUBLIC_KEY_$(string(metadata.id)[1:8]) $email"
    )

    private_key = Vector{UInt8}(
        """-----BEGIN KYBER$level PRIVATE KEY-----
STUB_PQC_IMPLEMENTATION
This is a placeholder for post-quantum Kyber key.
Install liboqs for real PQC support.
Key ID: $(metadata.id)
-----END KYBER$level PRIVATE KEY-----
"""
    )

    return (public_key, private_key)
end

"""
Stub signature — returns an empty vector (always invalid).
"""
function _stub_sign(message::Vector{UInt8}, secret_key::Vector{UInt8})::Vector{UInt8}
    log_security("WARNING: Stub sign — signature is NOT valid")
    return UInt8[]
end

"""
Stub verification — always returns false.
"""
function _stub_verify(
    message::Vector{UInt8},
    signature::Vector{UInt8},
    public_key::Vector{UInt8}
)::Bool
    log_security("WARNING: Stub verify — always returns false")
    return false
end

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
Check if the PQC implementation is a stub (no real crypto).
Returns false when liboqs is loaded and real algorithms are active.
"""
function is_stub()::Bool
    return !_LIBOQS_AVAILABLE[]
end

"""
Check if PQC libraries are available (alias for backward compatibility).
"""
function pqc_available()::Bool
    return _LIBOQS_AVAILABLE[]
end

"""
Generate Dilithium key pair.

When liboqs is available, generates real Dilithium keys via OQS_SIG.
Otherwise falls back to stub placeholder keys.

# Arguments
- `email::String`: Email address for key metadata.
- `level::Int`: Security level — 2, 3, or 5 (default 3).
- `comment::String`: Optional comment for key metadata.
- `expires_at::Union{DateTime, Nothing}`: Optional expiry date.

# Returns
A `KeyPair` with real or stub keys depending on liboqs availability.
"""
function generate_dilithium(
    email::String,
    level::Int=3;
    comment::String="",
    expires_at::Union{DateTime, Nothing}=nothing
)::KeyPair
    try
        log_key_operation("GENERATE_PQC", "Creating Dilithium$level key pair for $email")

        algorithm = if level == 2
            DILITHIUM2
        elseif level == 3
            DILITHIUM3
        elseif level == 5
            DILITHIUM5
        else
            throw(KeyGenerationError("Invalid Dilithium level: $level (must be 2, 3, or 5)"))
        end

        metadata = KeyMetadata(algorithm, SSH_AUTH, email, comment, expires_at)

        # Dispatch to real or stub implementation
        public_key, private_key = if _LIBOQS_AVAILABLE[]
            log_key_operation("GENERATE_PQC", "Using liboqs for real Dilithium$level keygen")
            _oqs_dilithium_keygen(level)
        else
            log_key_operation("GENERATE_PQC", "Using stub Dilithium$level keygen (liboqs not available)")
            _stub_dilithium_keygen(email, level, metadata)
        end

        keypair = KeyPair(metadata, public_key, private_key, false)

        log_key_operation("GENERATE_PQC", "Dilithium$level key generated: $(metadata.id)")
        if is_stub()
            @warn "Generated stub PQC key — not suitable for production use. Install liboqs for real PQC."
        end

        return keypair
    catch e
        if e isa KeyGenerationError
            rethrow(e)
        end
        throw(KeyGenerationError("Failed to generate Dilithium key: $(e)"))
    end
end

"""
Generate Kyber key pair (Key Encapsulation Mechanism).

When liboqs is available, generates real Kyber keys via OQS_KEM.
Otherwise falls back to stub placeholder keys.

# Arguments
- `email::String`: Email address for key metadata.
- `level::Int`: Security level — 512, 768, or 1024 (default 768).
- `comment::String`: Optional comment for key metadata.
- `expires_at::Union{DateTime, Nothing}`: Optional expiry date.

# Returns
A `KeyPair` with real or stub keys depending on liboqs availability.
"""
function generate_kyber(
    email::String,
    level::Int=768;
    comment::String="",
    expires_at::Union{DateTime, Nothing}=nothing
)::KeyPair
    try
        log_key_operation("GENERATE_PQC", "Creating Kyber$level key pair for $email")

        algorithm = if level == 512
            KYBER512
        elseif level == 768
            KYBER768
        elseif level == 1024
            KYBER1024
        else
            throw(KeyGenerationError("Invalid Kyber level: $level (must be 512, 768, or 1024)"))
        end

        metadata = KeyMetadata(algorithm, ENCRYPTION, email, comment, expires_at)

        # Dispatch to real or stub implementation
        public_key, private_key = if _LIBOQS_AVAILABLE[]
            log_key_operation("GENERATE_PQC", "Using liboqs for real Kyber$level keygen")
            _oqs_kyber_keygen(level)
        else
            log_key_operation("GENERATE_PQC", "Using stub Kyber$level keygen (liboqs not available)")
            _stub_kyber_keygen(email, level, metadata)
        end

        keypair = KeyPair(metadata, public_key, private_key, false)

        log_key_operation("GENERATE_PQC", "Kyber$level key generated: $(metadata.id)")
        if is_stub()
            @warn "Generated stub PQC key — not suitable for production use. Install liboqs for real PQC."
        end

        return keypair
    catch e
        if e isa KeyGenerationError
            rethrow(e)
        end
        throw(KeyGenerationError("Failed to generate Kyber key: $(e)"))
    end
end

"""
Sign a message using a Dilithium private key.

When liboqs is available, produces a real Dilithium signature.
Otherwise returns an empty (invalid) stub signature.

# Arguments
- `message::Vector{UInt8}`: The message bytes to sign.
- `secret_key::Vector{UInt8}`: The Dilithium secret key bytes.
- `level::Int`: Dilithium security level (2, 3, or 5).

# Returns
Signature bytes (real or empty stub).
"""
function sign_dilithium(
    message::Vector{UInt8},
    secret_key::Vector{UInt8},
    level::Int=3
)::Vector{UInt8}
    if _LIBOQS_AVAILABLE[]
        return _oqs_dilithium_sign(message, secret_key, level)
    else
        return _stub_sign(message, secret_key)
    end
end

"""
Verify a Dilithium signature.

When liboqs is available, performs real signature verification.
Otherwise always returns false (stub).

# Arguments
- `message::Vector{UInt8}`: The original message bytes.
- `signature::Vector{UInt8}`: The signature to verify.
- `public_key::Vector{UInt8}`: The Dilithium public key bytes.
- `level::Int`: Dilithium security level (2, 3, or 5).

# Returns
`true` if the signature is valid, `false` otherwise.
"""
function verify_dilithium(
    message::Vector{UInt8},
    signature::Vector{UInt8},
    public_key::Vector{UInt8},
    level::Int=3
)::Bool
    if _LIBOQS_AVAILABLE[]
        return _oqs_dilithium_verify(message, signature, public_key, level)
    else
        return _stub_verify(message, signature, public_key)
    end
end

"""
Perform Kyber key encapsulation.

When liboqs is available, performs real KEM encapsulation.
Otherwise throws a SecurityError (stub does not support encapsulation).

# Arguments
- `public_key::Vector{UInt8}`: The Kyber public key bytes.
- `level::Int`: Kyber security level (512, 768, or 1024).

# Returns
Tuple of (ciphertext, shared_secret).
"""
function encapsulate_kyber(
    public_key::Vector{UInt8},
    level::Int=768
)::Tuple{Vector{UInt8}, Vector{UInt8}}
    if _LIBOQS_AVAILABLE[]
        return _oqs_kyber_encaps(public_key, level)
    else
        throw(SecurityError("Kyber encapsulation requires liboqs — stub implementation cannot perform KEM operations"))
    end
end

"""
Perform Kyber key decapsulation.

When liboqs is available, performs real KEM decapsulation.
Otherwise throws a SecurityError (stub does not support decapsulation).

# Arguments
- `ciphertext::Vector{UInt8}`: The ciphertext from encapsulation.
- `secret_key::Vector{UInt8}`: The Kyber secret key bytes.
- `level::Int`: Kyber security level (512, 768, or 1024).

# Returns
The shared secret bytes.
"""
function decapsulate_kyber(
    ciphertext::Vector{UInt8},
    secret_key::Vector{UInt8},
    level::Int=768
)::Vector{UInt8}
    if _LIBOQS_AVAILABLE[]
        return _oqs_kyber_decaps(ciphertext, secret_key, level)
    else
        throw(SecurityError("Kyber decapsulation requires liboqs — stub implementation cannot perform KEM operations"))
    end
end

"""
Generate hybrid quantum-resistant key (classical + PQC)

Combines Ed25519 for current security with Dilithium for quantum resistance.
This provides security even if one algorithm is broken.
"""
function generate_hybrid_qr(
    email::String;
    comment::String="",
    expires_at::Union{DateTime, Nothing}=nothing
)::Tuple{KeyPair, KeyPair}
    try
        log_key_operation("GENERATE_HYBRID", "Creating hybrid QR key pair for $email")

        # Generate classical Ed25519 key
        include("classical.jl")
        classical_key = generate_ed25519(email, comment="$comment (classical)", expires_at=expires_at)

        # Generate PQC Dilithium3 key
        pqc_key = generate_dilithium(email, 3, comment="$comment (PQC)", expires_at=expires_at)

        log_key_operation("GENERATE_HYBRID", "Hybrid QR keys generated")

        return (classical_key, pqc_key)
    catch e
        throw(KeyGenerationError("Failed to generate hybrid QR keys: $(e)"))
    end
end

"""
Get PQC implementation information.
Reports whether real liboqs is active or stub is in use.
"""
function pqc_info()::Dict{String, Any}
    implementation = if _LIBOQS_AVAILABLE[]
        "liboqs"
    else
        "stub"
    end

    return Dict{String, Any}(
        "available" => pqc_available(),
        "is_stub" => is_stub(),
        "implementation" => implementation,
        "supported_algorithms" => [
            "Dilithium2", "Dilithium3", "Dilithium5",
            "Kyber512", "Kyber768", "Kyber1024"
        ],
        "install_instructions" => if is_stub()
            "Install liboqs (https://github.com/open-quantum-safe/liboqs) for real PQC support"
        else
            "liboqs is active — real PQC algorithms in use"
        end,
        "note" => if is_stub()
            "Current implementation is a stub — install liboqs for production use"
        else
            "Real PQC implementation via liboqs is active"
        end,
    )
end
