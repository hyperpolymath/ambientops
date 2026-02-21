"""
    Alternatives.jl - FOSS Alternative Recommendations for Juisys

    Provides FOSS (Free and Open Source Software) alternatives to
    proprietary applications with cost analysis and feature comparison.

    Features:
    - Alternative lookup from database
    - Cost savings calculation
    - Feature parity assessment
    - Privacy benefit scoring
    - Migration difficulty estimation

    PRIVACY: All data from local JSON database, no network calls.

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module Alternatives

export Alternative, find_alternatives, calculate_savings
export rank_alternatives, get_migration_tips
export compare_features, assess_feature_parity

using JSON3

"""
    Alternative

    Represents a FOSS alternative to proprietary software.
"""
struct Alternative
    name::String
    category::String
    description::String
    url::String
    platforms::Vector{String}
    license::String

    # Comparison metrics
    feature_parity::Float64      # 0.0-1.0, how well it matches original
    learning_curve::Symbol       # :easy, :medium, :hard
    migration_effort::Symbol     # :low, :medium, :high
    maturity::Symbol             # :alpha, :beta, :stable, :mature

    # Benefits
    cost_savings_annual::Float64
    privacy_improvement::Symbol  # :none, :low, :medium, :high, :critical
    community_size::Symbol       # :small, :medium, :large
end

"""
    find_alternatives(app_name::String, db_path::String)

    Find FOSS alternatives for given proprietary application.

    Returns: Vector of Alternative structs.
    PRIVACY: Loads from local database only.
"""
function find_alternatives(app_name::String, db_path::String)
    if !isfile(db_path)
        @warn "App database not found" path=db_path
        return Alternative[]
    end

    try
        db_content = read(db_path, String)
        db = JSON3.read(db_content)

        app_lower = lowercase(app_name)

        # Find matching entry
        for entry in db
            if lowercase(get(entry, :proprietary_name, "")) == app_lower
                return build_alternatives(entry)
            end
        end

        @info "No alternatives found in database" app=app_name
        return Alternative[]

    catch e
        @error "Failed to load alternatives" exception=e
        return Alternative[]
    end
end

"""
    build_alternatives(db_entry)

    Build Alternative structs from database entry.
"""
function build_alternatives(db_entry)
    alternatives = Alternative[]

    foss_list = get(db_entry, :foss_alternatives, [])
    category = get(db_entry, :category, "other")
    cost_savings = get(db_entry, :cost_savings, 0.0)
    privacy_benefit = get(db_entry, :privacy_benefit, "medium")
    feature_parity = get(db_entry, :feature_parity, 0.8)

    for alt_name in foss_list
        alt = Alternative(
            alt_name,
            category,
            get(db_entry, :description, "FOSS alternative"),
            get(db_entry, :url, ""),
            get(db_entry, :platforms, ["Linux", "Windows", "macOS"]),
            get(db_entry, :license, "GPL/MIT/Apache"),
            feature_parity,
            parse_difficulty(get(db_entry, :learning_curve, "medium")),
            parse_difficulty(get(db_entry, :migration_effort, "medium")),
            parse_maturity(get(db_entry, :maturity, "stable")),
            cost_savings / length(foss_list),  # Split savings among alternatives
            parse_privacy_level(privacy_benefit),
            parse_community_size(get(db_entry, :community_size, "medium"))
        )

        push!(alternatives, alt)
    end

    return alternatives
end

"""
    parse_difficulty(diff_str)

    Parse difficulty level from string.
"""
function parse_difficulty(diff_str)
    diff_lower = lowercase(string(diff_str))

    if diff_lower in ["easy", "low"]
        return :easy
    elseif diff_lower in ["hard", "high", "difficult"]
        return :hard
    else
        return :medium
    end
end

"""
    parse_maturity(maturity_str)

    Parse maturity level from string.
"""
function parse_maturity(maturity_str)
    mat_lower = lowercase(string(maturity_str))

    if mat_lower == "alpha"
        return :alpha
    elseif mat_lower == "beta"
        return :beta
    elseif mat_lower in ["stable", "production"]
        return :stable
    elseif mat_lower == "mature"
        return :mature
    else
        return :stable
    end
end

"""
    parse_privacy_level(privacy_str)

    Parse privacy improvement level.
"""
function parse_privacy_level(privacy_str)
    priv_lower = lowercase(string(privacy_str))

    if priv_lower in ["none", "no"]
        return :none
    elseif priv_lower == "low"
        return :low
    elseif priv_lower in ["medium", "moderate"]
        return :medium
    elseif priv_lower == "high"
        return :high
    elseif priv_lower in ["critical", "very high", "excellent"]
        return :critical
    else
        return :medium
    end
end

"""
    parse_community_size(size_str)

    Parse community size from string.
"""
function parse_community_size(size_str)
    size_lower = lowercase(string(size_str))

    if size_lower == "small"
        return :small
    elseif size_lower == "large"
        return :large
    else
        return :medium
    end
end

"""
    calculate_savings(proprietary_cost::Float64, alternatives::Vector{Alternative})

    Calculate total and per-alternative cost savings.

    Returns: (total_savings, best_alternative)
"""
function calculate_savings(proprietary_cost::Float64,
                          alternatives::Vector{Alternative})

    if isempty(alternatives)
        return (0.0, nothing)
    end

    # FOSS alternatives are typically free (cost = 0)
    # Savings = proprietary cost - 0 = proprietary cost
    total_savings = proprietary_cost

    # Find best alternative by combined score
    ranked = rank_alternatives(alternatives)
    best = isempty(ranked) ? nothing : first(ranked)

    return (total_savings, best)
end

"""
    rank_alternatives(alternatives::Vector{Alternative})

    Rank alternatives by overall score considering:
    - Feature parity (40%)
    - Privacy improvement (30%)
    - Learning curve (15%)
    - Maturity (15%)

    Returns: Sorted vector (best first).
"""
function rank_alternatives(alternatives::Vector{Alternative})
    if isempty(alternatives)
        return alternatives
    end

    # Calculate score for each alternative
    scored = map(alternatives) do alt
        score = calculate_alternative_score(alt)
        (alt, score)
    end

    # Sort by score descending
    sort!(scored, by=x -> x[2], rev=true)

    return [alt for (alt, score) in scored]
end

"""
    calculate_alternative_score(alt::Alternative)

    Calculate overall quality score for alternative.
    Higher is better.
"""
function calculate_alternative_score(alt::Alternative)
    # Feature parity (40%)
    feature_score = alt.feature_parity * 0.4

    # Privacy improvement (30%)
    privacy_score = score_privacy(alt.privacy_improvement) * 0.3

    # Learning curve - inverse (15%)
    # Easy is better, so invert the score
    learning_score = score_difficulty(alt.learning_curve, inverse=true) * 0.15

    # Maturity (15%)
    maturity_score = score_maturity(alt.maturity) * 0.15

    return feature_score + privacy_score + learning_score + maturity_score
end

"""
    score_privacy(level::Symbol)

    Convert privacy level to numeric score.
"""
function score_privacy(level::Symbol)
    mapping = Dict(
        :none => 0.0,
        :low => 0.3,
        :medium => 0.6,
        :high => 0.9,
        :critical => 1.0
    )

    return get(mapping, level, 0.6)
end

"""
    score_difficulty(level::Symbol; inverse::Bool=false)

    Convert difficulty level to numeric score.
"""
function score_difficulty(level::Symbol; inverse::Bool=false)
    mapping = Dict(
        :easy => 1.0,
        :medium => 0.6,
        :hard => 0.3
    )

    score = get(mapping, level, 0.6)
    return inverse ? score : (1.0 - score)
end

"""
    score_maturity(level::Symbol)

    Convert maturity level to numeric score.
"""
function score_maturity(level::Symbol)
    mapping = Dict(
        :alpha => 0.3,
        :beta => 0.5,
        :stable => 0.8,
        :mature => 1.0
    )

    return get(mapping, level, 0.8)
end

"""
    get_migration_tips(from_app::String, to_alt::Alternative)

    Generate migration tips for switching to alternative.

    Returns: Vector of helpful tips.
"""
function get_migration_tips(from_app::String, to_alt::Alternative)
    tips = String[]

    # General tips
    push!(tips, "1. Export your data from $(from_app) before switching")
    push!(tips, "2. Install $(to_alt.name) and explore the interface")
    push!(tips, "3. Import your data into $(to_alt.name)")

    # Learning curve specific
    if to_alt.learning_curve == :easy
        push!(tips, "4. $(to_alt.name) is user-friendly - you should adapt quickly")
    elseif to_alt.learning_curve == :hard
        push!(tips, "4. $(to_alt.name) has a learning curve - allocate time for training")
        push!(tips, "5. Consider running both tools in parallel during transition")
    end

    # Feature parity specific
    if to_alt.feature_parity < 0.7
        push!(tips, "Note: $(to_alt.name) may not have all features of $(from_app)")
        push!(tips, "Identify which features you actually use before switching")
    elseif to_alt.feature_parity >= 0.9
        push!(tips, "Great news: $(to_alt.name) has excellent feature parity")
    end

    # Privacy benefits
    if to_alt.privacy_improvement in [:high, :critical]
        push!(tips, "✓ Significant privacy improvement - no telemetry or data collection")
    end

    # Community
    if to_alt.community_size == :large
        push!(tips, "Strong community support available for $(to_alt.name)")
    end

    return tips
end

"""
    compare_features(proprietary::String, foss_alt::String)

    Compare features between proprietary and FOSS alternative.
    (Placeholder for future detailed feature comparison)

    Returns: Dict with comparison results.
"""
function compare_features(proprietary::String, foss_alt::String)
    # This is a simplified comparison
    # Full implementation would have detailed feature matrices

    comparison = Dict(
        "proprietary" => proprietary,
        "foss" => foss_alt,
        "features" => Dict(
            "basic_functionality" => "both",
            "advanced_features" => "varies",
            "privacy" => "advantage: FOSS",
            "cost" => "advantage: FOSS",
            "support" => "varies",
            "updates" => "both"
        )
    )

    return comparison
end

"""
    assess_feature_parity(proprietary::String, foss_alt::String, db_path::String)

    Assess how well FOSS alternative matches proprietary software features.

    Returns: Float64 score 0.0-1.0
"""
function assess_feature_parity(proprietary::String, foss_alt::String,
                               db_path::String)

    alternatives = find_alternatives(proprietary, db_path)

    for alt in alternatives
        if lowercase(alt.name) == lowercase(foss_alt)
            return alt.feature_parity
        end
    end

    # Default estimate if not found
    return 0.75
end

"""
    format_alternative_report(alt::Alternative)

    Format alternative as readable report text.
"""
function format_alternative_report(alt::Alternative)
    report = IOBuffer()

    println(report, "📦 $(alt.name)")
    println(report, "   Category: $(alt.category)")
    println(report, "   License: $(alt.license)")
    println(report, "   Platforms: $(join(alt.platforms, ", "))")
    println(report, "")
    println(report, "   Feature Parity: $(round(alt.feature_parity * 100, digits=1))%")
    println(report, "   Learning Curve: $(alt.learning_curve)")
    println(report, "   Maturity: $(alt.maturity)")
    println(report, "   Privacy Improvement: $(alt.privacy_improvement)")
    println(report, "   Annual Savings: \$$(round(alt.cost_savings_annual, digits=2))")

    return String(take!(report))
end

end # module Alternatives
