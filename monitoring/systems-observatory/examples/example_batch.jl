#!/usr/bin/env julia

"""
    example_batch.jl - Batch Processing Example

    Demonstrates:
    - Processing multiple applications
    - Generating summary statistics
    - Creating batch reports

    Usage: julia --project=. examples/example_batch.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

include("../src/core.jl")
include("../src/alternatives.jl")
include("../src/reports.jl")

using .Core
using .Alternatives
using .Reports

function main()
    println("\n" * "="^70)
    println("JUISYS BATCH PROCESSING EXAMPLE")
    println("="^70)
    println()

    # Load rules
    rules = Core.load_rules("data/rules.json")

    # Sample applications to audit
    apps_to_audit = [
        ("Adobe Photoshop", Dict("cost" => 239.88, "is_foss" => false, "description" => "telemetry")),
        ("Microsoft Office", Dict("cost" => 149.99, "is_foss" => false, "description" => "telemetry requires login")),
        ("Slack", Dict("cost" => 96.00, "is_foss" => false, "description" => "third party data sharing")),
        ("GIMP", Dict("cost" => 0.0, "is_foss" => true, "description" => "")),
        ("LibreOffice", Dict("cost" => 0.0, "is_foss" => true, "description" => ""))
    ]

    results = []

    println("Processing $(length(apps_to_audit)) applications...\n")

    for (app_name, metadata) in apps_to_audit
        result = Core.classify_app(app_name, rules; metadata=metadata)

        # Format for reports module
        result_dict = Dict(
            :app_name => app_name,
            :category => string(result.app.category),
            :risk_level => string(result.risk_level),
            :privacy_score => result.privacy_score,
            :cost => result.app.cost,
            :alternatives => result.alternatives,
            :recommendations => result.recommendations,
            :has_telemetry => result.app.has_telemetry,
            :collects_pii => result.app.collects_pii
        )

        push!(results, result_dict)

        # Display progress
        risk_symbol = if result.risk_level in [Core.HIGH, Core.CRITICAL]
            "🔴"
        elseif result.risk_level == Core.MEDIUM
            "🟡"
        else
            "🟢"
        end

        println("$risk_symbol $app_name - $(result.risk_level)")
    end

    # Generate summary
    println("\n" * "="^70)
    println("SUMMARY")
    println("="^70)

    stats = Reports.summary_stats(results)

    println("Total Applications: $(stats[:total_apps])")
    println("High Risk: $(stats[:high_risk])")
    println("Medium Risk: $(stats[:medium_risk])")
    println("Low Risk: $(stats[:low_risk])")
    println("No Risk: $(stats[:no_risk])")
    println()
    println("Total Current Cost: \$$(round(stats[:total_cost], digits=2))")
    println("Potential Savings: \$$(round(stats[:potential_savings], digits=2))")
    println("="^70)

    println("\nBatch processing complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
