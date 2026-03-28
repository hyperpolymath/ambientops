#!/usr/bin/env julia

"""
    example_diagnostics_basic.jl - Basic Diagnostics Example

    Demonstrates:
    - Enabling diagnostics add-on
    - Running basic diagnostics
    - Displaying results

    Usage: julia --project=. examples-diagnostics/example_diagnostics_basic.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

include("../src/diagnostics_integration.jl")

using .DiagnosticsIntegration

function main()
    println("\n" * "="^70)
    println("JUISYS DIAGNOSTICS ADD-ON - BASIC EXAMPLE")
    println("="^70)
    println()

    # Check if diagnostics library is available
    println("Step 1: Enable diagnostics add-on...")

    if !enable_diagnostics(BASIC)
        println("ERROR: Could not enable diagnostics")
        println()
        println("To build diagnostics library:")
        println("  cd src-diagnostics/d")
        println("  make release")
        println()
        return
    end

    println("✓ Diagnostics add-on enabled (BASIC level)")
    println()

    # Create diagnostics instance
    println("Step 2: Create diagnostics instance...")

    try
        diag = SystemDiagnostics(BASIC)
        println("✓ Diagnostics instance created")
        println()

        # Request consent
        println("Step 3: Request consent...")

        if !request_consent(diag)
            println("Consent denied - exiting")
            return
        end

        println()

        # Run diagnostics
        println("Step 4: Run diagnostics...")

        results = run_diagnostics(diag)

        if isnothing(results)
            println("ERROR: Diagnostics failed")
            return
        end

        println()

        # Display report
        println("Step 5: Display results...")
        println()

        report = format_diagnostic_report(results)
        println(report)

        # Optional: Export to file
        print("Export to file? [y/N]: ")
        response = lowercase(strip(readline()))

        if response in ["y", "yes"]
            print("Enter filename (e.g., diagnostics.json): ")
            filename = strip(readline())

            if !isempty(filename)
                success = export_diagnostics_report(results, filename, format=:json)

                if success
                    println("✓ Exported to: $filename")
                end
            end
        end

        # Clean up
        println()
        println("Step 6: Cleanup...")
        clear_diagnostics_data(diag)

        println()
        println("="^70)
        println("Example complete!")
        println()
        println("Try different diagnostic levels:")
        println("  BASIC     - Essential info only")
        println("  STANDARD  - Common developer diagnostics")
        println("  DEEP      - Comprehensive analysis")
        println("  FORENSIC  - Maximum detail")
        println("="^70)

    catch e
        println("ERROR: ", e)
        println()
        println("Make sure:")
        println("  1. Diagnostics library is built (cd src-diagnostics/d && make release)")
        println("  2. Library is in correct location")
        println("  3. D compiler is installed (brew install ldc)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
