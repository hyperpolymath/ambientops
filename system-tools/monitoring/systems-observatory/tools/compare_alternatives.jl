#!/usr/bin/env julia

"""
    compare_alternatives.jl - FOSS Alternatives Comparison Tool

    Side-by-side comparison of FOSS alternatives for any proprietary app,
    helping users make informed migration decisions.

    Usage: julia --project=. tools/compare_alternatives.jl [app_name]
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using JSON3
using Printf

function load_app_database()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    return JSON3.read(read(app_db_path, String))
end

function find_app(apps, query::String)
    query_lower = lowercase(query)
    matches = []

    for app in apps
        app_name_lower = lowercase(app[:proprietary_name])
        if occursin(query_lower, app_name_lower) || app_name_lower == query_lower
            push!(matches, app)
        end
    end

    return matches
end

function print_comparison_header(app)
    println("\n" * "="^80)
    println("COMPARISON: $(app[:proprietary_name]) vs FOSS Alternatives")
    println("="^80)
    println()
    println("Proprietary Application: $(app[:proprietary_name])")
    println("Description: $(app[:description])")
    println("Category: $(uppercase(app[:category]))")
    println("Annual Cost: \$$(app[:cost_savings])")
    println()
end

function print_alternatives_table(app)
    alternatives = app[:foss_alternatives]

    println("─"^80)
    println(@sprintf("%-30s │ %s", "FOSS Alternative", "Notes"))
    println("─"^80)

    for (i, alt) in enumerate(alternatives)
        println(@sprintf("%-30s │ Free & Open Source", alt))
    end

    println("─"^80)
    println()
end

function print_feature_comparison(app)
    println("FEATURE PARITY ANALYSIS")
    println("─"^80)

    parity = app[:feature_parity] * 100
    bar_width = 50
    filled = Int(round(parity / 100 * bar_width))
    empty = bar_width - filled

    println(@sprintf("Overall Feature Parity: %.1f%%", parity))
    println("[" * "█"^filled * "░"^empty * "]")
    println()

    if parity >= 95
        println("Assessment: EXCELLENT - FOSS alternatives match or exceed proprietary features")
    elseif parity >= 85
        println("Assessment: GOOD - FOSS alternatives cover most essential features")
    elseif parity >= 70
        println("Assessment: ACCEPTABLE - FOSS alternatives adequate for most use cases")
    elseif parity >= 50
        println("Assessment: LIMITED - Some feature gaps, evaluate carefully")
    else
        println("Assessment: SIGNIFICANT GAPS - Consider if limitations are acceptable")
    end
    println()
end

function print_privacy_analysis(app)
    println("PRIVACY & SECURITY BENEFITS")
    println("─"^80)

    benefit = app[:privacy_benefit]
    benefit_descriptions = Dict(
        "critical" => "CRITICAL - Major privacy improvements (tracking, data collection, surveillance)",
        "high" => "HIGH - Significant privacy benefits (telemetry, analytics reduced)",
        "medium" => "MEDIUM - Moderate privacy improvements",
        "low" => "LOW - Minor privacy differences"
    )

    println("Privacy Benefit Level: $(uppercase(benefit))")
    println(get(benefit_descriptions, benefit, "Unknown"))
    println()

    if benefit in ["critical", "high"]
        println("✓ No telemetry or tracking")
        println("✓ No data collection for advertising")
        println("✓ Source code publicly auditable")
        println("✓ Community-driven development")
        println("✓ No vendor lock-in")
    end
    println()
end

function print_migration_analysis(app)
    println("MIGRATION ASSESSMENT")
    println("─"^80)

    effort = app[:migration_effort]
    learning = app[:learning_curve]
    maturity = app[:maturity]

    println(@sprintf("Migration Effort:     %-10s", uppercase(effort)))
    println(@sprintf("Learning Curve:       %-10s", uppercase(learning)))
    println(@sprintf("Software Maturity:    %-10s", uppercase(maturity)))
    println()

    # Detailed guidance
    if effort == "low" && learning == "easy"
        println("✓ EASY MIGRATION - Recommended for quick transition")
        println("  • Similar interface and workflow")
        println("  • Minimal training required")
        println("  • Can migrate within days")
    elseif effort == "medium" || learning == "medium"
        println("⚠ MODERATE MIGRATION - Requires planning")
        println("  • Some interface differences")
        println("  • 1-2 weeks learning period")
        println("  • Backup data before switching")
        println("  • Consider running both in parallel")
    else
        println("⚠ COMPLEX MIGRATION - Careful planning required")
        println("  • Significant workflow changes")
        println("  • Training recommended")
        println("  • Gradual migration advised")
        println("  • Consider professional assistance")
    end
    println()
end

function print_cost_analysis(app)
    println("COST-BENEFIT ANALYSIS")
    println("─"^80)

    savings = app[:cost_savings]

    if savings > 0
        println(@sprintf("Annual Savings:        \$%.2f", savings))
        println(@sprintf("5-Year Savings:        \$%.2f", savings * 5))
        println(@sprintf("10-Year Savings:       \$%.2f", savings * 10))
        println()

        # ROI calculation
        migration_hours = if app[:migration_effort] == "low"
            5
        elseif app[:migration_effort] == "medium"
            20
        else
            40
        end

        assumed_hourly_rate = 50.0
        migration_cost = migration_hours * assumed_hourly_rate

        println(@sprintf("Estimated Migration Time:  %d hours", migration_hours))
        println(@sprintf("Migration Cost (@ \$50/hr): \$%.2f", migration_cost))
        println(@sprintf("Break-even Period:         %.1f months", migration_cost / (savings / 12)))
        println()

        if savings > migration_cost
            roi = ((savings - migration_cost) / migration_cost) * 100
            println(@sprintf("First Year ROI:            %.0f%%", roi))
        end
    else
        println("Annual Savings:        \$0.00 (proprietary app is free)")
        println()
        println("Benefits beyond cost:")
        println("  • Privacy protection")
        println("  • No vendor lock-in")
        println("  • Community support")
        println("  • Customization freedom")
    end
    println()
end

function print_platform_support(app)
    println("PLATFORM SUPPORT")
    println("─"^80)

    platforms = app[:platforms]
    println("Supported Platforms: $(join(platforms, ", "))")
    println()

    if "Linux" in platforms
        println("✓ Linux support (often better FOSS integration)")
    end
    if "macOS" in platforms
        println("✓ macOS support")
    end
    if "Windows" in platforms
        println("✓ Windows support")
    end
    println()
end

function print_recommendations(app)
    println("RECOMMENDATIONS")
    println("─"^80)

    score = calculate_recommendation_score(app)

    if score >= 0.80
        println("★★★★★ HIGHLY RECOMMENDED")
        println()
        println("This is an excellent candidate for migration:")
        println("  • Strong feature parity")
        println("  • Easy migration")
        println("  • Significant benefits")
        println()
        println("Action: Start migration planning immediately")
    elseif score >= 0.65
        println("★★★★☆ RECOMMENDED")
        println()
        println("Good migration candidate with minor trade-offs:")
        println("  • Acceptable feature coverage")
        println("  • Moderate migration effort")
        println("  • Clear benefits")
        println()
        println("Action: Evaluate alternatives, plan migration")
    elseif score >= 0.50
        println("★★★☆☆ CONSIDER")
        println()
        println("Viable option but requires careful evaluation:")
        println("  • Some feature gaps")
        println("  • May require workflow changes")
        println("  • Benefits still worthwhile")
        println()
        println("Action: Test alternatives thoroughly before committing")
    else
        println("★★☆☆☆ EVALUATE CAREFULLY")
        println()
        println("Migration may be challenging:")
        println("  • Significant feature gaps or")
        println("  • High migration complexity")
        println()
        println("Action: Carefully assess if limitations are acceptable")
    end

    println()
end

function calculate_recommendation_score(app)
    privacy_score = Dict("low" => 0.25, "medium" => 0.5, "high" => 0.75, "critical" => 1.0)
    ease_score = Dict("low" => 1.0, "medium" => 0.6, "high" => 0.3)
    learning_score = Dict("easy" => 1.0, "medium" => 0.7, "high" => 0.4)
    maturity_score = Dict("mature" => 1.0, "stable" => 0.8, "developing" => 0.5)

    privacy = get(privacy_score, app[:privacy_benefit], 0.5)
    ease = get(ease_score, app[:migration_effort], 0.5)
    learning = get(learning_score, app[:learning_curve], 0.5)
    maturity = get(maturity_score, app[:maturity], 0.7)
    features = app[:feature_parity]

    # Weighted score
    return 0.25 * features + 0.25 * privacy + 0.20 * ease + 0.15 * learning + 0.15 * maturity
end

function print_next_steps(app)
    println("NEXT STEPS")
    println("─"^80)
    println()
    println("1. Research Alternatives:")

    for (i, alt) in enumerate(app[:foss_alternatives])
        println("   • $alt - Search online for documentation and reviews")
    end

    println()
    println("2. Test Before Switching:")
    println("   • Download and install FOSS alternative")
    println("   • Test with non-critical data first")
    println("   • Verify feature compatibility")
    println()

    println("3. Plan Migration:")
    println("   • Export data from $(app[:proprietary_name])")
    println("   • Backup all important files")
    println("   • Document custom settings/workflows")
    println()

    println("4. Execute Migration:")
    println("   • Import data into FOSS alternative")
    println("   • Run both apps in parallel initially")
    println("   • Gradually shift workflow")
    println()

    println("5. Finalize:")
    println("   • Verify all data migrated correctly")
    println("   • Cancel $(app[:proprietary_name]) subscription")
    println("   • Uninstall proprietary software")
    println()
end

function interactive_mode(apps)
    println("\n" * "="^80)
    println("FOSS ALTERNATIVES COMPARISON TOOL")
    println("="^80)
    println()
    println("Compare proprietary applications with their FOSS alternatives")
    println()

    while true
        println("Enter application name to compare (or 'list' to see all, 'quit' to exit):")
        print("> ")

        input = strip(readline())

        if lowercase(input) in ["quit", "exit", "q"]
            break
        elseif lowercase(input) == "list"
            list_all_apps(apps)
            continue
        end

        if isempty(input)
            continue
        end

        matches = find_app(apps, input)

        if isempty(matches)
            println("\n⚠ No applications found matching '$input'")
            println("Tip: Try partial names like 'photo' instead of 'Photoshop'")
            println()
            continue
        elseif length(matches) > 1
            println("\nMultiple matches found:")
            for (i, app) in enumerate(matches)
                println("  $i. $(app[:proprietary_name])")
            end
            print("\nSelect number: ")
            idx = parse(Int, strip(readline()))
            if 1 <= idx <= length(matches)
                compare_app(matches[idx])
            end
        else
            compare_app(matches[1])
        end
    end

    println("\nThank you for using Juisys!")
end

function list_all_apps(apps)
    println("\n" * "─"^80)
    println("AVAILABLE APPLICATIONS ($(length(apps)) total)")
    println("─"^80)

    by_category = Dict{String, Vector}()
    for app in apps
        cat = app[:category]
        if !haskey(by_category, cat)
            by_category[cat] = []
        end
        push!(by_category[cat], app)
    end

    for (cat, cat_apps) in sort(collect(by_category), by=x->x[1])
        println("\n$(uppercase(cat)):")
        for app in sort(cat_apps, by=x->x[:proprietary_name])
            println("  • $(app[:proprietary_name])")
        end
    end
    println()
end

function compare_app(app)
    print_comparison_header(app)
    print_alternatives_table(app)
    print_feature_comparison(app)
    print_privacy_analysis(app)
    print_migration_analysis(app)
    print_cost_analysis(app)
    print_platform_support(app)
    print_recommendations(app)
    print_next_steps(app)

    println("="^80)
    println()
end

function main()
    apps = load_app_database()

    if length(ARGS) > 0
        # Command-line mode
        query = join(ARGS, " ")
        matches = find_app(apps, query)

        if isempty(matches)
            println("No applications found matching '$query'")
            println("Try: julia $PROGRAM_FILE  (for interactive mode)")
            return
        end

        compare_app(matches[1])
    else
        # Interactive mode
        interactive_mode(apps)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
