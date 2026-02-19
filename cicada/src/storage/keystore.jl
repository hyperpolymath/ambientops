"""
Key storage and retrieval system
"""

using Dates
using JSON3
using UUIDs

include("../keygen/types.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")

"""
Key storage format
"""
struct StoredKey
    id::UUID
    algorithm::String
    purpose::String
    created_at::String
    expires_at::Union{String, Nothing}
    email::String
    comment::String
    fingerprint::String
    quantum_resistant::Bool
    public_key_path::String
    private_key_path::String
end

"""
Save key pair to disk
"""
function save_keypair(keypair::KeyPair, key_dir::String; name::Union{String, Nothing}=nothing)
    try
        # Ensure key directory exists with proper permissions
        mkpath(key_dir)
        chmod(key_dir, 0o700)

        # Generate file name
        if isnothing(name)
            name = "id_$(lowercase(string(keypair.metadata.algorithm)))_$(string(keypair.metadata.id)[1:8])"
        end

        # Paths for keys
        private_path = joinpath(key_dir, name)
        public_path = joinpath(key_dir, "$name.pub")
        metadata_path = joinpath(key_dir, "$name.json")

        # Write private key with restricted permissions
        write(private_path, keypair.private_key)
        chmod(private_path, 0o600)

        # Write public key
        write(public_path, keypair.public_key)
        chmod(public_path, 0o644)

        # Compute fingerprint from public key
        fingerprint = compute_fingerprint(keypair.public_key)

        # Create metadata
        stored_key = StoredKey(
            keypair.metadata.id,
            string(keypair.metadata.algorithm),
            string(keypair.metadata.purpose),
            string(keypair.metadata.created_at),
            isnothing(keypair.metadata.expires_at) ? nothing : string(keypair.metadata.expires_at),
            keypair.metadata.email,
            keypair.metadata.comment,
            fingerprint,
            keypair.metadata.quantum_resistant,
            public_path,
            private_path
        )

        # Write metadata
        write(metadata_path, JSON3.write(stored_key, allow_inf=true))
        chmod(metadata_path, 0o600)

        log_key_operation("SAVE", "Key saved to $private_path")

        return (private_path, public_path, metadata_path)
    catch e
        throw(StorageError("Failed to save key pair: $(e)"))
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

        # Extract fingerprint (format: "bits fingerprint comment (type)")
        parts = split(strip(output), " ")
        if length(parts) >= 2
            return parts[2]
        else
            return "unknown"
        end
    catch e
        @warn "Failed to compute fingerprint: $e"
        return "error"
    end
end

"""
List all stored keys
"""
function list_keys(key_dir::String)::Vector{StoredKey}
    keys = StoredKey[]

    if !isdir(key_dir)
        return keys
    end

    try
        for file in readdir(key_dir)
            if endswith(file, ".json")
                metadata_path = joinpath(key_dir, file)
                data = JSON3.read(read(metadata_path, String))

                stored_key = StoredKey(
                    UUID(data.id),
                    data.algorithm,
                    data.purpose,
                    data.created_at,
                    get(data, :expires_at, nothing),
                    data.email,
                    get(data, :comment, ""),
                    get(data, :fingerprint, ""),
                    get(data, :quantum_resistant, false),
                    data.public_key_path,
                    data.private_key_path
                )

                push!(keys, stored_key)
            end
        end

        # Sort by creation date (newest first)
        sort!(keys, by=k->k.created_at, rev=true)

        return keys
    catch e
        throw(StorageError("Failed to list keys: $(e)"))
    end
end

"""
Load key pair from disk
"""
function load_keypair(key_id::UUID, key_dir::String)::Union{KeyPair, Nothing}
    try
        keys = list_keys(key_dir)

        for stored_key in keys
            if stored_key.id == key_id
                # Read keys from disk
                private_key = read(stored_key.private_key_path) |> collect
                public_key = read(stored_key.public_key_path) |> collect

                # Reconstruct metadata
                algorithm = parse(KeyAlgorithm, stored_key.algorithm)
                purpose = parse(KeyPurpose, stored_key.purpose)
                created_at = DateTime(stored_key.created_at)
                expires_at = isnothing(stored_key.expires_at) ? nothing : DateTime(stored_key.expires_at)

                metadata = KeyMetadata(algorithm, purpose, stored_key.email, stored_key.comment, expires_at)

                return KeyPair(metadata, public_key, private_key, false)
            end
        end

        return nothing
    catch e
        throw(StorageError("Failed to load key: $(e)"))
    end
end

"""
Delete key from storage
"""
function delete_key(key_id::UUID, key_dir::String)::Bool
    try
        keys = list_keys(key_dir)

        for stored_key in keys
            if stored_key.id == key_id
                # Delete files
                rm(stored_key.private_key_path, force=true)
                rm(stored_key.public_key_path, force=true)

                # Delete metadata
                metadata_file = replace(stored_key.private_key_path, r"\.[^.]*$" => ".json")
                rm(metadata_file, force=true)

                log_key_operation("DELETE", "Key deleted: $key_id")

                return true
            end
        end

        return false
    catch e
        throw(StorageError("Failed to delete key: $(e)"))
    end
end

"""
Export public key in SSH format
"""
function export_public_key(key_id::UUID, key_dir::String, output_path::String)
    try
        keys = list_keys(key_dir)

        for stored_key in keys
            if stored_key.id == key_id
                # Copy public key to output path
                cp(stored_key.public_key_path, output_path, force=true)

                log_key_operation("EXPORT", "Public key exported to $output_path")

                return true
            end
        end

        throw(StorageError("Key not found: $key_id"))
    catch e
        throw(StorageError("Failed to export public key: $(e)"))
    end
end
