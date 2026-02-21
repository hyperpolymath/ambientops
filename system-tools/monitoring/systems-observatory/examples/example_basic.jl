#!/usr/bin/env julia

"""
    example_basic.jl - Basic Juisys Usage Example

    Demonstrates:
    - Loading app database
    - Classifying an application
    - Finding alternatives
    - Generating a simple report

    Usage: julia --project=. examples/example_basic.jl
"""

# Add parent directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Load Juisys modules
include("../src/core.jl")
include("../src/alternatives.jl")
include("../src/io.jl")

using .Core
using .Alternatives
using .IO

function main()
    println("="^70)
    println("JUISYS BASIC EXAMPLE")
    println("="^70)
    println()

    # Load rules
    println("Loading classification rules...")
    rules = Core.load_rules("data/rules.json")
    println("✓ Rules loaded")
    println()

    # Classify an application
    println("Classifying Adobe Photoshop...")

    metadata = Dict{String, Any}(
        "version" => "2024",
        "publisher" => "Adobe",
        "is_foss" => false,
        "cost" => 239.88,
        "description" => "telemetry third party data sharing"
    )

    result = Core.classify_app("Adobe Photoshop", rules; metadata=metadata)

    println("  Risk Level: $(result.risk_level)")
    println("  Privacy Score: $(round(result.privacy_score * 100, digits=1))%")
    println("  Cost Score: \$$(result.app.cost)")
    println()

    # Find alternatives
    println("Finding FOSS alternatives...")
    alternatives = Alternatives.find_alternatives("Adobe Photoshop", "data/app_db.json")

    if !isempty(alternatives)
        println("  Found $(length(alternatives)) alternative(s):")
        for alt in alternatives
            println("    - $(alt.name)")
            println("      Feature Parity: $(round(alt.feature_parity * 100, digits=1))%")
            println("      Annual Savings: \$$(round(alt.cost_savings_annual, digits=2))")
        end
    else
        println("  No alternatives found in database")
    end

    println()
    println("="^70)
    println("Example complete!")
    println()
    println("Try modifying this script to:")
    println("- Classify different applications")
    println("- Add new alternatives to data/app_db.json")
    println("- Generate reports using Reports module")
    println("="^70)
end

# Run main function
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
