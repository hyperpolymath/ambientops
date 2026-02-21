#!/usr/bin/env julia

"""
    migration_planner.jl - Interactive Migration Planning Tool

    Interactive tool to help users plan their migration from proprietary
    to FOSS software with personalized recommendations based on priorities.

    Usage: julia --project=. tools/migration_planner.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using JSON3
using Dates
using Printf

# Migration priority weights
mutable struct UserPriorities
    cost_savings::Float64
    privacy::Float64
    ease_of_migration::Float64
    feature_completeness::Float64
    time_investment::Float64
end

function print_welcome()
    println("\n" * "="^70)
    println("          JUISYS MIGRATION PLANNER")
    println("       Privacy-First FOSS Migration Assistant")
    println("="^70)
    println()
    println("This tool will help you create a personalized migration plan")
    println("from proprietary to FOSS (Free and Open Source) software.")
    println()
end

function gather_priorities()
    println("─"^70)
    println("STEP 1: Define Your Priorities")
    println("─"^70)
    println()
    println("Please rate the following factors (1-10):")
    println("  10 = Extremely important")
    println("  5  = Moderately important")
    println("  1  = Not important")
    println()

    cost = get_rating("Cost savings (lower subscription fees)", 7)
    privacy = get_rating("Privacy protection (less tracking/telemetry)", 8)
    ease = get_rating("Ease of migration (minimal learning curve)", 7)
    features = get_rating("Feature completeness (matches current tools)", 8)
    time = get_rating("Time investment (how quickly to migrate)", 6)

    # Normalize to 0-1 scale
    total = cost + privacy + ease + features + time
    return UserPriorities(
        cost / total,
        privacy / total,
        ease / total,
        features / total,
        time / total
    )
end

function get_rating(prompt::String, default::Int=5)
    while true
        print("  $prompt [$default]: ")
        input = strip(readline())

        if isempty(input)
            return Float64(default)
        end

        try
            rating = parse(Int, input)
            if 1 <= rating <= 10
                return Float64(rating)
            else
                println("    ⚠ Please enter a number between 1 and 10")
            end
        catch
            println("    ⚠ Please enter a valid number")
        end
    end
end

function load_app_database()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    return JSON3.read(read(app_db_path, String))
end

function calculate_app_score(app, priorities::UserPriorities)
    # Cost component (normalized)
    cost_score = if app[:cost_savings] == 0.0
        0.3  # Free apps still have value
    else
        min(1.0, app[:cost_savings] / 500.0)
    end

    # Privacy component
    privacy_scores = Dict(
        "low" => 0.25,
        "medium" => 0.50,
        "high" => 0.75,
        "critical" => 1.00
    )
    privacy_score = get(privacy_scores, app[:privacy_benefit], 0.5)

    # Ease component
    ease_scores = Dict(
        ("low", "easy") => 1.0,
        ("low", "medium") => 0.9,
        ("low", "high") => 0.8,
        ("medium", "easy") => 0.7,
        ("medium", "medium") => 0.6,
        ("medium", "high") => 0.5,
        ("high", "easy") => 0.4,
        ("high", "medium") => 0.3,
        ("high", "high") => 0.2
    )
    ease_score = get(ease_scores, (app[:migration_effort], app[:learning_curve]), 0.5)

    # Feature component
    feature_score = app[:feature_parity]

    # Time component (based on maturity and migration effort)
    maturity_scores = Dict("mature" => 1.0, "stable" => 0.8, "developing" => 0.5)
    maturity_score = get(maturity_scores, app[:maturity], 0.7)
    time_score = (ease_score + maturity_score) / 2.0

    # Weighted total
    total_score = (
        cost_score * priorities.cost_savings +
        privacy_score * priorities.privacy +
        ease_score * priorities.ease_of_migration +
        feature_score * priorities.feature_completeness +
        time_score * priorities.time_investment
    )

    return total_score
end

function select_apps_to_analyze(all_apps)
    println("\n" * "─"^70)
    println("STEP 2: Select Applications to Analyze")
    println("─"^70)
    println()
    println("Choose one of the following options:")
    println("  1. Analyze all applications in database")
    println("  2. Select by category")
    println("  3. Select specific applications")
    println("  4. Select high-cost applications (>$100/year)")
    println("  5. Select privacy-critical applications")
    println()

    while true
        print("Your choice [1-5]: ")
        choice = strip(readline())

        if choice == "1"
            return all_apps
        elseif choice == "2"
            return select_by_category(all_apps)
        elseif choice == "3"
            return select_specific_apps(all_apps)
        elseif choice == "4"
            return filter(app -> app[:cost_savings] > 100.0, all_apps)
        elseif choice == "5"
            return filter(app -> app[:privacy_benefit] in ["critical", "high"], all_apps)
        else
            println("  ⚠ Please enter a number between 1 and 5")
        end
    end
end

function select_by_category(all_apps)
    categories = unique([app[:category] for app in all_apps])
    sort!(categories)

    println("\nAvailable categories:")
    for (i, cat) in enumerate(categories)
        count = count(app -> app[:category] == cat, all_apps)
        println("  $i. $(uppercase(cat)) ($count apps)")
    end
    println()

    while true
        print("Select category number: ")
        input = strip(readline())

        try
            idx = parse(Int, input)
            if 1 <= idx <= length(categories)
                selected_cat = categories[idx]
                return filter(app -> app[:category] == selected_cat, all_apps)
            else
                println("  ⚠ Please enter a number between 1 and $(length(categories))")
            end
        catch
            println("  ⚠ Please enter a valid number")
        end
    end
end

function select_specific_apps(all_apps)
    println("\nEnter application names (comma-separated):")
    println("Example: Photoshop, Office, Zoom")
    print("> ")

    input = strip(readline())
    requested_names = [strip(s) for s in split(input, ",")]

    selected = []
    for req_name in requested_names
        req_lower = lowercase(req_name)
        for app in all_apps
            if occursin(req_lower, lowercase(app[:proprietary_name]))
                push!(selected, app)
                break
            end
        end
    end

    if isempty(selected)
        println("\n  ⚠ No matching applications found. Using all apps.")
        return all_apps
    end

    println("\n  ✓ Selected $(length(selected)) application(s)")
    return selected
end

function generate_migration_plan(apps, priorities::UserPriorities)
    println("\n" * "─"^70)
    println("STEP 3: Generating Personalized Migration Plan")
    println("─"^70)
    println()

    # Calculate scores
    scored_apps = [(app, calculate_app_score(app, priorities)) for app in apps]
    sort!(scored_apps, by=x->x[2], rev=true)

    # Determine phases
    phase1 = scored_apps[1:min(5, length(scored_apps))]
    phase2 = scored_apps[6:min(15, length(scored_apps))]
    phase3 = scored_apps[16:length(scored_apps)]

    total_savings = sum([app[:cost_savings] for (app, _) in scored_apps])
    total_apps = length(scored_apps)

    # Summary
    println("MIGRATION SUMMARY")
    println("─"^70)
    println(@sprintf("  Applications to migrate: %d", total_apps))
    println(@sprintf("  Potential annual savings: \$%.2f", total_savings))
    println(@sprintf("  Estimated timeline: %s", estimate_timeline(total_apps)))
    println()

    # Display priorities
    println("YOUR PRIORITIES:")
    println(@sprintf("  Cost Savings:         %.0f%%", priorities.cost_savings * 100))
    println(@sprintf("  Privacy:              %.0f%%", priorities.privacy * 100))
    println(@sprintf("  Ease of Migration:    %.0f%%", priorities.ease_of_migration * 100))
    println(@sprintf("  Feature Completeness: %.0f%%", priorities.feature_completeness * 100))
    println(@sprintf("  Time Investment:      %.0f%%", priorities.time_investment * 100))
    println()

    # Phase 1
    if !isempty(phase1)
        display_phase("PHASE 1: Quick Wins (Weeks 1-4)", phase1)
    end

    # Phase 2
    if !isempty(phase2)
        display_phase("PHASE 2: Main Migration (Months 2-4)", phase2)
    end

    # Phase 3
    if !isempty(phase3)
        display_phase("PHASE 3: Advanced Migration (Months 5-12)", phase3)
    end

    return scored_apps
end

function display_phase(phase_name::String, apps)
    println("\n$phase_name")
    println("─"^70)

    phase_savings = sum([app[:cost_savings] for (app, _) in apps])
    println(@sprintf("  Phase savings: \$%.2f/year", phase_savings))
    println()

    for (i, (app, score)) in enumerate(apps)
        println(@sprintf("  %2d. %-25s → %-20s", i, app[:proprietary_name],
                       app[:foss_alternatives][1]))
        println(@sprintf("      Score: %.1f%%  |  Savings: \$%.2f/year  |  Parity: %.0f%%",
                       score * 100, app[:cost_savings], app[:feature_parity] * 100))
        println(@sprintf("      Privacy: %-8s  |  Effort: %-6s  |  Learning: %s",
                       uppercase(app[:privacy_benefit]),
                       uppercase(app[:migration_effort]),
                       uppercase(app[:learning_curve])))
        println()
    end
end

function estimate_timeline(num_apps::Int)
    weeks = num_apps * 2  # 2 weeks per app average
    if weeks <= 8
        return "1-2 months"
    elseif weeks <= 24
        return "3-6 months"
    else
        return "6-12 months"
    end
end

function export_plan(scored_apps, priorities::UserPriorities)
    println("─"^70)
    println("Would you like to export this plan?")
    print("[y/N]: ")

    response = lowercase(strip(readline()))

    if response in ["y", "yes"]
        timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
        filename = "migration_plan_$timestamp.json"

        plan = Dict(
            "generated_at" => string(now()),
            "priorities" => Dict(
                "cost_savings" => priorities.cost_savings,
                "privacy" => priorities.privacy,
                "ease_of_migration" => priorities.ease_of_migration,
                "feature_completeness" => priorities.feature_completeness,
                "time_investment" => priorities.time_investment
            ),
            "total_apps" => length(scored_apps),
            "total_savings" => sum([app[:cost_savings] for (app, _) in scored_apps]),
            "apps" => [
                Dict(
                    "proprietary" => app[:proprietary_name],
                    "foss_alternative" => app[:foss_alternatives][1],
                    "score" => score,
                    "cost_savings" => app[:cost_savings],
                    "feature_parity" => app[:feature_parity],
                    "privacy_benefit" => app[:privacy_benefit],
                    "migration_effort" => app[:migration_effort]
                )
                for (app, score) in scored_apps
            ]
        )

        filepath = joinpath(@__DIR__, "..", filename)
        open(filepath, "w") do f
            JSON3.write(f, plan)
        end

        println("\n  ✓ Plan exported to: $filename")
        println()
    end
end

function main()
    print_welcome()

    # Step 1: Gather priorities
    priorities = gather_priorities()

    # Step 2: Load and select apps
    all_apps = load_app_database()
    selected_apps = select_apps_to_analyze(all_apps)

    if isempty(selected_apps)
        println("\n⚠ No applications selected. Exiting.")
        return
    end

    # Step 3: Generate migration plan
    scored_apps = generate_migration_plan(selected_apps, priorities)

    # Step 4: Export option
    export_plan(scored_apps, priorities)

    # Closing
    println("="^70)
    println("MIGRATION PLANNING COMPLETE")
    println("="^70)
    println()
    println("Next steps:")
    println("  1. Review the recommended migration phases")
    println("  2. Research FOSS alternatives in detail")
    println("  3. Start with Phase 1 (Quick Wins)")
    println("  4. Export your data before switching")
    println("  5. Run apps in parallel during transition")
    println()
    println("For detailed app information, see:")
    println("  - julia --project=. examples/example_database_stats.jl")
    println("  - julia --project=. examples/example_advanced_analysis.jl")
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
