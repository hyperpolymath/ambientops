"""
Key backup and recovery utilities
"""

using Dates
using JSON3
using UUIDs
using Nettle

include("../keygen/types.jl")
include("../utils/errors.jl")
include("../utils/logging.jl")
include("keystore.jl")

"""
Backup a single key
"""
function backup_key(key_id::UUID, key_dir::String, backup_dir::String; encrypt::Bool=true)
    try
        mkpath(backup_dir)
        chmod(backup_dir, 0o700)

        keys = list_keys(key_dir)
        found = false

        for stored_key in keys
            if stored_key.id == key_id
                found = true

                # Create backup filename with timestamp
                timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
                backup_name = "backup_$(stored_key.id)_$timestamp"
                backup_path = joinpath(backup_dir, backup_name)

                # Create backup directory
                mkpath(backup_path)
                chmod(backup_path, 0o700)

                # Copy all key files
                cp(stored_key.private_key_path, joinpath(backup_path, basename(stored_key.private_key_path)))
                cp(stored_key.public_key_path, joinpath(backup_path, basename(stored_key.public_key_path)))

                # Copy metadata
                metadata_file = replace(stored_key.private_key_path, r"\.[^.]*$" => ".json")
                if isfile(metadata_file)
                    cp(metadata_file, joinpath(backup_path, basename(metadata_file)))
                end

                # Create backup manifest
                manifest = Dict(
                    "backup_date" => string(now()),
                    "key_id" => string(key_id),
                    "algorithm" => stored_key.algorithm,
                    "email" => stored_key.email,
                    "encrypted" => encrypt
                )

                write(joinpath(backup_path, "manifest.json"), JSON3.write(manifest))

                log_key_operation("BACKUP", "Key backed up to $backup_path")

                return backup_path
            end
        end

        if !found
            throw(StorageError("Key not found: $key_id"))
        end
    catch e
        throw(StorageError("Failed to backup key: $(e)"))
    end
end

"""
Backup all keys in key directory
"""
function backup_all_keys(key_dir::String, backup_dir::String)::Vector{String}
    try
        keys = list_keys(key_dir)
        backup_paths = String[]

        for stored_key in keys
            try
                path = backup_key(stored_key.id, key_dir, backup_dir, encrypt=false)
                push!(backup_paths, path)
            catch e
                @warn "Failed to backup key $(stored_key.id): $e"
            end
        end

        log_key_operation("BACKUP_ALL", "Backed up $(length(backup_paths)) keys")

        return backup_paths
    catch e
        throw(StorageError("Failed to backup all keys: $(e)"))
    end
end

"""
Restore key from backup
"""
function restore_key(backup_path::String, key_dir::String)::UUID
    try
        # Read manifest
        manifest_file = joinpath(backup_path, "manifest.json")
        if !isfile(manifest_file)
            throw(StorageError("Invalid backup: missing manifest.json"))
        end

        manifest = JSON3.read(read(manifest_file, String))
        key_id = UUID(manifest.key_id)

        # Find key files in backup
        files = readdir(backup_path)

        private_key_file = nothing
        public_key_file = nothing
        metadata_file = nothing

        for file in files
            if endswith(file, ".pub")
                public_key_file = joinpath(backup_path, file)
            elseif endswith(file, ".json") && file != "manifest.json"
                metadata_file = joinpath(backup_path, file)
            elseif !endswith(file, ".pub") && !endswith(file, ".json")
                # Assume this is the private key
                private_key_file = joinpath(backup_path, file)
            end
        end

        if isnothing(private_key_file) || isnothing(public_key_file)
            throw(StorageError("Invalid backup: missing key files"))
        end

        # Ensure key directory exists
        mkpath(key_dir)
        chmod(key_dir, 0o700)

        # Restore files
        dest_private = joinpath(key_dir, basename(private_key_file))
        dest_public = joinpath(key_dir, basename(public_key_file))

        cp(private_key_file, dest_private, force=true)
        chmod(dest_private, 0o600)

        cp(public_key_file, dest_public, force=true)
        chmod(dest_public, 0o644)

        if !isnothing(metadata_file)
            dest_metadata = joinpath(key_dir, basename(metadata_file))
            cp(metadata_file, dest_metadata, force=true)
            chmod(dest_metadata, 0o600)
        end

        log_key_operation("RESTORE", "Key restored from $backup_path")

        return key_id
    catch e
        throw(StorageError("Failed to restore key: $(e)"))
    end
end

"""
List all backups in backup directory
"""
function list_backups(backup_dir::String)::Vector{Dict{String, Any}}
    backups = Dict{String, Any}[]

    if !isdir(backup_dir)
        return backups
    end

    try
        for dir in readdir(backup_dir)
            dir_path = joinpath(backup_dir, dir)

            if isdir(dir_path)
                manifest_file = joinpath(dir_path, "manifest.json")

                if isfile(manifest_file)
                    manifest = JSON3.read(read(manifest_file, String))

                    backup_info = Dict{String, Any}(
                        "path" => dir_path,
                        "key_id" => manifest.key_id,
                        "backup_date" => manifest.backup_date,
                        "algorithm" => manifest.algorithm,
                        "email" => get(manifest, :email, "unknown")
                    )

                    push!(backups, backup_info)
                end
            end
        end

        # Sort by backup date (newest first)
        sort!(backups, by=b->get(b, "backup_date", ""), rev=true)

        return backups
    catch e
        throw(StorageError("Failed to list backups: $(e)"))
    end
end

"""
Clean old backups (keep only N most recent per key)
"""
function clean_old_backups(backup_dir::String; keep::Int=5)::Int
    try
        backups = list_backups(backup_dir)

        # Group by key_id
        by_key = Dict{String, Vector{Dict{String, Any}}}()

        for backup in backups
            key_id = backup["key_id"]
            if !haskey(by_key, key_id)
                by_key[key_id] = Dict{String, Any}[]
            end
            push!(by_key[key_id], backup)
        end

        deleted_count = 0

        # For each key, keep only N most recent backups
        for (key_id, key_backups) in by_key
            if length(key_backups) > keep
                # Already sorted by date, delete oldest
                to_delete = key_backups[(keep+1):end]

                for backup in to_delete
                    rm(backup["path"], recursive=true, force=true)
                    deleted_count += 1
                    @info "Deleted old backup: $(backup["path"])"
                end
            end
        end

        log_key_operation("CLEANUP", "Deleted $deleted_count old backups")

        return deleted_count
    catch e
        throw(StorageError("Failed to clean old backups: $(e)"))
    end
end
