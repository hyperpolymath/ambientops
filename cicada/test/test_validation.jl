"""
Tests for key validation
"""

include("../src/keygen/types.jl")
include("../src/keygen/classical.jl")
include("../src/validation/verify.jl")
include("../src/utils/errors.jl")
include("../src/utils/logging.jl")

# Suppress logging during tests
configure_logging(0)

@testset "Key Validation" begin
    @testset "Validate public key" begin
        keypair = generate_ed25519("test@example.com")

        @test validate_public_key(keypair.public_key) == true
    end

    @testset "Validate private key" begin
        keypair = generate_ed25519("test@example.com")

        @test validate_private_key(keypair.private_key) == true
    end

    @testset "Verify keypair match" begin
        keypair = generate_ed25519("test@example.com")

        @test verify_keypair(keypair) == true
    end

    @testset "Full keypair validation" begin
        keypair = generate_ed25519("test@example.com")

        (is_valid, issues) = validate_keypair(keypair)

        @test is_valid == true
        @test length(issues) == 0
    end

    @testset "Expiration detection" begin
        # Create expired key
        past_date = now() - Day(1)
        metadata = KeyMetadata(ED25519, SSH_AUTH, "test@example.com", "", past_date)

        @test is_expired(metadata) == true

        # Create future expiration
        future_date = now() + Day(365)
        metadata2 = KeyMetadata(ED25519, SSH_AUTH, "test@example.com", "", future_date)

        @test is_expired(metadata2) == false
    end

    @testset "Expiration warning" begin
        # Key expiring in 15 days
        near_future = now() + Day(15)
        metadata = KeyMetadata(ED25519, SSH_AUTH, "test@example.com", "", near_future)

        @test expires_soon(metadata, warning_days=30) == true
        @test expires_soon(metadata, warning_days=10) == false
    end

    @testset "Key strength validation" begin
        # Strong algorithm
        (strong, msg) = validate_key_strength(ED25519)
        @test strong == true

        # Weak algorithm (RSA-2048)
        (strong, msg) = validate_key_strength(RSA2048)
        @test strong == false
    end

    @testset "Security audit" begin
        keypair = generate_ed25519("test@example.com")

        audit = audit_key(keypair)

        @test haskey(audit, "id")
        @test haskey(audit, "algorithm")
        @test haskey(audit, "valid")
        @test haskey(audit, "quantum_resistant")
        @test audit["valid"] == true
    end
end
