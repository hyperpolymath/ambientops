#!/usr/bin/env julia

"""
    benchmark_database.jl - Database Performance Benchmarks

    Comprehensive performance testing for Juisys database operations.

    Usage: julia --project=. benchmarks/benchmark_database.jl
"""

push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using JSON3
using Printf
using Dates

struct BenchmarkResult
    name::String
    iterations::Int
    total_time_ms::Float64
    avg_time_ms::Float64
    min_time_ms::Float64
    max_time_ms::Float64
    ops_per_second::Float64
end

function benchmark(name::String, func::Function, iterations::Int=1000)
    println("Running: $name ($iterations iterations)...")

    times = Float64[]

    # Warmup
    for _ in 1:min(10, iterations)
        func()
    end

    # Actual benchmark
    for _ in 1:iterations
        start = time()
        func()
        elapsed = (time() - start) * 1000  # Convert to ms
        push!(times, elapsed)
    end

    total_time = sum(times)
    avg_time = total_time / iterations
    min_time = minimum(times)
    max_time = maximum(times)
    ops_per_sec = 1000.0 / avg_time

    return BenchmarkResult(
        name,
        iterations,
        total_time,
        avg_time,
        min_time,
        max_time,
        ops_per_sec
    )
end

function print_result(result::BenchmarkResult)
    println("\n" * "─"^70)
    println(result.name)
    println("─"^70)
    println(@sprintf("  Iterations:       %d", result.iterations))
    println(@sprintf("  Total Time:       %.2f ms", result.total_time_ms))
    println(@sprintf("  Average Time:     %.3f ms", result.avg_time_ms))
    println(@sprintf("  Min Time:         %.3f ms", result.min_time_ms))
    println(@sprintf("  Max Time:         %.3f ms", result.max_time_ms))
    println(@sprintf("  Throughput:       %.0f ops/sec", result.ops_per_second))
end

function benchmark_database_loading()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")

    results = []

    # Benchmark: Load app database
    result1 = benchmark("Load App Database (JSON parsing)", 1000) do
        JSON3.read(read(app_db_path, String))
    end
    push!(results, result1)
    print_result(result1)

    # Benchmark: Load rules database
    result2 = benchmark("Load Rules Database (JSON parsing)", 1000) do
        JSON3.read(read(rules_db_path, String))
    end
    push!(results, result2)
    print_result(result2)

    # Benchmark: Load both databases
    result3 = benchmark("Load Both Databases", 500) do
        apps = JSON3.read(read(app_db_path, String))
        rules = JSON3.read(read(rules_db_path, String))
    end
    push!(results, result3)
    print_result(result3)

    return results
end

function benchmark_database_queries()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    apps = JSON3.read(read(app_db_path, String))

    results = []

    # Benchmark: Filter by category
    result1 = benchmark("Filter by Category", 10000) do
        filter(app -> app[:category] == "productivity", apps)
    end
    push!(results, result1)
    print_result(result1)

    # Benchmark: Filter by cost threshold
    result2 = benchmark("Filter by Cost (>$100)", 10000) do
        filter(app -> app[:cost_savings] > 100.0, apps)
    end
    push!(results, result2)
    print_result(result2)

    # Benchmark: Filter by privacy benefit
    result3 = benchmark("Filter by Privacy Benefit", 10000) do
        filter(app -> app[:privacy_benefit] in ["critical", "high"], apps)
    end
    push!(results, result3)
    print_result(result3)

    # Benchmark: Complex query
    result4 = benchmark("Complex Query (multi-criteria)", 10000) do
        filter(app -> app[:cost_savings] > 50.0 &&
                     app[:privacy_benefit] == "critical" &&
                     app[:feature_parity] >= 0.80 &&
                     app[:migration_effort] == "low",
              apps)
    end
    push!(results, result4)
    print_result(result4)

    # Benchmark: Sort by cost
    result5 = benchmark("Sort by Cost Savings", 10000) do
        sort(apps, by=x->x[:cost_savings], rev=true)
    end
    push!(results, result5)
    print_result(result5)

    # Benchmark: Calculate total savings
    result6 = benchmark("Calculate Total Savings", 10000) do
        sum([app[:cost_savings] for app in apps])
    end
    push!(results, result6)
    print_result(result6)

    return results
end

function benchmark_string_operations()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    apps = JSON3.read(read(app_db_path, String))

    results = []

    # Benchmark: Case-insensitive search
    result1 = benchmark("Case-insensitive Name Search", 10000) do
        query = "office"
        query_lower = lowercase(query)
        filter(app -> occursin(query_lower, lowercase(app[:proprietary_name])), apps)
    end
    push!(results, result1)
    print_result(result1)

    # Benchmark: Extract all alternatives
    result2 = benchmark("Extract All FOSS Alternatives", 10000) do
        Set([alt for app in apps for alt in app[:foss_alternatives]])
    end
    push!(results, result2)
    print_result(result2)

    # Benchmark: Category grouping
    result3 = benchmark("Group by Category", 10000) do
        by_category = Dict{String, Vector}()
        for app in apps
            cat = app[:category]
            if !haskey(by_category, cat)
                by_category[cat] = []
            end
            push!(by_category[cat], app)
        end
        by_category
    end
    push!(results, result3)
    print_result(result3)

    return results
end

function benchmark_scoring_algorithms()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    apps = JSON3.read(read(app_db_path, String))

    results = []

    # Benchmark: Privacy score calculation
    function calc_privacy_score(app)
        scores = Dict("low" => 0.25, "medium" => 0.50, "high" => 0.75, "critical" => 1.0)
        get(scores, app[:privacy_benefit], 0.5)
    end

    result1 = benchmark("Privacy Score Calculation", 10000) do
        [calc_privacy_score(app) for app in apps]
    end
    push!(results, result1)
    print_result(result1)

    # Benchmark: Migration ease score
    function calc_migration_ease(app)
        effort_scores = Dict("low" => 1.0, "medium" => 0.6, "high" => 0.3)
        learning_scores = Dict("easy" => 1.0, "medium" => 0.7, "high" => 0.4)
        effort = get(effort_scores, app[:migration_effort], 0.5)
        learning = get(learning_scores, app[:learning_curve], 0.5)
        (effort + learning) / 2.0
    end

    result2 = benchmark("Migration Ease Score", 10000) do
        [calc_migration_ease(app) for app in apps]
    end
    push!(results, result2)
    print_result(result2)

    # Benchmark: Overall recommendation score
    function calc_overall_score(app)
        privacy = calc_privacy_score(app)
        ease = calc_migration_ease(app)
        features = app[:feature_parity]
        maturity_scores = Dict("mature" => 1.0, "stable" => 0.8, "developing" => 0.5)
        maturity = get(maturity_scores, app[:maturity], 0.7)

        0.30 * privacy + 0.25 * features + 0.25 * ease + 0.20 * maturity
    end

    result3 = benchmark("Overall Recommendation Score", 10000) do
        [(app, calc_overall_score(app)) for app in apps]
    end
    push!(results, result3)
    print_result(result3)

    # Benchmark: Rank all apps
    result4 = benchmark("Rank All Applications", 10000) do
        scored = [(app, calc_overall_score(app)) for app in apps]
        sort(scored, by=x->x[2], rev=true)
    end
    push!(results, result4)
    print_result(result4)

    return results
end

function benchmark_memory_usage()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")

    println("\n" * "─"^70)
    println("Memory Usage Analysis")
    println("─"^70)

    # Measure file sizes
    app_db_size = filesize(app_db_path)
    rules_db_size = filesize(rules_db_path)

    println(@sprintf("  App Database File:    %d bytes (%.2f KB)", app_db_size, app_db_size / 1024))
    println(@sprintf("  Rules Database File:  %d bytes (%.2f KB)", rules_db_size, rules_db_size / 1024))
    println(@sprintf("  Total on Disk:        %d bytes (%.2f KB)", app_db_size + rules_db_size, (app_db_size + rules_db_size) / 1024))

    # Load and measure in-memory size
    apps = JSON3.read(read(app_db_path, String))
    rules = JSON3.read(read(rules_db_path, String))

    println()
    println(@sprintf("  Applications Loaded:  %d", length(apps)))
    println(@sprintf("  Categories in Rules:  %d", length(rules[:categories])))
end

function generate_summary(all_results)
    println("\n" * "="^70)
    println("BENCHMARK SUMMARY")
    println("="^70)
    println()

    total_benchmarks = sum([length(r) for r in all_results])
    println(@sprintf("Total Benchmarks Run: %d", total_benchmarks))
    println()

    # Find fastest and slowest operations
    all_flat = vcat(all_results...)
    fastest = minimum([r.avg_time_ms for r in all_flat])
    slowest = maximum([r.avg_time_ms for r in all_flat])

    fastest_op = filter(r -> r.avg_time_ms == fastest, all_flat)[1]
    slowest_op = filter(r -> r.avg_time_ms == slowest, all_flat)[1]

    println("Performance Highlights:")
    println(@sprintf("  Fastest Operation:  %s (%.3f ms)", fastest_op.name, fastest_op.avg_time_ms))
    println(@sprintf("  Slowest Operation:  %s (%.3f ms)", slowest_op.name, slowest_op.avg_time_ms))
    println()

    # Overall assessment
    avg_overall = sum([r.avg_time_ms for r in all_flat]) / length(all_flat)
    println(@sprintf("Average Operation Time: %.3f ms", avg_overall))
    println()

    if avg_overall < 1.0
        println("✓ EXCELLENT - All operations under 1ms average")
    elseif avg_overall < 5.0
        println("✓ GOOD - Fast performance across all operations")
    elseif avg_overall < 10.0
        println("⚠ ACCEPTABLE - Performance adequate")
    else
        println("⚠ NEEDS OPTIMIZATION - Consider performance improvements")
    end
end

function export_results(all_results, output_path)
    all_flat = vcat(all_results...)

    export_data = Dict(
        "generated_at" => string(now()),
        "total_benchmarks" => length(all_flat),
        "results" => [
            Dict(
                "name" => r.name,
                "iterations" => r.iterations,
                "avg_time_ms" => r.avg_time_ms,
                "min_time_ms" => r.min_time_ms,
                "max_time_ms" => r.max_time_ms,
                "ops_per_second" => r.ops_per_second
            )
            for r in all_flat
        ]
    )

    open(output_path, "w") do f
        JSON3.write(f, export_data)
    end

    println("\n✓ Results exported to: $output_path")
end

function main()
    println("\n" * "="^70)
    println("JUISYS DATABASE PERFORMANCE BENCHMARKS")
    println("="^70)
    println()
    println("Started: $(now())")
    println()

    all_results = []

    println("\n" * "="^70)
    println("PHASE 1: Database Loading Performance")
    println("="^70)
    results1 = benchmark_database_loading()
    push!(all_results, results1)

    println("\n" * "="^70)
    println("PHASE 2: Database Query Performance")
    println("="^70)
    results2 = benchmark_database_queries()
    push!(all_results, results2)

    println("\n" * "="^70)
    println("PHASE 3: String Operation Performance")
    println("="^70)
    results3 = benchmark_string_operations()
    push!(all_results, results3)

    println("\n" * "="^70)
    println("PHASE 4: Scoring Algorithm Performance")
    println("="^70)
    results4 = benchmark_scoring_algorithms()
    push!(all_results, results4)

    println("\n" * "="^70)
    println("PHASE 5: Memory Usage")
    println("="^70)
    benchmark_memory_usage()

    # Summary
    generate_summary(all_results)

    # Export results
    output_path = joinpath(@__DIR__, "..", "benchmark_results.json")
    export_results(all_results, output_path)

    println("\n" * "="^70)
    println("BENCHMARKS COMPLETE")
    println("="^70)
    println("\nCompleted: $(now())")
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
