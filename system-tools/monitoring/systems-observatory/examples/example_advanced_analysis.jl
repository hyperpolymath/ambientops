#!/usr/bin/env julia

"""
    example_advanced_analysis.jl - Advanced App Analysis Example

    Demonstrates:
    - Multi-criteria app analysis
    - Custom scoring algorithms
    - Migration path generation
    - Cost-benefit analysis
    - Risk assessment

    Usage: julia --project=. examples/example_advanced_analysis.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using JSON3
using Printf

struct MigrationScore
    app_name::String
    foss_alternative::String
    overall_score::Float64
    cost_benefit::Float64
    privacy_gain::Float64
    feature_adequacy::Float64
    ease_of_migration::Float64
    maturity_factor::Float64
    recommendation::String
end

function load_app_database()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    return JSON3.read(read(app_db_path, String))
end

function calculate_privacy_score(privacy_benefit::String)
    scores = Dict(
        "low" => 0.25,
        "medium" => 0.50,
        "high" => 0.75,
        "critical" => 1.00
    )
    return get(scores, privacy_benefit, 0.0)
end

function calculate_migration_ease(effort::String, learning_curve::String)
    effort_scores = Dict("low" => 1.0, "medium" => 0.6, "high" => 0.3)
    learning_scores = Dict("easy" => 1.0, "medium" => 0.7, "high" => 0.4)

    effort_score = get(effort_scores, effort, 0.5)
    learning_score = get(learning_scores, learning_curve, 0.5)

    return (effort_score + learning_score) / 2.0
end

function calculate_maturity_score(maturity::String)
    scores = Dict(
        "mature" => 1.0,
        "stable" => 0.8,
        "developing" => 0.5
    )
    return get(scores, maturity, 0.5)
end

function calculate_cost_benefit_score(cost_savings::Float64)
    # Normalize to 0-1 scale, with diminishing returns
    if cost_savings == 0.0
        return 0.3  # Free apps still have value (privacy/control)
    elseif cost_savings < 50.0
        return 0.4 + (cost_savings / 50.0) * 0.2
    elseif cost_savings < 200.0
        return 0.6 + ((cost_savings - 50.0) / 150.0) * 0.3
    else
        return 0.9 + min((cost_savings - 200.0) / 1000.0, 0.1)
    end
end

function analyze_migration(app)
    privacy_score = calculate_privacy_score(app[:privacy_benefit])
    feature_score = app[:feature_parity]
    migration_ease = calculate_migration_ease(app[:migration_effort], app[:learning_curve])
    maturity_score = calculate_maturity_score(app[:maturity])
    cost_benefit = calculate_cost_benefit_score(app[:cost_savings])

    # Weighted overall score
    weights = Dict(
        :privacy => 0.30,
        :features => 0.25,
        :ease => 0.20,
        :maturity => 0.15,
        :cost => 0.10
    )

    overall_score = (
        privacy_score * weights[:privacy] +
        feature_score * weights[:features] +
        migration_ease * weights[:ease] +
        maturity_score * weights[:maturity] +
        cost_benefit * weights[:cost]
    )

    # Generate recommendation
    recommendation = if overall_score >= 0.80
        "HIGHLY RECOMMENDED - Excellent alternative"
    elseif overall_score >= 0.65
        "RECOMMENDED - Good alternative"
    elseif overall_score >= 0.50
        "CONSIDER - Viable with trade-offs"
    elseif overall_score >= 0.35
        "EVALUATE CAREFULLY - Significant limitations"
    else
        "NOT RECOMMENDED - Major drawbacks"
    end

    # Get first FOSS alternative for display
    foss_alt = isempty(app[:foss_alternatives]) ? "None" : app[:foss_alternatives][1]

    return MigrationScore(
        app[:proprietary_name],
        foss_alt,
        overall_score,
        cost_benefit,
        privacy_score,
        feature_score,
        migration_ease,
        maturity_score,
        recommendation
    )
end

function print_migration_score(score::MigrationScore)
    println("\n" * "="^70)
    println("$(score.app_name) → $(score.foss_alternative)")
    println("="^70)

    overall_pct = score.overall_score * 100
    println(@sprintf("OVERALL SCORE: %.1f%% - %s", overall_pct, score.recommendation))
    println()
    println("Score Breakdown:")
    println(@sprintf("  Privacy Gain:      %.1f%%  %s", score.privacy_gain * 100, progress_bar(score.privacy_gain)))
    println(@sprintf("  Feature Adequacy:  %.1f%%  %s", score.feature_adequacy * 100, progress_bar(score.feature_adequacy)))
    println(@sprintf("  Migration Ease:    %.1f%%  %s", score.ease_of_migration * 100, progress_bar(score.ease_of_migration)))
    println(@sprintf("  Maturity Factor:   %.1f%%  %s", score.maturity_factor * 100, progress_bar(score.maturity_factor)))
    println(@sprintf("  Cost Benefit:      %.1f%%  %s", score.cost_benefit * 100, progress_bar(score.cost_benefit)))
end

function progress_bar(score::Float64, width::Int=30)
    filled = Int(round(score * width))
    empty = width - filled
    return "[" * "█"^filled * "░"^empty * "]"
end

function analyze_portfolio(apps)
    println("\n" * "="^70)
    println("PORTFOLIO ANALYSIS")
    println("="^70)

    total_cost = sum([app[:cost_savings] for app in apps])
    weighted_parity = sum([app[:cost_savings] * app[:feature_parity] for app in apps]) / max(total_cost, 1.0)

    println("\nCurrent Portfolio:")
    println(@sprintf("  Total Annual Cost:        \$%.2f", total_cost))
    println(@sprintf("  Weighted Feature Parity:  %.1f%%", weighted_parity * 100))

    # Calculate migration scenarios
    println("\nMigration Scenarios:")

    # Scenario 1: Easy wins only
    easy_wins = filter(app -> app[:migration_effort] == "low" &&
                              app[:feature_parity] >= 0.85, apps)
    easy_savings = sum([app[:cost_savings] for app in easy_wins])
    println(@sprintf("\n  1. QUICK WINS (low effort, high parity):"))
    println(@sprintf("     Apps to migrate: %d", length(easy_wins)))
    println(@sprintf("     Potential savings: \$%.2f/year", easy_savings))
    println(@sprintf("     Effort level: LOW"))

    # Scenario 2: High ROI migrations
    high_roi = filter(app -> app[:cost_savings] > 100.0, apps)
    high_roi_savings = sum([app[:cost_savings] for app in high_roi])
    println(@sprintf("\n  2. HIGH ROI (costly proprietary apps):"))
    println(@sprintf("     Apps to migrate: %d", length(high_roi)))
    println(@sprintf("     Potential savings: \$%.2f/year", high_roi_savings))
    println(@sprintf("     Effort level: MIXED"))

    # Scenario 3: Privacy-focused
    privacy_critical = filter(app -> app[:privacy_benefit] in ["critical", "high"], apps)
    privacy_savings = sum([app[:cost_savings] for app in privacy_critical])
    println(@sprintf("\n  3. PRIVACY FIRST (critical/high privacy):"))
    println(@sprintf("     Apps to migrate: %d", length(privacy_critical)))
    println(@sprintf("     Potential savings: \$%.2f/year", privacy_savings))
    println(@sprintf("     Privacy improvement: SIGNIFICANT"))

    # Scenario 4: Complete migration
    println(@sprintf("\n  4. COMPLETE MIGRATION (all apps):"))
    println(@sprintf("     Apps to migrate: %d", length(apps)))
    println(@sprintf("     Potential savings: \$%.2f/year", total_cost))
    println(@sprintf("     Effort level: HIGH"))
end

function generate_migration_plan(apps, strategy::String="balanced")
    println("\n" * "="^70)
    println("MIGRATION PLAN: $(uppercase(strategy))")
    println("="^70)

    scores = [analyze_migration(app) for app in apps]

    # Sort based on strategy
    if strategy == "quick_wins"
        sorted_scores = sort(scores, by=x->(x.ease_of_migration, x.overall_score), rev=true)
    elseif strategy == "privacy"
        sorted_scores = sort(scores, by=x->(x.privacy_gain, x.overall_score), rev=true)
    elseif strategy == "cost"
        sorted_scores = sort(scores, by=x->(x.cost_benefit, x.overall_score), rev=true)
    else  # balanced
        sorted_scores = sort(scores, by=x->x.overall_score, rev=true)
    end

    # Phased approach
    phases = [
        ("PHASE 1: Immediate (1-2 months)", sorted_scores[1:min(5, length(sorted_scores))]),
        ("PHASE 2: Short-term (3-6 months)", sorted_scores[6:min(15, length(sorted_scores))]),
        ("PHASE 3: Long-term (6-12 months)", sorted_scores[16:min(length(sorted_scores), length(sorted_scores))])
    ]

    for (phase_name, phase_apps) in phases
        if isempty(phase_apps)
            continue
        end

        println("\n$phase_name")
        println("─"^70)

        for (i, score) in enumerate(phase_apps)
            println(@sprintf("  %2d. %-25s → %-20s [%.1f%%]",
                           i,
                           score.app_name,
                           score.foss_alternative,
                           score.overall_score * 100))
        end
    end
end

function main()
    println("\n" * "="^70)
    println("ADVANCED APP MIGRATION ANALYSIS")
    println("="^70)

    apps = load_app_database()
    println("\nLoaded $(length(apps)) applications for analysis")

    # Analyze a few specific high-value apps in detail
    println("\n" * "="^70)
    println("DETAILED ANALYSIS - TOP CANDIDATES")
    println("="^70)

    # Get high-cost apps for detailed analysis
    high_value = filter(app -> app[:cost_savings] > 100.0, apps)
    high_value_sorted = sort(high_value, by=x->x[:cost_savings], rev=true)

    for app in high_value_sorted[1:min(3, length(high_value_sorted))]
        score = analyze_migration(app)
        print_migration_score(score)
    end

    # Portfolio analysis
    analyze_portfolio(apps)

    # Generate migration plans with different strategies
    println("\n")
    generate_migration_plan(apps, "balanced")

    println("\n\n" * "="^70)
    println("Alternative Strategies:")
    println("  • julia $PROGRAM_FILE quick_wins   # Fastest results")
    println("  • julia $PROGRAM_FILE privacy      # Maximum privacy gain")
    println("  • julia $PROGRAM_FILE cost         # Maximum cost savings")
    println("="^70 * "\n")
end

if abspath(PROGRAM_FILE) == @__FILE__
    strategy = length(ARGS) > 0 ? ARGS[1] : "balanced"

    if strategy in ["quick_wins", "privacy", "cost", "balanced"]
        apps = load_app_database()
        generate_migration_plan(apps, strategy)
    else
        main()
    end
end
