"""
    diagnostics_integration.jl - Julia Integration Layer for D-based Diagnostics

    Integrates D-language system diagnostics with Juisys.
    Provides developer-focused technical diagnostics as optional add-on.

    PRIVACY: Same guarantees as core Juisys
    - Requires explicit consent via Security module
    - All data ephemeral
    - No network transmission
    - Optional activation only

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module DiagnosticsIntegration

export DiagnosticsLevel, SystemDiagnostics
export run_diagnostics, diagnostics_enabled, enable_diagnostics

using ..Security
using JSON3

"""
    DiagnosticsLevel

    Diagnostic depth levels matching D implementation
"""
@enum DiagnosticsLevel begin
    BASIC = 0
    STANDARD = 1
    DEEP = 2
    FORENSIC = 3
end

"""
    Diagnostics configuration
"""
mutable struct DiagnosticsConfig
    enabled::Bool
    level::DiagnosticsLevel
    lib_path::String
    consent_granted::Bool

    DiagnosticsConfig() = new(false, STANDARD, "", false)
end

# Global configuration
const DIAG_CONFIG = Ref{DiagnosticsConfig}()

"""
    init_diagnostics_config()

    Initialize diagnostics configuration
"""
function init_diagnostics_config()
    DIAG_CONFIG[] = DiagnosticsConfig()

    # Try to locate diagnostics library
    lib_candidates = [
        "src-diagnostics/d/libdiagnostics.so",
        "src-diagnostics/d/libdiagnostics.dylib",
        "/usr/local/lib/juisys/libdiagnostics.dylib"
    ]

    for path in lib_candidates
        if isfile(path)
            DIAG_CONFIG[].lib_path = path
            @info "Found diagnostics library" path=path
            break
        end
    end

    if isempty(DIAG_CONFIG[].lib_path)
        @warn "Diagnostics library not found - advanced diagnostics disabled"
        @info "To enable: compile src-diagnostics/d/diagnostics.d"
    end

    return nothing
end

"""
    enable_diagnostics(level::DiagnosticsLevel = STANDARD)

    Enable diagnostics add-on with specified level
"""
function enable_diagnostics(level::DiagnosticsLevel = STANDARD)
    if !isdefined(DIAG_CONFIG, :x)
        init_diagnostics_config()
    end

    if isempty(DIAG_CONFIG[].lib_path)
        @error "Cannot enable diagnostics - library not found"
        return false
    end

    DIAG_CONFIG[].enabled = true
    DIAG_CONFIG[].level = level

    @info "Diagnostics add-on enabled" level=level

    return true
end

"""
    diagnostics_enabled()

    Check if diagnostics add-on is enabled
"""
function diagnostics_enabled()
    if !isdefined(DIAG_CONFIG, :x)
        return false
    end

    return DIAG_CONFIG[].enabled && !isempty(DIAG_CONFIG[].lib_path)
end

"""
    SystemDiagnostics

    High-level interface to D-based diagnostics
"""
struct SystemDiagnostics
    handle::Ptr{Nothing}
    level::DiagnosticsLevel

    function SystemDiagnostics(level::DiagnosticsLevel = STANDARD)
        if !diagnostics_enabled()
            error("Diagnostics not enabled - call enable_diagnostics() first")
        end

        # Load library and create diagnostics instance
        lib = DIAG_CONFIG[].lib_path

        handle = ccall(
            (:createDiagnostics, lib),
            Ptr{Nothing},
            (Int32,),
            Int32(level)
        )

        if handle == C_NULL
            error("Failed to create diagnostics instance")
        end

        diag = new(handle, level)

        # Register finalizer to clean up
        finalizer(diag) do d
            ccall(
                (:destroyDiagnostics, DIAG_CONFIG[].lib_path),
                Nothing,
                (Ptr{Nothing},),
                d.handle
            )
        end

        return diag
    end
end

"""
    request_consent(diag::SystemDiagnostics)

    Request user consent for diagnostics collection
    Integrates with Juisys Security module
"""
function request_consent(diag::SystemDiagnostics)
    # First check Juisys Security module consent
    if !Security.has_consent(Security.SYSTEM_SCAN)
        granted = Security.request_consent(
            Security.SYSTEM_SCAN,
            "System diagnostics require scanning system configuration"
        )

        if !granted
            @warn "System scan consent denied - diagnostics cannot run"
            return false
        end
    end

    # Then request diagnostics-specific consent via D library
    lib = DIAG_CONFIG[].lib_path

    granted = ccall(
        (:requestDiagnosticsConsent, lib),
        Bool,
        (Ptr{Nothing},),
        diag.handle
    )

    DIAG_CONFIG[].consent_granted = granted

    return granted
end

"""
    run_diagnostics(diag::SystemDiagnostics)

    Run diagnostics collection
    Returns: Dict with diagnostic results
"""
function run_diagnostics(diag::SystemDiagnostics)
    if !DIAG_CONFIG[].consent_granted
        @warn "Consent required before running diagnostics"

        if !request_consent(diag)
            return nothing
        end
    end

    lib = DIAG_CONFIG[].lib_path

    # Run diagnostics via D library
    ccall(
        (:runDiagnostics, lib),
        Nothing,
        (Ptr{Nothing},),
        diag.handle
    )

    # Export results as JSON
    json_ptr = ccall(
        (:exportDiagnosticsJSON, lib),
        Ptr{UInt8},
        (Ptr{Nothing},),
        diag.handle
    )

    if json_ptr == C_NULL
        error("Failed to export diagnostics data")
    end

    json_str = unsafe_string(json_ptr)

    # Parse JSON
    results = JSON3.read(json_str)

    @info "Diagnostics complete" total_diagnostics=results[:total_diagnostics]

    return results
end

"""
    clear_diagnostics_data(diag::SystemDiagnostics)

    Clear diagnostic data (GDPR compliance)
"""
function clear_diagnostics_data(diag::SystemDiagnostics)
    lib = DIAG_CONFIG[].lib_path

    ccall(
        (:clearDiagnosticsData, lib),
        Nothing,
        (Ptr{Nothing},),
        diag.handle
    )

    @info "Diagnostics data cleared (GDPR Article 17)"
end

"""
    format_diagnostic_report(results::Dict)

    Format diagnostic results as human-readable report
"""
function format_diagnostic_report(results::Dict)
    io = IOBuffer()

    println(io, "\n" * "="^70)
    println(io, "JUISYS TECHNICAL DIAGNOSTICS REPORT")
    println(io, "="^70)
    println(io, "Timestamp: $(results[:timestamp])")
    println(io, "Level: $(results[:level])")
    println(io, "Total Diagnostics: $(results[:total_diagnostics])")
    println(io, "")
    println(io, "PRIVACY NOTICE:")
    println(io, "  $(results[:privacy_notice])")
    println(io, "="^70)
    println(io, "")

    # Group by category
    by_category = Dict{String, Vector}()

    for result in results[:results]
        category = result[:category]

        if !haskey(by_category, category)
            by_category[category] = []
        end

        push!(by_category[category], result)
    end

    # Display each category
    for (category, items) in sort(collect(by_category))
        println(io, "")
        println(io, "─"^70)
        println(io, "CATEGORY: $category")
        println(io, "─"^70)

        for item in items
            println(io, "")
            println(io, "  $(item[:name])")

            if item[:sensitive]
                println(io, "    ⚠️  SENSITIVE DATA (filtered)")
            end

            println(io, "    Collected: $(item[:timestamp])")

            # Display data summary (not full dump for brevity)
            data_keys = collect(keys(item[:data]))
            if !isempty(data_keys)
                println(io, "    Data fields: $(join(data_keys, ", "))")
            end
        end
    end

    println(io, "")
    println(io, "="^70)
    println(io, "End of diagnostics report")
    println(io, "="^70)
    println(io, "")

    return String(take!(io))
end

"""
    export_diagnostics_report(results::Dict, filepath::String; format::Symbol=:json)

    Export diagnostics to file
    Requires FILE_WRITE consent

    Formats: :json, :markdown, :text
"""
function export_diagnostics_report(results::Dict, filepath::String;
                                   format::Symbol=:json)

    # Check consent
    if !Security.has_consent(Security.FILE_WRITE)
        granted = Security.request_consent(
            Security.FILE_WRITE,
            "Export diagnostics report to $filepath"
        )

        if !granted
            @warn "File write consent denied - cannot export"
            return false
        end
    end

    try
        if format == :json
            # Export as JSON
            write(filepath, JSON3.write(results, allow_inf=true))

        elseif format == :markdown
            # Export as Markdown
            report = format_diagnostic_report(results)
            write(filepath, report)

        elseif format == :text
            # Export as plain text
            report = format_diagnostic_report(results)
            write(filepath, report)

        else
            error("Unknown format: $format")
        end

        @info "Diagnostics exported" path=filepath format=format

        return true

    catch e
        @error "Failed to export diagnostics" exception=e
        return false
    end
end

end # module DiagnosticsIntegration
