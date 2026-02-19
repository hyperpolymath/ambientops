"""
Custom error types for PalimpsestCryptoIdentity
"""

# Base error type
abstract type CIcaDAError <: Exception end

# Configuration errors
struct ConfigurationError <: CIcaDAError
    msg::String
end

# Key generation errors
struct KeyGenerationError <: CIcaDAError
    msg::String
end

# Key validation errors
struct KeyValidationError <: CIcaDAError
    msg::String
end

# Storage errors
struct StorageError <: CIcaDAError
    msg::String
end

# Integration errors
struct IntegrationError <: CIcaDAError
    msg::String
end

# Security errors
struct SecurityError <: CIcaDAError
    msg::String
end

# Display methods
Base.showerror(io::IO, e::ConfigurationError) = print(io, "Configuration Error: ", e.msg)
Base.showerror(io::IO, e::KeyGenerationError) = print(io, "Key Generation Error: ", e.msg)
Base.showerror(io::IO, e::KeyValidationError) = print(io, "Key Validation Error: ", e.msg)
Base.showerror(io::IO, e::StorageError) = print(io, "Storage Error: ", e.msg)
Base.showerror(io::IO, e::IntegrationError) = print(io, "Integration Error: ", e.msg)
Base.showerror(io::IO, e::SecurityError) = print(io, "Security Error: ", e.msg)
