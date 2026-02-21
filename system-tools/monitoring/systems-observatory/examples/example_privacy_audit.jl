#!/usr/bin/env julia

"""
    example_privacy_audit.jl - Privacy Self-Audit Example

    Demonstrates:
    - Running privacy compliance checks
    - Generating compliance reports
    - Verifying GDPR adherence

    Usage: julia --project=. examples/example_privacy_audit.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

include("../src/security.jl")

using .Security

function main()
    println("\n" * "="^70)
    println("JUISYS PRIVACY SELF-AUDIT EXAMPLE")
    println("="^70)
    println()

    println("This example demonstrates Juisys's unique transparency feature:")
    println("The tool audits its own code for privacy compliance!")
    println()

    println("Running self-audit checks...")
    println()

    # Run self-audit
    checks = Security.self_audit()

    # Display results
    for check in checks
        symbol = check.passed ? "✓" : "✗"
        severity_color = if check.severity == :critical
            "\e[31m"  # Red
        elseif check.severity == :error
            "\e[33m"  # Yellow
        else
            "\e[32m"  # Green
        end
        reset = "\e[0m"

        println("$severity_color$symbol $(check.check_name)$reset")
        println("  $(check.details)")
        println("  Severity: $(check.severity)")
        println()
    end

    # Generate full report
    println("="^70)
    println("Generating full privacy compliance report...")
    println("="^70)

    report = Security.get_privacy_report()
    println(report)

    # Validate compliance
    is_compliant = Security.validate_compliance()

    if is_compliant
        println("\n✓ Juisys is GDPR COMPLIANT")
        println("All critical privacy checks passed!")
    else
        println("\n✗ WARNING: Privacy compliance issues detected!")
        println("Review failed checks above before using in production.")
    end

    println("\n" * "="^70)
    println("Privacy audit complete!")
    println()
    println("Key Takeaway:")
    println("This self-audit capability demonstrates transparency.")
    println("Users can verify privacy claims by running this check.")
    println("Consider implementing similar features in your own software!")
    println("="^70)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
