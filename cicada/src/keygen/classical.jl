"""
Classical cryptographic key generation (Ed25519, RSA, ECDSA)
"""

using Nettle
using Dates

include("types.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")

"""
Generate Ed25519 SSH key pair
"""
function generate_ed25519(email::String; comment::String="", expires_at::Union{DateTime, Nothing}=nothing)::KeyPair
    try
        log_key_operation("GENERATE", "Creating Ed25519 key pair for $email")

        metadata = KeyMetadata(ED25519, SSH_AUTH, email, comment, expires_at)

        # Generate Ed25519 key using ssh-keygen
        temp_dir = mktempdir()
        key_path = joinpath(temp_dir, "id_ed25519")

        # Generate key without passphrase (will be encrypted during storage if needed)
        run(pipeline(`ssh-keygen -t ed25519 -C "$email" -N "" -f $key_path`, devnull))

        # Read generated keys
        private_key = read(key_path, String) |> codeunits |> collect
        public_key = read("$key_path.pub", String) |> codeunits |> collect

        # Clean up
        rm(temp_dir, recursive=true, force=true)

        keypair = KeyPair(metadata, public_key, private_key, false)

        log_key_operation("SUCCESS", "Ed25519 key generated: $(metadata.id)")

        return keypair
    catch e
        throw(KeyGenerationError("Failed to generate Ed25519 key: $(e)"))
    end
end

"""
Generate RSA SSH key pair
"""
function generate_rsa(email::String, bits::Int=4096; comment::String="", expires_at::Union{DateTime, Nothing}=nothing)::KeyPair
    try
        log_key_operation("GENERATE", "Creating RSA-$bits key pair for $email")

        algorithm = bits == 2048 ? RSA2048 : RSA4096
        metadata = KeyMetadata(algorithm, SSH_AUTH, email, comment, expires_at)

        # Generate RSA key using ssh-keygen
        temp_dir = mktempdir()
        key_path = joinpath(temp_dir, "id_rsa")

        # Generate key without passphrase
        run(pipeline(`ssh-keygen -t rsa -b $bits -C "$email" -N "" -f $key_path`, devnull))

        # Read generated keys
        private_key = read(key_path, String) |> codeunits |> collect
        public_key = read("$key_path.pub", String) |> codeunits |> collect

        # Clean up
        rm(temp_dir, recursive=true, force=true)

        keypair = KeyPair(metadata, public_key, private_key, false)

        log_key_operation("SUCCESS", "RSA-$bits key generated: $(metadata.id)")

        return keypair
    catch e
        throw(KeyGenerationError("Failed to generate RSA key: $(e)"))
    end
end

"""
Generate ECDSA SSH key pair
"""
function generate_ecdsa(email::String; bits::Int=256, comment::String="", expires_at::Union{DateTime, Nothing}=nothing)::KeyPair
    try
        log_key_operation("GENERATE", "Creating ECDSA-P$bits key pair for $email")

        algorithm = bits == 256 ? ECDSA_P256 : ECDSA_P384
        metadata = KeyMetadata(algorithm, SSH_AUTH, email, comment, expires_at)

        # Generate ECDSA key using ssh-keygen
        temp_dir = mktempdir()
        key_path = joinpath(temp_dir, "id_ecdsa")

        # Generate key without passphrase
        run(pipeline(`ssh-keygen -t ecdsa -b $bits -C "$email" -N "" -f $key_path`, devnull))

        # Read generated keys
        private_key = read(key_path, String) |> codeunits |> collect
        public_key = read("$key_path.pub", String) |> codeunits |> collect

        # Clean up
        rm(temp_dir, recursive=true, force=true)

        keypair = KeyPair(metadata, public_key, private_key, false)

        log_key_operation("SUCCESS", "ECDSA-P$bits key generated: $(metadata.id)")

        return keypair
    catch e
        throw(KeyGenerationError("Failed to generate ECDSA key: $(e)"))
    end
end

"""
Compute SSH key fingerprint
"""
function compute_fingerprint(public_key::Vector{UInt8})::String
    try
        # Write public key to temp file
        temp_file = tempname()
        write(temp_file, public_key)

        # Get fingerprint using ssh-keygen
        output = read(`ssh-keygen -lf $temp_file`, String)

        # Clean up
        rm(temp_file, force=true)

        # Extract fingerprint from output (format: "bits fingerprint comment (type)")
        parts = split(strip(output), " ")
        if length(parts) >= 2
            return parts[2]
        else
            return ""
        end
    catch e
        @warn "Failed to compute fingerprint: $e"
        return ""
    end
end

"""
Generate key pair based on algorithm
"""
function generate_keypair(
    algorithm::KeyAlgorithm,
    email::String;
    comment::String="",
    expires_at::Union{DateTime, Nothing}=nothing
)::KeyPair
    if algorithm == ED25519
        return generate_ed25519(email, comment=comment, expires_at=expires_at)
    elseif algorithm == RSA2048
        return generate_rsa(email, 2048, comment=comment, expires_at=expires_at)
    elseif algorithm == RSA4096
        return generate_rsa(email, 4096, comment=comment, expires_at=expires_at)
    elseif algorithm == ECDSA_P256
        return generate_ecdsa(email, bits=256, comment=comment, expires_at=expires_at)
    elseif algorithm == ECDSA_P384
        return generate_ecdsa(email, bits=384, comment=comment, expires_at=expires_at)
    else
        throw(KeyGenerationError("Unsupported algorithm for classical key generation: $algorithm"))
    end
end
