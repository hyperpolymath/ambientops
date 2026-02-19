"""
Tests for configuration management
"""

include("../src/config.jl")

@testset "Configuration" begin
    @testset "Default Config" begin
        config = Config()

        @test config.key_dir == joinpath(homedir(), ".cicada", "keys")
        @test config.backup_dir == joinpath(homedir(), ".cicada", "backups")
        @test config.key_size == 4096
        @test config.quantum_resistant == true
        @test config.verbosity == 2
    end

    @testset "Config save/load" begin
        temp_dir = mktempdir()
        config_path = joinpath(temp_dir, "test_config.toml")

        # Create and save config
        config = Config()
        config.key_size = 2048
        config.verbosity = 3

        save_config(config, config_path)

        @test isfile(config_path)

        # Load and verify
        loaded_config = load_config(config_path)

        @test loaded_config.key_size == 2048
        @test loaded_config.verbosity == 3

        # Cleanup
        rm(temp_dir, recursive=true, force=true)
    end

    @testset "Missing config file" begin
        config = load_config("/nonexistent/path/config.toml")
        @test config isa Config
    end
end
