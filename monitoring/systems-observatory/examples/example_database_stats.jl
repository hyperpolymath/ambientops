#!/usr/bin/env julia

"""
    example_database_stats.jl - Database Statistics Generator

    Demonstrates:
    - Loading and analyzing the app database
    - Generating comprehensive statistics
    - Cost savings analysis
    - Privacy benefit analysis
    - Feature parity analysis

    Usage: julia --project=. examples/example_database_stats.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using JSON3
using Dates
using Printf

function load_databases()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")

    apps = JSON3.read(read(app_db_path, String))
    rules = JSON3.read(read(rules_db_path, String))

    return apps, rules
end

function print_header(title)
    println("\n" * "="^70)
    println(title)
    println("="^70 * "\n")
end

function print_section(title)
    println("\n" * "─"^70)
    println(title)
    println("─"^70)
end

function analyze_by_category(apps)
    print_section("Applications by Category")

    category_data = Dict{String, Vector}()

    for app in apps
        cat = app[:category]
        if !haskey(category_data, cat)
            category_data[cat] = []
        end
        push!(category_data[cat], app)
    end

    # Sort by count descending
    sorted_cats = sort(collect(category_data), by=x->length(x[2]), rev=true)

    for (cat, cat_apps) in sorted_cats
        count = length(cat_apps)
        total_savings = sum([a[:cost_savings] for a in cat_apps])
        avg_parity = sum([a[:feature_parity] for a in cat_apps]) / count

        println(@sprintf("  %-15s: %2d apps | \$%8.2f savings | %.1f%% avg parity",
                        uppercase(cat), count, total_savings, avg_parity * 100))
    end

    return category_data
end

function analyze_cost_savings(apps)
    print_section("Cost Savings Analysis")

    total_savings = sum([app[:cost_savings] for app in apps])
    free_apps = count(app -> app[:cost_savings] == 0.0, apps)
    paid_apps = length(apps) - free_apps

    println("  Total annual savings potential: \$$(round(total_savings, digits=2))")
    println("  Average savings per app: \$$(round(total_savings / length(apps), digits=2))")
    println("  Free proprietary apps: $free_apps")
    println("  Paid proprietary apps: $paid_apps")
    println()

    # Top 10 most expensive to replace
    sorted_apps = sort(apps, by=x->x[:cost_savings], rev=true)
    println("  Top 10 Most Expensive Proprietary Apps:")
    for (i, app) in enumerate(sorted_apps[1:min(10, length(sorted_apps))])
        savings = app[:cost_savings]
        println(@sprintf("    %2d. %-30s \$%8.2f/year",
                        i, app[:proprietary_name], savings))
    end
end

function analyze_privacy_benefits(apps)
    print_section("Privacy Benefit Analysis")

    benefit_counts = Dict{String, Int}()
    for app in apps
        benefit = app[:privacy_benefit]
        benefit_counts[benefit] = get(benefit_counts, benefit, 0) + 1
    end

    total = length(apps)
    println("  Privacy Benefit Distribution:")
    for (level, count) in sort(collect(benefit_counts), by=x->x[2], rev=true)
        pct = count / total * 100
        bar = "█" ^ Int(round(pct / 2))
        println(@sprintf("    %-10s: %2d apps (%5.1f%%) %s",
                        uppercase(level), count, pct, bar))
    end

    # Critical privacy apps
    critical_apps = filter(app -> app[:privacy_benefit] == "critical", apps)
    if !isempty(critical_apps)
        println("\n  Apps with CRITICAL privacy benefits:")
        for app in critical_apps
            println("    • $(app[:proprietary_name]) → $(join(app[:foss_alternatives], ", "))")
        end
    end
end

function analyze_feature_parity(apps)
    print_section("Feature Parity Analysis")

    avg_parity = sum([app[:feature_parity] for app in apps]) / length(apps)
    min_parity = minimum([app[:feature_parity] for app in apps])
    max_parity = maximum([app[:feature_parity] for app in apps])

    println("  Average feature parity: $(round(avg_parity * 100, digits=1))%")
    println("  Minimum feature parity: $(round(min_parity * 100, digits=1))%")
    println("  Maximum feature parity: $(round(max_parity * 100, digits=1))%")
    println()

    # Distribution by threshold
    excellent = count(app -> app[:feature_parity] >= 0.95, apps)
    good = count(app -> 0.85 <= app[:feature_parity] < 0.95, apps)
    acceptable = count(app -> 0.70 <= app[:feature_parity] < 0.85, apps)
    limited = count(app -> app[:feature_parity] < 0.70, apps)

    println("  Feature Parity Distribution:")
    println(@sprintf("    Excellent (≥95%%):  %2d apps", excellent))
    println(@sprintf("    Good (85-95%%):     %2d apps", good))
    println(@sprintf("    Acceptable (70-85%%): %2d apps", acceptable))
    println(@sprintf("    Limited (<70%%):    %2d apps", limited))

    # Apps with lowest parity
    println("\n  Apps with lowest feature parity (may need attention):")
    sorted_by_parity = sort(apps, by=x->x[:feature_parity])
    for (i, app) in enumerate(sorted_by_parity[1:min(5, length(sorted_by_parity))])
        parity = app[:feature_parity] * 100
        println(@sprintf("    %d. %-30s %.1f%%", i, app[:proprietary_name], parity))
    end
end

function analyze_migration_effort(apps)
    print_section("Migration Effort Analysis")

    effort_counts = Dict{String, Int}()
    for app in apps
        effort = app[:migration_effort]
        effort_counts[effort] = get(effort_counts, effort, 0) + 1
    end

    total = length(apps)
    println("  Migration Effort Distribution:")
    for effort in ["low", "medium", "high"]
        count = get(effort_counts, effort, 0)
        pct = count / total * 100
        println(@sprintf("    %-10s: %2d apps (%5.1f%%)", uppercase(effort), count, pct))
    end

    # Easy migrations
    easy_migrations = filter(app -> app[:migration_effort] == "low" &&
                                   app[:feature_parity] >= 0.85, apps)
    if !isempty(easy_migrations)
        println("\n  Recommended Easy Migrations (low effort + good parity):")
        for app in easy_migrations
            parity = app[:feature_parity] * 100
            println(@sprintf("    • %-30s → %-20s (%.1f%% parity)",
                           app[:proprietary_name],
                           app[:foss_alternatives][1],
                           parity))
        end
    end
end

function analyze_maturity(apps)
    print_section("FOSS Maturity Analysis")

    maturity_counts = Dict{String, Int}()
    for app in apps
        maturity = app[:maturity]
        maturity_counts[maturity] = get(maturity_counts, maturity, 0) + 1
    end

    total = length(apps)
    println("  FOSS Alternative Maturity:")
    for maturity in ["mature", "stable", "developing"]
        count = get(maturity_counts, maturity, 0)
        pct = count / total * 100
        println(@sprintf("    %-12s: %2d apps (%5.1f%%)", uppercase(maturity), count, pct))
    end
end

function analyze_learning_curve(apps)
    print_section("Learning Curve Analysis")

    curve_counts = Dict{String, Int}()
    for app in apps
        curve = app[:learning_curve]
        curve_counts[curve] = get(curve_counts, curve, 0) + 1
    end

    total = length(apps)
    println("  Learning Curve Distribution:")
    for curve in ["easy", "medium", "high"]
        count = get(curve_counts, curve, 0)
        pct = count / total * 100
        println(@sprintf("    %-10s: %2d apps (%5.1f%%)", uppercase(curve), count, pct))
    end
end

function generate_recommendations(apps)
    print_section("Top Recommendations")

    # Best ROI: High savings + easy migration + good parity
    best_roi = filter(app -> app[:cost_savings] > 50.0 &&
                            app[:migration_effort] == "low" &&
                            app[:feature_parity] >= 0.85, apps)

    if !isempty(best_roi)
        sorted_roi = sort(best_roi, by=x->x[:cost_savings], rev=true)
        println("  Best ROI Migrations (High Savings + Easy + Good Parity):")
        for (i, app) in enumerate(sorted_roi[1:min(5, length(sorted_roi))])
            println(@sprintf("    %d. %-25s → %-20s (\$%.2f/year, %.1f%% parity)",
                           i,
                           app[:proprietary_name],
                           app[:foss_alternatives][1],
                           app[:cost_savings],
                           app[:feature_parity] * 100))
        end
    end

    # Privacy-first recommendations
    println("\n  Privacy-First Recommendations:")
    privacy_recs = filter(app -> app[:privacy_benefit] == "critical" &&
                                app[:feature_parity] >= 0.80, apps)
    sorted_privacy = sort(privacy_recs, by=x->x[:feature_parity], rev=true)
    for (i, app) in enumerate(sorted_privacy[1:min(5, length(sorted_privacy))])
        println(@sprintf("    %d. %-25s → %-20s (%.1f%% parity)",
                       i,
                       app[:proprietary_name],
                       app[:foss_alternatives][1],
                       app[:feature_parity] * 100))
    end
end

function export_statistics(apps, output_path)
    print_section("Exporting Statistics")

    stats = Dict(
        "generated_at" => string(now()),
        "total_apps" => length(apps),
        "total_savings" => sum([app[:cost_savings] for app in apps]),
        "average_parity" => sum([app[:feature_parity] for app in apps]) / length(apps),
        "categories" => Dict{String, Int}(),
        "privacy_benefits" => Dict{String, Int}(),
        "migration_efforts" => Dict{String, Int}(),
        "maturity_levels" => Dict{String, Int}()
    )

    # Count by category
    for app in apps
        cat = app[:category]
        stats["categories"][cat] = get(stats["categories"], cat, 0) + 1

        benefit = app[:privacy_benefit]
        stats["privacy_benefits"][benefit] = get(stats["privacy_benefits"], benefit, 0) + 1

        effort = app[:migration_effort]
        stats["migration_efforts"][effort] = get(stats["migration_efforts"], effort, 0) + 1

        maturity = app[:maturity]
        stats["maturity_levels"][maturity] = get(stats["maturity_levels"], maturity, 0) + 1
    end

    # Write to file
    open(output_path, "w") do f
        JSON3.write(f, stats)
    end

    println("  ✓ Statistics exported to: $output_path")
end

function main()
    print_header("JUISYS DATABASE STATISTICS")

    println("Generated: $(now())")
    println()

    # Load databases
    apps, rules = load_databases()
    println("Loaded $(length(apps)) applications")

    # Run analyses
    analyze_by_category(apps)
    analyze_cost_savings(apps)
    analyze_privacy_benefits(apps)
    analyze_feature_parity(apps)
    analyze_migration_effort(apps)
    analyze_maturity(apps)
    analyze_learning_curve(apps)
    generate_recommendations(apps)

    # Export statistics
    output_path = joinpath(@__DIR__, "..", "database_stats.json")
    export_statistics(apps, output_path)

    print_header("STATISTICS GENERATION COMPLETE")
    println("Database contains comprehensive information on:")
    println("  • $(length(apps)) proprietary applications")
    println("  • $(length(Set([alt for app in apps for alt in app[:foss_alternatives]]))) unique FOSS alternatives")
    println("  • \$$(round(sum([app[:cost_savings] for app in apps]), digits=2)) potential annual savings")
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
