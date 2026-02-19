"""
Tests for key types and structures
"""

include("../src/keygen/types.jl")

@testset "Key Types" begin
    @testset "KeyAlgorithm" begin
        @test ED25519 isa KeyAlgorithm
        @test RSA4096 isa KeyAlgorithm
        @test DILITHIUM3 isa KeyAlgorithm
        @test KYBER768 isa KeyAlgorithm
    end

    @testset "KeyPurpose" begin
        @test SSH_AUTH isa KeyPurpose
        @test ENCRYPTION isa KeyPurpose
    end

    @testset "KeyMetadata creation" begin
        metadata = KeyMetadata(
            ED25519,
            SSH_AUTH,
            "test@example.com",
            "test comment"
        )

        @test metadata.algorithm == ED25519
        @test metadata.purpose == SSH_AUTH
        @test metadata.email == "test@example.com"
        @test metadata.comment == "test comment"
        @test metadata.id isa UUID
        @test metadata.created_at isa DateTime
        @test metadata.quantum_resistant == false
    end

    @testset "Post-quantum metadata" begin
        metadata = KeyMetadata(
            DILITHIUM3,
            SSH_AUTH,
            "test@example.com"
        )

        @test metadata.quantum_resistant == true
    end

    @testset "Algorithm names" begin
        @test algorithm_name(ED25519) == "Ed25519"
        @test algorithm_name(RSA4096) == "RSA-4096"
        @test algorithm_name(DILITHIUM3) == "Dilithium3 (NIST Level 3)"
        @test algorithm_name(KYBER768) == "Kyber768 (NIST Level 3)"
    end

    @testset "Key sizes" begin
        @test key_size(ED25519) == 256
        @test key_size(RSA4096) == 4096
        @test key_size(DILITHIUM3) == 4000
    end

    @testset "Post-quantum detection" begin
        @test is_post_quantum(ED25519) == false
        @test is_post_quantum(RSA4096) == false
        @test is_post_quantum(DILITHIUM3) == true
        @test is_post_quantum(KYBER768) == true
    end
end
