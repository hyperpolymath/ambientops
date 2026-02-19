"""
Tests for key generation
"""

include("../src/keygen/types.jl")
include("../src/keygen/classical.jl")
include("../src/keygen/postquantum.jl")
include("../src/utils/errors.jl")
include("../src/utils/logging.jl")

# Suppress logging during tests
configure_logging(0)

@testset "Key Generation" begin
    @testset "Ed25519 generation" begin
        keypair = generate_ed25519("test@example.com", comment="test key")

        @test keypair isa KeyPair
        @test keypair.metadata.algorithm == ED25519
        @test keypair.metadata.email == "test@example.com"
        @test length(keypair.public_key) > 0
        @test length(keypair.private_key) > 0
    end

    @testset "RSA generation" begin
        # Test RSA-4096
        keypair = generate_rsa("test@example.com", 4096)

        @test keypair isa KeyPair
        @test keypair.metadata.algorithm == RSA4096
        @test length(keypair.public_key) > 0
        @test length(keypair.private_key) > 0
    end

    @testset "ECDSA generation" begin
        keypair = generate_ecdsa("test@example.com", bits=256)

        @test keypair isa KeyPair
        @test keypair.metadata.algorithm == ECDSA_P256
        @test length(keypair.public_key) > 0
    end

    @testset "Post-quantum stub generation" begin
        # Test Dilithium stub
        keypair = generate_dilithium("test@example.com", 3)

        @test keypair isa KeyPair
        @test keypair.metadata.algorithm == DILITHIUM3
        @test keypair.metadata.quantum_resistant == true

        # Test Kyber stub
        keypair = generate_kyber("test@example.com", 768)

        @test keypair isa KeyPair
        @test keypair.metadata.algorithm == KYBER768
    end

    @testset "Hybrid key generation" begin
        (classical, pqc) = generate_hybrid_qr("test@example.com")

        @test classical.metadata.algorithm == ED25519
        @test pqc.metadata.algorithm == DILITHIUM3
        @test !classical.metadata.quantum_resistant
        @test pqc.metadata.quantum_resistant
    end

    @testset "PQC info" begin
        info = pqc_info()

        @test haskey(info, "available")
        @test haskey(info, "implementation")
        @test info["implementation"] == "stub"
    end
end
