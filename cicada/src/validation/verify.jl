"""
Key validation and verification utilities
"""

using Dates

include("../keygen/types.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")

"""
Validate SSH public key format
"""
function validate_public_key(public_key::Vector{UInt8})::Bool
    try
        # Write to temp file and validate with ssh-keygen
        temp_file = tempname()
        write(temp_file, public_key)

        # Try to read the key - ssh-keygen will fail if invalid
        result = success(`ssh-keygen -lf $temp_file`)

        # Clean up
        rm(temp_file, force=true)

        return result
    catch e
        @warn "Public key validation failed: $e"
        return false
    end
end

"""
Validate SSH private key format
"""
function validate_private_key(private_key::Vector{UInt8})::Bool
    try
        # Write to temp file
        temp_file = tempname()
        write(temp_file, private_key)
        chmod(temp_file, 0o600)

        # Try to extract public key - will fail if private key is invalid
        result = success(pipeline(`ssh-keygen -y -f $temp_file`, devnull))

        # Clean up
        rm(temp_file, force=true)

        return result
    catch e
        @warn "Private key validation failed: $e"
        return false
    end
end

"""
Verify key pair matches (public key derived from private key)
"""
function verify_keypair(keypair::KeyPair)::Bool
    try
        # Extract public key from private key
        temp_file = tempname()
        write(temp_file, keypair.private_key)
        chmod(temp_file, 0o600)

        derived_public = read(`ssh-keygen -y -f $temp_file`, String)

        # Clean up
        rm(temp_file, force=true)

        # Compare with stored public key
        stored_public = String(copy(keypair.public_key))

        # SSH public keys might have different comments, compare just the key part
        derived_parts = split(strip(derived_public), " ")
        stored_parts = split(strip(stored_public), " ")

        if length(derived_parts) >= 2 && length(stored_parts) >= 2
            return derived_parts[1] == stored_parts[1] && derived_parts[2] == stored_parts[2]
        end

        return false
    catch e
        @warn "Key pair verification failed: $e"
        return false
    end
end

"""
Check if key has expired
"""
function is_expired(metadata::KeyMetadata)::Bool
    if isnothing(metadata.expires_at)
        return false
    end

    return now() > metadata.expires_at
end

"""
Check if key is about to expire (within warning period)
"""
function expires_soon(metadata::KeyMetadata; warning_days::Int=30)::Bool
    if isnothing(metadata.expires_at)
        return false
    end

    warning_date = now() + Day(warning_days)
    return warning_date > metadata.expires_at && !is_expired(metadata)
end

"""
Validate key strength based on algorithm
"""
function validate_key_strength(algorithm::KeyAlgorithm)::Tuple{Bool, String}
    # Consider weak algorithms
    weak_algorithms = [RSA2048]  # RSA-2048 is becoming weak

    if algorithm in weak_algorithms
        return (false, "Algorithm $(algorithm_name(algorithm)) is considered weak. Consider using RSA-4096 or Ed25519.")
    end

    # Recommend quantum-resistant algorithms
    if !is_post_quantum(algorithm)
        return (true, "Classical algorithm. Consider quantum-resistant alternatives for long-term security.")
    end

    return (true, "Strong algorithm")
end

"""
Comprehensive key validation
"""
function validate_keypair(keypair::KeyPair)::Tuple{Bool, Vector{String}}
    issues = String[]

    # Validate public key format
    if !validate_public_key(keypair.public_key)
        push!(issues, "Invalid public key format")
    end

    # Validate private key format
    if !validate_private_key(keypair.private_key)
        push!(issues, "Invalid private key format")
    end

    # Verify key pair matches
    if !verify_keypair(keypair)
        push!(issues, "Public and private keys do not match")
    end

    # Check expiration
    if is_expired(keypair.metadata)
        push!(issues, "Key has expired on $(keypair.metadata.expires_at)")
    elseif expires_soon(keypair.metadata)
        push!(issues, "Key expires soon on $(keypair.metadata.expires_at)")
    end

    # Check key strength
    (strong, message) = validate_key_strength(keypair.metadata.algorithm)
    if !strong
        push!(issues, message)
    end

    is_valid = length(issues) == 0
    return (is_valid, issues)
end

"""
Security audit of a key
"""
function audit_key(keypair::KeyPair)::Dict{String, Any}
    audit = Dict{String, Any}()

    audit["id"] = string(keypair.metadata.id)
    audit["algorithm"] = algorithm_name(keypair.metadata.algorithm)
    audit["key_size"] = key_size(keypair.metadata.algorithm)
    audit["quantum_resistant"] = is_post_quantum(keypair.metadata.algorithm)
    audit["created_at"] = keypair.metadata.created_at
    audit["age_days"] = (now() - keypair.metadata.created_at).value ÷ (1000 * 60 * 60 * 24)

    # Expiration status
    if isnothing(keypair.metadata.expires_at)
        audit["expiration"] = "Never"
        audit["expired"] = false
    else
        audit["expiration"] = keypair.metadata.expires_at
        audit["expired"] = is_expired(keypair.metadata)
        audit["expires_soon"] = expires_soon(keypair.metadata)
    end

    # Validation
    (is_valid, issues) = validate_keypair(keypair)
    audit["valid"] = is_valid
    audit["issues"] = issues

    # Strength assessment
    (strong, message) = validate_key_strength(keypair.metadata.algorithm)
    audit["strong"] = strong
    audit["strength_message"] = message

    return audit
end
