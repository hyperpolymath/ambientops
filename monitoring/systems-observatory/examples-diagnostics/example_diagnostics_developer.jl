#!/usr/bin/env julia

"""
    example_diagnostics_developer.jl - Developer Tools Detection Example

    Demonstrates:
    - Deep level diagnostics
    - Development environment analysis
    - Tool version detection

    Usage: julia --project=. examples-diagnostics/example_diagnostics_developer.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

include("../src/diagnostics_integration.jl")

using .DiagnosticsIntegration
using JSON3

function main()
    println("\n" * "="^70)
    println("DEVELOPER ENVIRONMENT DIAGNOSTICS")
    println("="^70)
    println()

    # Enable deep diagnostics
    if !enable_diagnostics(DEEP)
        println("ERROR: Could not enable diagnostics")
        return
    end

    println("✓ Diagnostics enabled (DEEP level)")
    println()

    try
        diag = SystemDiagnostics(DEEP)

        # Auto-request consent
        if !request_consent(diag)
            println("Consent denied")
            return
        end

        println()
        println("Analyzing development environment...")
        println()

        # Run diagnostics
        results = run_diagnostics(diag)

        # Extract developer-specific information
        println("="^70)
        println("DEVELOPMENT TOOLS DETECTED")
        println("="^70)
        println()

        for result in results[:results]
            if result[:name] == "development_tools" ||
               result[:category] == "SOFTWARE"

                data = result[:data]

                # Compilers
                if haskey(data, :compilers)
                    println("COMPILERS:")
                    for compiler in data[:compilers]
                        println("  • $(compiler[:name]): $(compiler[:version_info])")
                    end
                    println()
                end

                # Interpreters
                if haskey(data, :interpreters)
                    println("INTERPRETERS:")
                    for interp in data[:interpreters]
                        println("  • $(interp[:name]): $(interp[:version_info])")
                    end
                    println()
                end

                # Build tools
                if haskey(data, :build_tools)
                    println("BUILD TOOLS:")
                    for tool in data[:build_tools]
                        println("  • $(tool[:name]): $(tool[:version_info])")
                    end
                    println()
                end

                # Version control
                if haskey(data, :version_control)
                    println("VERSION CONTROL:")
                    for vc in data[:version_control]
                        println("  • $(vc[:name]): $(vc[:version_info])")
                        if haskey(vc, :configured_user)
                            println("    User: $(vc[:configured_user])")
                        end
                    end
                    println()
                end

                # Editors
                if haskey(data, :editors)
                    println("EDITORS/IDEs:")
                    for editor in data[:editors]
                        println("  • $(editor[:name])")
                    end
                    println()
                end

                # Containers
                if haskey(data, :containers)
                    println("CONTAINER TOOLS:")
                    for (key, value) in pairs(data[:containers])
                        println("  • $key: $value")
                    end
                    println()
                end
            end
        end

        println("="^70)

        # Export full results
        export_path = "developer_diagnostics_" * string(now()) * ".json"
        export_diagnostics_report(results, export_path, format=:json)

        println()
        println("✓ Full diagnostics exported to: $export_path")
        println()

        # Cleanup
        clear_diagnostics_data(diag)

    catch e
        println("ERROR: ", e)
        showerror(stdout, e, catch_backtrace())
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
