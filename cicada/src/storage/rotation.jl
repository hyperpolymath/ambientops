"""
Key rotation utilities
"""

using Dates
using UUIDs

include("../keygen/types.jl")
include("../keygen/classical.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")
include("keystore.jl")
include("backup.jl")

"""
Rotate a key (backup old, generate new with same parameters)
"""
function rotate_key(
    key_id::UUID,
    key_dir::String,
    backup_dir::String;
    comment::String="",
    expires_at::Union{DateTime, Nothing}=nothing
)::Tuple{UUID, UUID}
    try
        log_key_operation("ROTATE", "Starting rotation for key $key_id")

        # Load existing key
        keys = list_keys(key_dir)
        old_key = nothing

        for stored_key in keys
            if stored_key.id == key_id
                old_key = stored_key
                break
            end
        end

        if isnothing(old_key)
            throw(StorageError("Key not found: $key_id"))
        end

        # Backup old key
        backup_path = backup_key(key_id, key_dir, backup_dir)
        @info "Old key backed up to $backup_path"

        # Parse algorithm
        algorithm = parse(KeyAlgorithm, old_key.algorithm)

        # Generate new key with same parameters
        new_keypair = generate_keypair(
            algorithm,
            old_key.email,
            comment=isempty(comment) ? old_key.comment : comment,
            expires_at=expires_at
        )

        # Save new key
        save_keypair(new_keypair, key_dir)

        log_key_operation("ROTATE", "Key rotated: old=$key_id, new=$(new_keypair.metadata.id)")

        return (key_id, new_keypair.metadata.id)
    catch e
        throw(StorageError("Failed to rotate key: $(e)"))
    end
end

"""
Auto-rotate keys that are expiring soon
"""
function auto_rotate_expiring_keys(
    key_dir::String,
    backup_dir::String;
    warning_days::Int=30,
    new_expiry_days::Int=365
)::Vector{Tuple{UUID, UUID}}
    try
        log_key_operation("AUTO_ROTATE", "Checking for expiring keys")

        keys = list_keys(key_dir)
        rotated = Tuple{UUID, UUID}[]

        for stored_key in keys
            # Skip if no expiration
            if isnothing(stored_key.expires_at)
                continue
            end

            expires_at = DateTime(stored_key.expires_at)
            warning_date = now() + Day(warning_days)

            # Check if expiring soon or already expired
            if expires_at < warning_date
                @info "Rotating expiring key: $(stored_key.id) (expires: $expires_at)"

                # New expiration date
                new_expires = now() + Day(new_expiry_days)

                # Rotate
                (old_id, new_id) = rotate_key(
                    stored_key.id,
                    key_dir,
                    backup_dir,
                    comment=stored_key.comment,
                    expires_at=new_expires
                )

                push!(rotated, (old_id, new_id))
            end
        end

        if length(rotated) > 0
            log_key_operation("AUTO_ROTATE", "Rotated $(length(rotated)) expiring keys")
        else
            log_key_operation("AUTO_ROTATE", "No keys need rotation")
        end

        return rotated
    catch e
        throw(StorageError("Failed to auto-rotate keys: $(e)"))
    end
end

"""
Rotate all keys (for security incident response)
"""
function rotate_all_keys(
    key_dir::String,
    backup_dir::String;
    new_expiry_days::Int=365
)::Vector{Tuple{UUID, UUID}}
    try
        log_security("SECURITY INCIDENT: Rotating all keys")

        keys = list_keys(key_dir)
        rotated = Tuple{UUID, UUID}[]

        for stored_key in keys
            @info "Rotating key: $(stored_key.id)"

            new_expires = now() + Day(new_expiry_days)

            (old_id, new_id) = rotate_key(
                stored_key.id,
                key_dir,
                backup_dir,
                comment=stored_key.comment,
                expires_at=new_expires
            )

            push!(rotated, (old_id, new_id))
        end

        log_security("All keys rotated: $(length(rotated)) total")

        return rotated
    catch e
        throw(StorageError("Failed to rotate all keys: $(e)"))
    end
end

"""
Generate rotation report
"""
function rotation_report(key_dir::String, warning_days::Int=30)::Dict{String, Any}
    try
        keys = list_keys(key_dir)

        report = Dict{String, Any}(
            "total_keys" => length(keys),
            "expired" => 0,
            "expiring_soon" => 0,
            "no_expiration" => 0,
            "healthy" => 0,
            "expiring_keys" => []
        )

        for stored_key in keys
            if isnothing(stored_key.expires_at)
                report["no_expiration"] += 1
            else
                expires_at = DateTime(stored_key.expires_at)

                if now() > expires_at
                    report["expired"] += 1
                    push!(report["expiring_keys"], Dict(
                        "id" => string(stored_key.id),
                        "email" => stored_key.email,
                        "expires_at" => string(expires_at),
                        "status" => "EXPIRED"
                    ))
                elseif (now() + Day(warning_days)) > expires_at
                    report["expiring_soon"] += 1
                    push!(report["expiring_keys"], Dict(
                        "id" => string(stored_key.id),
                        "email" => stored_key.email,
                        "expires_at" => string(expires_at),
                        "status" => "EXPIRING_SOON"
                    ))
                else
                    report["healthy"] += 1
                end
            end
        end

        return report
    catch e
        throw(StorageError("Failed to generate rotation report: $(e)"))
    end
end
