"""
Tests for key storage and management
"""

include("../src/keygen/types.jl")
include("../src/keygen/classical.jl")
include("../src/storage/keystore.jl")
include("../src/storage/backup.jl")
include("../src/utils/errors.jl")
include("../src/utils/logging.jl")

# Suppress logging during tests
configure_logging(0)

@testset "Key Storage" begin
    @testset "Save and list keys" begin
        temp_dir = mktempdir()

        # Generate and save key
        keypair = generate_ed25519("test@example.com")
        (priv_path, pub_path, meta_path) = save_keypair(keypair, temp_dir)

        @test isfile(priv_path)
        @test isfile(pub_path)
        @test isfile(meta_path)

        # List keys
        keys = list_keys(temp_dir)

        @test length(keys) == 1
        @test keys[1].id == keypair.metadata.id
        @test keys[1].email == "test@example.com"

        # Cleanup
        rm(temp_dir, recursive=true, force=true)
    end

    @testset "Load keypair" begin
        temp_dir = mktempdir()

        # Generate and save
        keypair = generate_ed25519("test@example.com")
        save_keypair(keypair, temp_dir)

        # Load
        loaded = load_keypair(keypair.metadata.id, temp_dir)

        @test !isnothing(loaded)
        @test loaded.metadata.id == keypair.metadata.id
        @test loaded.metadata.email == "test@example.com"

        # Cleanup
        rm(temp_dir, recursive=true, force=true)
    end

    @testset "Delete key" begin
        temp_dir = mktempdir()

        # Generate and save
        keypair = generate_ed25519("test@example.com")
        save_keypair(keypair, temp_dir)

        # Delete
        result = delete_key(keypair.metadata.id, temp_dir)

        @test result == true

        # Verify deleted
        keys = list_keys(temp_dir)
        @test length(keys) == 0

        # Cleanup
        rm(temp_dir, recursive=true, force=true)
    end

    @testset "Backup and restore" begin
        key_dir = mktempdir()
        backup_dir = mktempdir()

        # Generate and save
        keypair = generate_ed25519("test@example.com")
        save_keypair(keypair, key_dir)

        # Backup
        backup_path = backup_key(keypair.metadata.id, key_dir, backup_dir)

        @test isdir(backup_path)

        # Delete original
        delete_key(keypair.metadata.id, key_dir)

        # Restore
        restored_id = restore_key(backup_path, key_dir)

        @test restored_id == keypair.metadata.id

        # Verify restored
        keys = list_keys(key_dir)
        @test length(keys) == 1

        # Cleanup
        rm(key_dir, recursive=true, force=true)
        rm(backup_dir, recursive=true, force=true)
    end

    @testset "Backup all keys" begin
        key_dir = mktempdir()
        backup_dir = mktempdir()

        # Generate multiple keys
        keypair1 = generate_ed25519("test1@example.com")
        keypair2 = generate_ed25519("test2@example.com")

        save_keypair(keypair1, key_dir)
        save_keypair(keypair2, key_dir)

        # Backup all
        paths = backup_all_keys(key_dir, backup_dir)

        @test length(paths) == 2

        # Cleanup
        rm(key_dir, recursive=true, force=true)
        rm(backup_dir, recursive=true, force=true)
    end
end
