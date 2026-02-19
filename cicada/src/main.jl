"""
PalimpsestCryptoIdentity - CIcaDA
Quantum-Resistant Cryptographic Identity Management
"""

module PalimpsestCryptoIdentity

using ArgParse
using Logging
using Dates
using UUIDs

# Include all modules
include("utils/errors.jl")
include("utils/logging.jl")
include("config.jl")
include("keygen/types.jl")
include("keygen/classical.jl")
include("keygen/postquantum.jl")
include("storage/keystore.jl")
include("storage/backup.jl")
include("storage/rotation.jl")
include("validation/verify.jl")
include("integrations/github.jl")

"""
Parse command-line arguments
"""
function parse_commandline()
    s = ArgParseSettings(
        description = "CIcaDA - Palimpsest Crypto Identity: Quantum-Resistant SSH Key Management",
        version = "0.1.0",
        add_version = true
    )

    @add_arg_table! s begin
        "generate"
            help = "Generate a new cryptographic key pair"
            action = :command

        "list"
            help = "List all stored keys"
            action = :command

        "info"
            help = "Show detailed information about a key"
            action = :command

        "validate"
            help = "Validate a key pair"
            action = :command

        "backup"
            help = "Backup keys"
            action = :command

        "restore"
            help = "Restore keys from backup"
            action = :command

        "rotate"
            help = "Rotate a key (backup old, generate new)"
            action = :command

        "github"
            help = "GitHub integration commands"
            action = :command

        "audit"
            help = "Security audit of keys"
            action = :command

        "init"
            help = "Initialize CIcaDA configuration"
            action = :command

        "pqc-info"
            help = "Show post-quantum cryptography support information"
            action = :command
    end

    # Generate command
    @add_arg_table! s["generate"] begin
        "--email", "-e"
            help = "Email address for key"
            required = true
        "--algorithm", "-a"
            help = "Key algorithm (ed25519, rsa2048, rsa4096, ecdsa256, ecdsa384, dilithium2, dilithium3, dilithium5, kyber512, kyber768, kyber1024, hybrid)"
            default = "ed25519"
        "--comment", "-c"
            help = "Comment for key"
            default = ""
        "--expires"
            help = "Expiration date (YYYY-MM-DD)"
            default = nothing
        "--name", "-n"
            help = "Custom name for key file"
            default = nothing
        "--verbose", "-v"
            help = "Verbose output"
            action = :store_true
    end

    # List command
    @add_arg_table! s["list"] begin
        "--format", "-f"
            help = "Output format (table, json)"
            default = "table"
        "--verbose", "-v"
            help = "Show detailed information"
            action = :store_true
    end

    # Info command
    @add_arg_table! s["info"] begin
        "--id"
            help = "Key ID (UUID)"
            required = true
    end

    # Validate command
    @add_arg_table! s["validate"] begin
        "--id"
            help = "Key ID to validate"
            required = true
    end

    # Backup command
    @add_arg_table! s["backup"] begin
        "--id"
            help = "Key ID to backup (omit for all keys)"
            default = nothing
        "--clean"
            help = "Clean old backups (keep only N recent per key)"
            arg_type = Int
            default = nothing
    end

    # Restore command
    @add_arg_table! s["restore"] begin
        "--backup-path"
            help = "Path to backup directory"
            required = true
    end

    # Rotate command
    @add_arg_table! s["rotate"] begin
        "--id"
            help = "Key ID to rotate"
            default = nothing
        "--auto"
            help = "Auto-rotate expiring keys"
            action = :store_true
        "--all"
            help = "Rotate all keys (security incident)"
            action = :store_true
        "--warning-days"
            help = "Days before expiration to trigger auto-rotation"
            arg_type = Int
            default = 30
    end

    # GitHub command
    @add_arg_table! s["github"] begin
        "--action"
            help = "Action (upload, list, delete, verify-token)"
            required = true
        "--id"
            help = "Local key ID for upload"
            default = nothing
        "--github-key-id"
            help = "GitHub key ID for delete"
            arg_type = Int
            default = nothing
        "--token"
            help = "GitHub personal access token"
            default = nothing
        "--title"
            help = "Title for uploaded key"
            default = nothing
    end

    # Audit command
    @add_arg_table! s["audit"] begin
        "--id"
            help = "Key ID to audit (omit for all keys)"
            default = nothing
        "--format", "-f"
            help = "Output format (table, json)"
            default = "table"
    end

    # Init command
    @add_arg_table! s["init"] begin
        "--force"
            help = "Force re-initialization"
            action = :store_true
    end

    return parse_args(s)
end

"""
Main entry point
"""
function main(args::Vector{String} = ARGS)
    try
        parsed_args = parse_commandline()

        # Load configuration
        config_path = default_config_path()
        config = if isfile(config_path)
            load_config(config_path)
        else
            Config()
        end

        # Configure logging
        verbosity = get(parsed_args, "verbose", false) ? 3 : config.verbosity
        configure_logging(verbosity)

        # Handle commands
        if parsed_args["%COMMAND%"] == "init"
            cmd_init(config, parsed_args["init"])

        elseif parsed_args["%COMMAND%"] == "generate"
            cmd_generate(config, parsed_args["generate"])

        elseif parsed_args["%COMMAND%"] == "list"
            cmd_list(config, parsed_args["list"])

        elseif parsed_args["%COMMAND%"] == "info"
            cmd_info(config, parsed_args["info"])

        elseif parsed_args["%COMMAND%"] == "validate"
            cmd_validate(config, parsed_args["validate"])

        elseif parsed_args["%COMMAND%"] == "backup"
            cmd_backup(config, parsed_args["backup"])

        elseif parsed_args["%COMMAND%"] == "restore"
            cmd_restore(config, parsed_args["restore"])

        elseif parsed_args["%COMMAND%"] == "rotate"
            cmd_rotate(config, parsed_args["rotate"])

        elseif parsed_args["%COMMAND%"] == "github"
            cmd_github(config, parsed_args["github"])

        elseif parsed_args["%COMMAND%"] == "audit"
            cmd_audit(config, parsed_args["audit"])

        elseif parsed_args["%COMMAND%"] == "pqc-info"
            cmd_pqc_info()

        else
            println("CIcaDA - Palimpsest Crypto Identity")
            println("Use --help for usage information")
        end

    catch e
        if e isa CIcaDAError
            println(stderr, "ERROR: $e")
            exit(1)
        else
            rethrow(e)
        end
    end
end

# Command implementations

function cmd_init(config::Config, args::Dict)
    println("Initializing CIcaDA configuration...")

    config_path = default_config_path()

    if isfile(config_path) && !args["force"]
        println("Configuration already exists at $config_path")
        println("Use --force to re-initialize")
        return
    end

    init_config_dirs(config)
    save_config(config, config_path)

    println("✓ Configuration initialized")
    println("  Config file: $config_path")
    println("  Key directory: $(config.key_dir)")
    println("  Backup directory: $(config.backup_dir)")
end

function cmd_generate(config::Config, args::Dict)
    init_config_dirs(config)

    email = args["email"]
    algorithm_str = lowercase(args["algorithm"])
    comment = args["comment"]
    name = args["name"]

    # Parse expiration date
    expires_at = if !isnothing(args["expires"])
        try
            DateTime(args["expires"], "yyyy-mm-dd")
        catch
            throw(ConfigurationError("Invalid date format. Use YYYY-MM-DD"))
        end
    else
        nothing
    end

    println("Generating key pair...")
    println("  Algorithm: $algorithm_str")
    println("  Email: $email")

    # Generate based on algorithm
    if algorithm_str == "ed25519"
        keypair = generate_ed25519(email, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "rsa2048"
        keypair = generate_rsa(email, 2048, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "rsa4096"
        keypair = generate_rsa(email, 4096, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "ecdsa256"
        keypair = generate_ecdsa(email, bits=256, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "ecdsa384"
        keypair = generate_ecdsa(email, bits=384, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "dilithium2"
        keypair = generate_dilithium(email, 2, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "dilithium3"
        keypair = generate_dilithium(email, 3, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "dilithium5"
        keypair = generate_dilithium(email, 5, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "kyber512"
        keypair = generate_kyber(email, 512, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "kyber768"
        keypair = generate_kyber(email, 768, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "kyber1024"
        keypair = generate_kyber(email, 1024, comment=comment, expires_at=expires_at)
    elseif algorithm_str == "hybrid"
        (classical, pqc) = generate_hybrid_qr(email, comment=comment, expires_at=expires_at)
        (priv1, pub1, _) = save_keypair(classical, config.key_dir, name=isnothing(name) ? nothing : "$(name)_ed25519")
        (priv2, pub2, _) = save_keypair(pqc, config.key_dir, name=isnothing(name) ? nothing : "$(name)_dilithium3")
        println("\n✓ Hybrid quantum-resistant key pair generated!")
        println("  Classical (Ed25519):")
        println("    Private key: $priv1")
        println("    Public key: $pub1")
        println("  Post-Quantum (Dilithium3):")
        println("    Private key: $priv2")
        println("    Public key: $pub2")
        return
    else
        throw(ConfigurationError("Unknown algorithm: $algorithm_str"))
    end

    # Save key
    (private_path, public_path, _) = save_keypair(keypair, config.key_dir, name=name)

    println("\n✓ Key pair generated successfully!")
    println("  Key ID: $(keypair.metadata.id)")
    println("  Private key: $private_path")
    println("  Public key: $public_path")
    println("  Quantum-resistant: $(keypair.metadata.quantum_resistant)")

    if keypair.metadata.quantum_resistant
        println("\n⚠ Note: PQC keys are currently stub implementations")
        println("   For production use, install NistyPQC.jl")
    end
end

function cmd_list(config::Config, args::Dict)
    keys = list_keys(config.key_dir)

    if length(keys) == 0
        println("No keys found in $(config.key_dir)")
        return
    end

    println("Stored keys ($(length(keys)) total):\n")

    if args["format"] == "json"
        println(JSON3.write(keys, allow_inf=true))
    else
        for (i, key) in enumerate(keys)
            println("[$i] $(key.id)")
            println("    Algorithm: $(key.algorithm)")
            println("    Email: $(key.email)")
            println("    Created: $(key.created_at)")
            println("    Quantum-resistant: $(key.quantum_resistant)")

            if !isnothing(key.expires_at)
                println("    Expires: $(key.expires_at)")
            end

            if args["verbose"]
                println("    Private key: $(key.private_key_path)")
                println("    Public key: $(key.public_key_path)")
                if !isempty(key.fingerprint)
                    println("    Fingerprint: $(key.fingerprint)")
                end
            end

            println()
        end
    end
end

function cmd_info(config::Config, args::Dict)
    key_id = UUID(args["id"])
    keys = list_keys(config.key_dir)

    for key in keys
        if key.id == key_id
            println("Key Information:")
            println("  ID: $(key.id)")
            println("  Algorithm: $(key.algorithm)")
            println("  Purpose: $(key.purpose)")
            println("  Email: $(key.email)")
            println("  Comment: $(key.comment)")
            println("  Created: $(key.created_at)")
            println("  Quantum-resistant: $(key.quantum_resistant)")
            println("  Fingerprint: $(key.fingerprint)")
            println("  Private key: $(key.private_key_path)")
            println("  Public key: $(key.public_key_path)")

            if !isnothing(key.expires_at)
                println("  Expires: $(key.expires_at)")
            else
                println("  Expires: Never")
            end

            return
        end
    end

    println(stderr, "Key not found: $key_id")
    exit(1)
end

function cmd_validate(config::Config, args::Dict)
    key_id = UUID(args["id"])
    keypair = load_keypair(key_id, config.key_dir)

    if isnothing(keypair)
        println(stderr, "Key not found: $key_id")
        exit(1)
    end

    println("Validating key $(keypair.metadata.id)...")

    (is_valid, issues) = validate_keypair(keypair)

    if is_valid
        println("✓ Key is valid")
    else
        println("✗ Key validation failed:")
        for issue in issues
            println("  - $issue")
        end
        exit(1)
    end
end

function cmd_backup(config::Config, args::Dict)
    if !isnothing(args["clean"])
        count = clean_old_backups(config.backup_dir, keep=args["clean"])
        println("✓ Cleaned $count old backups")
        return
    end

    if isnothing(args["id"])
        # Backup all keys
        paths = backup_all_keys(config.key_dir, config.backup_dir)
        println("✓ Backed up $(length(paths)) keys to $(config.backup_dir)")
    else
        # Backup specific key
        key_id = UUID(args["id"])
        path = backup_key(key_id, config.key_dir, config.backup_dir)
        println("✓ Key backed up to $path")
    end
end

function cmd_restore(config::Config, args::Dict)
    backup_path = args["backup-path"]
    key_id = restore_key(backup_path, config.key_dir)
    println("✓ Key restored: $key_id")
end

function cmd_rotate(config::Config, args::Dict)
    if args["all"]
        println("⚠ WARNING: This will rotate ALL keys!")
        println("This should only be done in response to a security incident.")
        print("Continue? (yes/no): ")
        response = readline()

        if lowercase(strip(response)) != "yes"
            println("Cancelled")
            return
        end

        rotated = rotate_all_keys(config.key_dir, config.backup_dir)
        println("\n✓ Rotated $(length(rotated)) keys")

        for (old_id, new_id) in rotated
            println("  $old_id -> $new_id")
        end

    elseif args["auto"]
        rotated = auto_rotate_expiring_keys(
            config.key_dir,
            config.backup_dir,
            warning_days=args["warning-days"]
        )

        if length(rotated) > 0
            println("✓ Auto-rotated $(length(rotated)) expiring keys")
            for (old_id, new_id) in rotated
                println("  $old_id -> $new_id")
            end
        else
            println("✓ No keys need rotation")
        end

    elseif !isnothing(args["id"])
        key_id = UUID(args["id"])
        (old_id, new_id) = rotate_key(key_id, config.key_dir, config.backup_dir)
        println("✓ Key rotated")
        println("  Old: $old_id")
        println("  New: $new_id")

    else
        println(stderr, "Specify --id, --auto, or --all")
        exit(1)
    end
end

function cmd_github(config::Config, args::Dict)
    action = args["action"]

    # Get token from args or config
    token = args["token"]
    if isnothing(token)
        token = config.github_token
    end

    if isnothing(token) && action != "help"
        println(stderr, "GitHub token required. Use --token or configure in config.toml")
        exit(1)
    end

    if action == "upload"
        if isnothing(args["id"])
            println(stderr, "--id required for upload")
            exit(1)
        end

        key_id = UUID(args["id"])
        result = upload_to_github(key_id, config.key_dir, token, title=args["title"])

        println("✓ Key uploaded to GitHub")
        println("  GitHub Key ID: $(result["github_key_id"])")
        println("  Title: $(result["title"])")

    elseif action == "list"
        keys = list_github_keys(token)
        println("GitHub SSH Keys ($(length(keys)) total):\n")

        for (i, key) in enumerate(keys)
            println("[$i] ID: $(key["id"])")
            println("    Title: $(key["title"])")
            println("    Created: $(key["created_at"])")
            println()
        end

    elseif action == "delete"
        if isnothing(args["github-key-id"])
            println(stderr, "--github-key-id required for delete")
            exit(1)
        end

        delete_from_github(token, args["github-key-id"])
        println("✓ Key deleted from GitHub")

    elseif action == "verify-token"
        if verify_github_token(token)
            println("✓ GitHub token is valid")
        else
            println("✗ GitHub token is invalid")
            exit(1)
        end

    else
        println(stderr, "Unknown action: $action")
        println("Valid actions: upload, list, delete, verify-token")
        exit(1)
    end
end

function cmd_audit(config::Config, args::Dict)
    if isnothing(args["id"])
        # Audit all keys
        keys = list_keys(config.key_dir)
        println("Security Audit ($(length(keys)) keys):\n")

        for stored_key in keys
            keypair = load_keypair(stored_key.id, config.key_dir)
            if !isnothing(keypair)
                audit = audit_key(keypair)
                println("Key: $(audit["id"])")
                println("  Algorithm: $(audit["algorithm"]) ($(audit["key_size"]) bits)")
                println("  QR: $(audit["quantum_resistant"])")
                println("  Age: $(audit["age_days"]) days")
                println("  Valid: $(audit["valid"])")

                if length(audit["issues"]) > 0
                    println("  Issues:")
                    for issue in audit["issues"]
                        println("    - $issue")
                    end
                end

                println()
            end
        end
    else
        # Audit specific key
        key_id = UUID(args["id"])
        keypair = load_keypair(key_id, config.key_dir)

        if isnothing(keypair)
            println(stderr, "Key not found: $key_id")
            exit(1)
        end

        audit = audit_key(keypair)

        if args["format"] == "json"
            println(JSON3.write(audit, allow_inf=true))
        else
            println("Security Audit for $(audit["id"]):")
            println("  Algorithm: $(audit["algorithm"]) ($(audit["key_size"]) bits)")
            println("  Quantum-resistant: $(audit["quantum_resistant"])")
            println("  Created: $(audit["created_at"])")
            println("  Age: $(audit["age_days"]) days")
            println("  Expiration: $(audit["expiration"])")
            println("  Expired: $(audit["expired"])")
            println("  Valid: $(audit["valid"])")
            println("  Strong: $(audit["strong"])")
            println("  Assessment: $(audit["strength_message"])")

            if length(audit["issues"]) > 0
                println("\nIssues:")
                for issue in audit["issues"]
                    println("  - $issue")
                end
            end
        end
    end
end

function cmd_pqc_info()
    info = pqc_info()

    println("Post-Quantum Cryptography Support:")
    println("  Available: $(info["available"])")
    println("  Implementation: $(info["implementation"])")
    println("  Recommended library: $(info["recommended_library"])")
    println("\nSupported algorithms:")
    for algo in info["supported_algorithms"]
        println("  - $algo")
    end
    println("\nNote: $(info["note"])")
end

# Allow script to be run directly
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end

end # module
