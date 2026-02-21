"""
    test_database.jl - Database Validation Tests

    Comprehensive tests for app_db.json and rules.json integrity
"""

using Test
using JSON3

@testset "Database Validation Tests" begin

    @testset "App Database Schema" begin
        # Load app database
        app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
        @test isfile(app_db_path)

        apps = JSON3.read(read(app_db_path, String))
        @test length(apps) > 0

        println("✓ Loaded $(length(apps)) applications from database")

        # Validate each application entry
        required_fields = [
            "proprietary_name",
            "foss_alternatives",
            "category",
            "cost_savings",
            "privacy_benefit",
            "feature_parity",
            "description",
            "learning_curve",
            "migration_effort",
            "maturity",
            "platforms",
            "license",
            "community_size"
        ]

        for (idx, app) in enumerate(apps)
            # Check all required fields exist
            for field in required_fields
                field_symbol = Symbol(field)
                @test haskey(app, field_symbol) "App #$idx missing field: $field"
            end

            # Validate field types and values
            @test app[:proprietary_name] isa String
            @test !isempty(app[:proprietary_name])

            @test app[:foss_alternatives] isa Vector
            @test length(app[:foss_alternatives]) > 0

            @test app[:category] isa String
            @test app[:category] in ["productivity", "graphics", "development",
                                     "communication", "media", "security",
                                     "utilities", "gaming", "education", "business"]

            @test app[:cost_savings] isa Number
            @test app[:cost_savings] >= 0.0

            @test app[:privacy_benefit] isa String
            @test app[:privacy_benefit] in ["low", "medium", "high", "critical"]

            @test app[:feature_parity] isa Number
            @test 0.0 <= app[:feature_parity] <= 1.0

            @test app[:description] isa String
            @test !isempty(app[:description])

            @test app[:learning_curve] isa String
            @test app[:learning_curve] in ["easy", "medium", "high"]

            @test app[:migration_effort] isa String
            @test app[:migration_effort] in ["low", "medium", "high"]

            @test app[:maturity] isa String
            @test app[:maturity] in ["developing", "stable", "mature"]

            @test app[:platforms] isa Vector
            @test length(app[:platforms]) > 0

            @test app[:license] isa String
            @test !isempty(app[:license])

            @test app[:community_size] isa String
            @test app[:community_size] in ["small", "medium", "large", "growing"]
        end

        println("✓ All $(length(apps)) applications validated successfully")
    end

    @testset "Rules Database Schema" begin
        # Load rules database
        rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")
        @test isfile(rules_db_path)

        rules = JSON3.read(read(rules_db_path, String))

        # Validate top-level structure
        @test haskey(rules, :categories)
        @test haskey(rules, :risk_flags)
        @test haskey(rules, :cost_thresholds)
        @test haskey(rules, :privacy_weights)
        @test haskey(rules, :risk_scoring)
        @test haskey(rules, :foss_benefits)
        @test haskey(rules, :migration_tips)
        @test haskey(rules, :feature_parity_threshold)
        @test haskey(rules, :gdpr_flags)
        @test haskey(rules, :platform_specific)
        @test haskey(rules, :ambient_settings)

        println("✓ Rules database has all required sections")

        # Validate categories
        @test rules[:categories] isa Dict
        expected_categories = [
            :productivity, :graphics, :development, :communication,
            :media, :security, :utilities, :gaming, :education, :business
        ]
        for cat in expected_categories
            @test haskey(rules[:categories], cat)
            @test rules[:categories][cat] isa Vector
            @test length(rules[:categories][cat]) > 0
        end

        # Validate risk flags
        @test haskey(rules[:risk_flags], :telemetry_keywords)
        @test haskey(rules[:risk_flags], :ad_keywords)
        @test haskey(rules[:risk_flags], :account_keywords)
        @test haskey(rules[:risk_flags], :pii_keywords)
        @test haskey(rules[:risk_flags], :sharing_keywords)
        @test haskey(rules[:risk_flags], :privacy_concerns)
        @test haskey(rules[:risk_flags], :subscription_keywords)
        @test haskey(rules[:risk_flags], :drm_keywords)

        # Validate cost thresholds
        @test rules[:cost_thresholds][:free] == 0.0
        @test rules[:cost_thresholds][:low] > 0.0
        @test rules[:cost_thresholds][:medium] > rules[:cost_thresholds][:low]
        @test rules[:cost_thresholds][:high] > rules[:cost_thresholds][:medium]
        @test rules[:cost_thresholds][:premium] > rules[:cost_thresholds][:high]

        # Validate privacy weights sum approximately to 1.0
        weights_sum = sum(values(rules[:privacy_weights]))
        @test 0.9 <= weights_sum <= 1.1  # Allow small floating point variations

        # Validate risk scoring levels
        risk_levels = [:NONE, :LOW, :MEDIUM, :HIGH, :CRITICAL]
        for level in risk_levels
            @test haskey(rules[:risk_scoring], level)
            @test haskey(rules[:risk_scoring][level], :score_min)
            @test haskey(rules[:risk_scoring][level], :score_max)
            @test haskey(rules[:risk_scoring][level], :description)
            @test haskey(rules[:risk_scoring][level], :color)
            @test haskey(rules[:risk_scoring][level], :recommendation)
        end

        # Validate GDPR flags
        gdpr_rights = [
            :right_to_access, :right_to_erasure, :right_to_portability,
            :right_to_object, :data_minimization, :purpose_limitation,
            :storage_limitation, :accuracy, :integrity_confidentiality
        ]
        for right in gdpr_rights
            @test haskey(rules[:gdpr_flags], right)
            @test rules[:gdpr_flags][right] isa Vector
        end

        # Validate platform specific
        @test haskey(rules[:platform_specific], :windows)
        @test haskey(rules[:platform_specific], :macos)
        @test haskey(rules[:platform_specific], :linux)

        for platform in [:windows, :macos, :linux]
            @test haskey(rules[:platform_specific][platform], :package_manager) ||
                  haskey(rules[:platform_specific][platform], :package_managers)
            @test haskey(rules[:platform_specific][platform], :common_paths)
        end

        # Validate ambient settings
        @test haskey(rules[:ambient_settings], :visual_feedback)
        @test haskey(rules[:ambient_settings], :audio_feedback)
        @test haskey(rules[:ambient_settings], :iot_feedback)

        for level in risk_levels
            @test haskey(rules[:ambient_settings][:visual_feedback], level)
            @test haskey(rules[:ambient_settings][:audio_feedback], level)
            @test haskey(rules[:ambient_settings][:iot_feedback], level)
        end

        println("✓ Rules database structure validated successfully")
    end

    @testset "Cross-Reference Validation" begin
        # Load both databases
        app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
        rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")

        apps = JSON3.read(read(app_db_path, String))
        rules = JSON3.read(read(rules_db_path, String))

        # Verify all app categories exist in rules
        app_categories = Set([app[:category] for app in apps])
        rules_categories = Set(keys(rules[:categories]))

        for cat in app_categories
            @test Symbol(cat) in rules_categories "Category '$cat' in app_db not found in rules"
        end

        println("✓ All app categories match rules categories")

        # Count apps per category
        category_counts = Dict{String, Int}()
        for app in apps
            cat = app[:category]
            category_counts[cat] = get(category_counts, cat, 0) + 1
        end

        println("\n📊 Applications by Category:")
        for (cat, count) in sort(collect(category_counts), by=x->x[2], rev=true)
            println("   $cat: $count apps")
        end

        # Calculate total potential savings
        total_savings = sum([app[:cost_savings] for app in apps])
        println("\n💰 Total Potential Annual Savings: \$$(round(total_savings, digits=2))")

        # Count critical privacy benefits
        critical_count = count(app -> app[:privacy_benefit] == "critical", apps)
        high_count = count(app -> app[:privacy_benefit] == "high", apps)
        println("\n🔒 Privacy Analysis:")
        println("   Critical privacy benefit: $critical_count apps")
        println("   High privacy benefit: $high_count apps")

        # Average feature parity
        avg_parity = sum([app[:feature_parity] for app in apps]) / length(apps)
        println("\n🎯 Average FOSS Feature Parity: $(round(avg_parity * 100, digits=1))%")
    end

    @testset "Data Integrity" begin
        app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
        apps = JSON3.read(read(app_db_path, String))

        # Check for duplicate proprietary names
        prop_names = [app[:proprietary_name] for app in apps]
        @test length(prop_names) == length(Set(prop_names)) "Duplicate proprietary app names found"

        # Check for reasonable cost savings (not negative or absurdly high)
        for app in apps
            @test app[:cost_savings] >= 0.0
            @test app[:cost_savings] < 10000.0  # Sanity check
        end

        # Check feature parity is valid percentage
        for app in apps
            @test 0.0 <= app[:feature_parity] <= 1.0
        end

        # Check all apps have at least one alternative
        for app in apps
            @test length(app[:foss_alternatives]) >= 1 "App $(app[:proprietary_name]) has no alternatives"
        end

        println("✓ Data integrity checks passed")
    end

    @testset "Performance" begin
        # Test database loading performance
        app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
        rules_db_path = joinpath(@__DIR__, "..", "data", "rules.json")

        # Measure app DB load time
        app_time = @elapsed begin
            for i in 1:100
                JSON3.read(read(app_db_path, String))
            end
        end
        @test app_time < 1.0  # Should load 100 times in under 1 second

        # Measure rules DB load time
        rules_time = @elapsed begin
            for i in 1:100
                JSON3.read(read(rules_db_path, String))
            end
        end
        @test rules_time < 1.0

        println("✓ Database loading performance acceptable")
        println("   App DB: $(round(app_time/100 * 1000, digits=2))ms per load")
        println("   Rules DB: $(round(rules_time/100 * 1000, digits=2))ms per load")
    end
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    println("\n" * "="^70)
    println("DATABASE VALIDATION TEST SUITE")
    println("="^70 * "\n")

    include(Test.@__FILE__)

    println("\n" * "="^70)
    println("ALL DATABASE TESTS PASSED ✓")
    println("="^70 * "\n")
end
