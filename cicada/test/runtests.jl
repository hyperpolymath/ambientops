"""
Comprehensive test suite for PalimpsestCryptoIdentity
"""

using Test
using Dates
using UUIDs

# Add src to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

# Run all test modules
@testset "PalimpsestCryptoIdentity Test Suite" begin
    include("test_types.jl")
    include("test_keygen.jl")
    include("test_storage.jl")
    include("test_validation.jl")
    include("test_config.jl")
end
