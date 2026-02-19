"""
Configuration management for PalimpsestCryptoIdentity
"""

using TOML
using UUIDs

include("utils/errors.jl")

"""
Application configuration structure
"""
mutable struct Config
    # Key storage
    key_dir::String
    backup_dir::String

    # Security settings
    key_size::Int
    quantum_resistant::Bool

    # GitHub integration
    github_token::Union{String, Nothing}
    github_username::Union{String, Nothing}

    # Logging
    verbosity::Int

    # MFA settings
    require_mfa::Bool

    Config() = new(
        joinpath(homedir(), ".cicada", "keys"),
        joinpath(homedir(), ".cicada", "backups"),
        4096,
        true,
        nothing,
        nothing,
        2,
        false
    )
end

"""
Load configuration from TOML file
"""
function load_config(path::String)::Config
    config = Config()

    if !isfile(path)
        @warn "Config file not found at $path, using defaults"
        return config
    end

    try
        data = TOML.parsefile(path)

        # Parse storage settings
        if haskey(data, "storage")
            storage = data["storage"]
            config.key_dir = get(storage, "key_dir", config.key_dir)
            config.backup_dir = get(storage, "backup_dir", config.backup_dir)
        end

        # Parse security settings
        if haskey(data, "security")
            security = data["security"]
            config.key_size = get(security, "key_size", config.key_size)
            config.quantum_resistant = get(security, "quantum_resistant", config.quantum_resistant)
            config.require_mfa = get(security, "require_mfa", config.require_mfa)
        end

        # Parse GitHub settings
        if haskey(data, "github")
            github = data["github"]
            config.github_token = get(github, "token", nothing)
            config.github_username = get(github, "username", nothing)
        end

        # Parse logging settings
        if haskey(data, "logging")
            logging = data["logging"]
            config.verbosity = get(logging, "verbosity", config.verbosity)
        end

        return config
    catch e
        throw(ConfigurationError("Failed to parse config file: $(e)"))
    end
end

"""
Save configuration to TOML file
"""
function save_config(config::Config, path::String)
    data = Dict(
        "storage" => Dict(
            "key_dir" => config.key_dir,
            "backup_dir" => config.backup_dir
        ),
        "security" => Dict(
            "key_size" => config.key_size,
            "quantum_resistant" => config.quantum_resistant,
            "require_mfa" => config.require_mfa
        ),
        "logging" => Dict(
            "verbosity" => config.verbosity
        )
    )

    # Add GitHub settings if present
    if !isnothing(config.github_token) || !isnothing(config.github_username)
        data["github"] = Dict()
        if !isnothing(config.github_token)
            data["github"]["token"] = config.github_token
        end
        if !isnothing(config.github_username)
            data["github"]["username"] = config.github_username
        end
    end

    # Ensure directory exists
    mkpath(dirname(path))

    try
        open(path, "w") do io
            TOML.print(io, data)
        end
    catch e
        throw(ConfigurationError("Failed to save config file: $(e)"))
    end
end

"""
Get default config path
"""
function default_config_path()::String
    return joinpath(homedir(), ".cicada", "config.toml")
end

"""
Initialize configuration directories
"""
function init_config_dirs(config::Config)
    try
        mkpath(config.key_dir)
        mkpath(config.backup_dir)

        # Set restrictive permissions on key directory
        chmod(config.key_dir, 0o700)
        chmod(config.backup_dir, 0o700)

        @info "Initialized configuration directories"
    catch e
        throw(ConfigurationError("Failed to initialize directories: $(e)"))
    end
end
