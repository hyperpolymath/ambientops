"""
Key types and structures for PalimpsestCryptoIdentity
"""

using Dates
using UUIDs

"""
Supported key algorithms
"""
@enum KeyAlgorithm begin
    ED25519
    RSA2048
    RSA4096
    ECDSA_P256
    ECDSA_P384
    # Post-quantum algorithms
    DILITHIUM2
    DILITHIUM3
    DILITHIUM5
    KYBER512
    KYBER768
    KYBER1024
end

"""
Key purpose/usage
"""
@enum KeyPurpose begin
    SSH_AUTH
    CODE_SIGNING
    ENCRYPTION
    HYBRID_QR  # Hybrid quantum-resistant
end

"""
Key metadata structure
"""
struct KeyMetadata
    id::UUID
    algorithm::KeyAlgorithm
    purpose::KeyPurpose
    created_at::DateTime
    expires_at::Union{DateTime, Nothing}
    email::String
    comment::String
    fingerprint::String
    quantum_resistant::Bool

    function KeyMetadata(
        algorithm::KeyAlgorithm,
        purpose::KeyPurpose,
        email::String,
        comment::String="",
        expires_at::Union{DateTime, Nothing}=nothing
    )
        qr = algorithm in [DILITHIUM2, DILITHIUM3, DILITHIUM5, KYBER512, KYBER768, KYBER1024]
        new(
            uuid4(),
            algorithm,
            purpose,
            now(),
            expires_at,
            email,
            comment,
            "",  # Will be computed after key generation
            qr
        )
    end
end

"""
Cryptographic key pair
"""
struct KeyPair
    metadata::KeyMetadata
    public_key::Vector{UInt8}
    private_key::Vector{UInt8}
    passphrase_protected::Bool

    function KeyPair(metadata::KeyMetadata, public_key::Vector{UInt8}, private_key::Vector{UInt8}, passphrase::Bool=false)
        new(metadata, public_key, private_key, passphrase)
    end
end

"""
Get algorithm display name
"""
function algorithm_name(algo::KeyAlgorithm)::String
    if algo == ED25519
        return "Ed25519"
    elseif algo == RSA2048
        return "RSA-2048"
    elseif algo == RSA4096
        return "RSA-4096"
    elseif algo == ECDSA_P256
        return "ECDSA-P256"
    elseif algo == ECDSA_P384
        return "ECDSA-P384"
    elseif algo == DILITHIUM2
        return "Dilithium2 (NIST Level 2)"
    elseif algo == DILITHIUM3
        return "Dilithium3 (NIST Level 3)"
    elseif algo == DILITHIUM5
        return "Dilithium5 (NIST Level 5)"
    elseif algo == KYBER512
        return "Kyber512 (NIST Level 1)"
    elseif algo == KYBER768
        return "Kyber768 (NIST Level 3)"
    elseif algo == KYBER1024
        return "Kyber1024 (NIST Level 5)"
    else
        return "Unknown"
    end
end

"""
Get key size in bits
"""
function key_size(algo::KeyAlgorithm)::Int
    if algo == ED25519
        return 256
    elseif algo == RSA2048
        return 2048
    elseif algo == RSA4096
        return 4096
    elseif algo == ECDSA_P256
        return 256
    elseif algo == ECDSA_P384
        return 384
    elseif algo == DILITHIUM2
        return 2528  # Approximate security level
    elseif algo == DILITHIUM3
        return 4000
    elseif algo == DILITHIUM5
        return 4880
    elseif algo == KYBER512
        return 128  # Post-quantum security level
    elseif algo == KYBER768
        return 192
    elseif algo == KYBER1024
        return 256
    else
        return 0
    end
end

"""
Check if algorithm is post-quantum
"""
function is_post_quantum(algo::KeyAlgorithm)::Bool
    return algo in [DILITHIUM2, DILITHIUM3, DILITHIUM5, KYBER512, KYBER768, KYBER1024]
end
