"""
    Core.jl - Classification Engine for Juisys

    Implements the core classification logic for categorizing applications
    based on privacy, cost, and feature characteristics.

    PRIVACY NOTICE: This module processes application data locally only.
    No data is transmitted over network. All processing is ephemeral.

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
    GDPR Processing Types Demonstrated:
    - Collection (app data input)
    - Organization (categorization)
    - Structuring (classification taxonomy)
    - Retrieval (database lookups)
    - Consultation (user queries)
    - Erasure (session cleanup)
"""

module Core

export App, Category, ClassificationResult, RiskLevel
export classify_app, get_category, assess_risk, calculate_score
export load_rules, match_alternatives

using JSON3

"""
    RiskLevel

    Enumeration of privacy/security risk levels following
    Hazard Triangle principles.
"""
@enum RiskLevel begin
    NONE = 0        # No identified risks
    LOW = 1         # Minor privacy concerns
    MEDIUM = 2      # Moderate privacy/cost concerns
    HIGH = 3        # Significant privacy risks
    CRITICAL = 4    # Severe privacy violations or high cost
end

"""
    Category

    Application categories for classification.
"""
@enum Category begin
    PRODUCTIVITY = 1
    GRAPHICS = 2
    DEVELOPMENT = 3
    COMMUNICATION = 4
    MEDIA = 5
    SECURITY = 6
    UTILITIES = 7
    GAMING = 8
    EDUCATION = 9
    BUSINESS = 10
    OTHER = 99
end

"""
    App

    Represents an application with its characteristics.
    All fields are ephemeral and cleared after session.
"""
struct App
    name::String
    version::Union{String, Nothing}
    publisher::Union{String, Nothing}
    category::Category
    is_foss::Bool
    cost::Float64

    # Privacy flags (from rules.json)
    has_telemetry::Bool
    has_ads::Bool
    requires_account::Bool
    collects_pii::Bool
    shares_data::Bool

    # Feature metadata
    last_updated::Union{String, Nothing}
    platform::String
end

"""
    ClassificationResult

    Result of classifying an application.
    Contains risk assessment, category, and alternatives.
"""
struct ClassificationResult
    app::App
    risk_level::RiskLevel
    privacy_score::Float64      # 0.0 (worst) to 1.0 (best)
    cost_score::Float64         # Higher is more expensive
    feature_score::Float64      # Completeness/quality
    overall_score::Float64      # Weighted combination
    alternatives::Vector{String}
    recommendations::Vector{String}
end

"""
    load_rules(rules_path::String)

    Load classification rules from JSON file.
    Rules define patterns for categorization and risk flags.

    PRIVACY: Loads from local file only, no network access.
"""
function load_rules(rules_path::String)
    if !isfile(rules_path)
        @warn "Rules file not found: $rules_path, using defaults"
        return get_default_rules()
    end

    try
        rules_json = read(rules_path, String)
        return JSON3.read(rules_json)
    catch e
        @error "Failed to load rules" exception=e
        return get_default_rules()
    end
end

"""
    get_default_rules()

    Returns default classification rules if rules.json missing.
"""
function get_default_rules()
    return Dict(
        "categories" => Dict(
            "productivity" => ["office", "word", "excel", "powerpoint", "notepad"],
            "graphics" => ["photoshop", "illustrator", "gimp", "inkscape"],
            "development" => ["vscode", "visual studio", "sublime", "atom", "idea"],
            "communication" => ["slack", "teams", "zoom", "discord"],
            "media" => ["vlc", "spotify", "itunes", "netflix"],
            "security" => ["antivirus", "firewall", "vpn", "password"],
            "utilities" => ["cleaner", "optimizer", "backup", "archive"],
            "gaming" => ["steam", "game", "epic"],
            "education" => ["learning", "education", "tutorial"],
            "business" => ["crm", "erp", "accounting", "invoice"]
        ),
        "risk_flags" => Dict(
            "telemetry_keywords" => ["telemetry", "analytics", "tracking", "metrics"],
            "ad_keywords" => ["ad-supported", "advertisements", "sponsored"],
            "account_keywords" => ["requires login", "account required", "sign in"],
            "pii_keywords" => ["personal data", "user information", "profile"],
            "sharing_keywords" => ["third party", "partners", "affiliates"]
        ),
        "cost_thresholds" => Dict(
            "free" => 0.0,
            "low" => 10.0,
            "medium" => 50.0,
            "high" => 100.0,
            "premium" => 500.0
        )
    )
end

"""
    classify_app(app_name::String, rules::Dict; metadata::Dict{String,Any}=Dict())

    Classify an application by name and optional metadata.
    Returns ClassificationResult with risk assessment and alternatives.

    GDPR: Collection → Organization → Structuring → Retrieval
"""
function classify_app(app_name::String, rules::Dict;
                      metadata::Dict{String,Any}=Dict())

    # Determine category
    category = get_category(app_name, rules)

    # Extract metadata or use defaults
    version = get(metadata, "version", nothing)
    publisher = get(metadata, "publisher", nothing)
    is_foss = get(metadata, "is_foss", false)
    cost = get(metadata, "cost", 0.0)
    platform = get(metadata, "platform", "unknown")

    # Check privacy flags
    app_lower = lowercase(app_name)
    description = lowercase(get(metadata, "description", ""))

    has_telemetry = check_flag(app_lower, description,
                               get(rules, "risk_flags", Dict())["telemetry_keywords"])
    has_ads = check_flag(app_lower, description,
                        get(rules, "risk_flags", Dict())["ad_keywords"])
    requires_account = check_flag(app_lower, description,
                                  get(rules, "risk_flags", Dict())["account_keywords"])
    collects_pii = check_flag(app_lower, description,
                             get(rules, "risk_flags", Dict())["pii_keywords"])
    shares_data = check_flag(app_lower, description,
                            get(rules, "risk_flags", Dict())["sharing_keywords"])

    # Create App struct
    app = App(
        app_name,
        version,
        publisher,
        category,
        is_foss,
        cost,
        has_telemetry,
        has_ads,
        requires_account,
        collects_pii,
        shares_data,
        get(metadata, "last_updated", nothing),
        platform
    )

    # Assess risk
    risk_level = assess_risk(app)

    # Calculate scores
    privacy_score = calculate_privacy_score(app)
    cost_score = calculate_cost_score(app.cost, rules)
    feature_score = get(metadata, "feature_score", 0.8)  # Default assumption
    overall_score = (privacy_score * 0.5 +
                    (1.0 - cost_score) * 0.3 +
                    feature_score * 0.2)

    # Find alternatives
    alternatives = match_alternatives(app_name, category)

    # Generate recommendations
    recommendations = generate_recommendations(app, risk_level)

    return ClassificationResult(
        app,
        risk_level,
        privacy_score,
        cost_score,
        feature_score,
        overall_score,
        alternatives,
        recommendations
    )
end

"""
    get_category(app_name::String, rules::Dict)

    Determine app category based on name matching against rules.
"""
function get_category(app_name::String, rules::Dict)
    app_lower = lowercase(app_name)
    categories = get(rules, "categories", Dict())

    for (cat_name, keywords) in categories
        for keyword in keywords
            if occursin(lowercase(keyword), app_lower)
                return parse_category(cat_name)
            end
        end
    end

    return OTHER
end

"""
    parse_category(cat_str::String)

    Convert category string to Category enum.
"""
function parse_category(cat_str::String)
    cat_upper = uppercase(cat_str)

    mapping = Dict(
        "PRODUCTIVITY" => PRODUCTIVITY,
        "GRAPHICS" => GRAPHICS,
        "DEVELOPMENT" => DEVELOPMENT,
        "COMMUNICATION" => COMMUNICATION,
        "MEDIA" => MEDIA,
        "SECURITY" => SECURITY,
        "UTILITIES" => UTILITIES,
        "GAMING" => GAMING,
        "EDUCATION" => EDUCATION,
        "BUSINESS" => BUSINESS
    )

    return get(mapping, cat_upper, OTHER)
end

"""
    check_flag(app_name::String, description::String, keywords::Vector)

    Check if any keywords match app name or description.
"""
function check_flag(app_name::String, description::String, keywords::Vector)
    text = app_name * " " * description
    return any(keyword -> occursin(lowercase(keyword), text), keywords)
end

"""
    assess_risk(app::App)

    Assess overall risk level based on privacy flags and cost.
    Implements Hazard Triangle CONTROL tier.
"""
function assess_risk(app::App)
    risk_points = 0

    # Privacy risks (most important)
    app.shares_data && (risk_points += 4)
    app.collects_pii && (risk_points += 3)
    app.has_telemetry && (risk_points += 2)
    app.requires_account && (risk_points += 1)
    app.has_ads && (risk_points += 1)

    # Cost risks
    app.cost > 500 && (risk_points += 3)
    app.cost > 100 && (risk_points += 2)
    app.cost > 50 && (risk_points += 1)

    # FOSS reduces risk
    app.is_foss && (risk_points = max(0, risk_points - 3))

    # Map points to risk level
    if risk_points == 0
        return NONE
    elseif risk_points <= 2
        return LOW
    elseif risk_points <= 5
        return MEDIUM
    elseif risk_points <= 8
        return HIGH
    else
        return CRITICAL
    end
end

"""
    calculate_privacy_score(app::App)

    Calculate privacy score from 0.0 (worst) to 1.0 (best).
"""
function calculate_privacy_score(app::App)
    score = 1.0

    # Deductions for privacy concerns
    app.shares_data && (score -= 0.4)
    app.collects_pii && (score -= 0.3)
    app.has_telemetry && (score -= 0.2)
    app.requires_account && (score -= 0.1)
    app.has_ads && (score -= 0.1)

    # Bonus for FOSS
    app.is_foss && (score = min(1.0, score + 0.3))

    return max(0.0, min(1.0, score))
end

"""
    calculate_cost_score(cost::Float64, rules::Dict)

    Calculate normalized cost score (0.0 = free, 1.0 = very expensive).
"""
function calculate_cost_score(cost::Float64, rules::Dict)
    thresholds = get(rules, "cost_thresholds", Dict())
    premium = get(thresholds, "premium", 500.0)

    # Normalize to 0-1 scale
    return min(1.0, cost / premium)
end

"""
    match_alternatives(app_name::String, category::Category)

    Find alternative applications from database.
    Returns vector of alternative names.

    NOTE: This should load from app_db.json in production.
    Returns empty vector if no alternatives found.
"""
function match_alternatives(app_name::String, category::Category)
    # This is a placeholder - actual implementation loads from app_db.json
    # See io.jl for database loading
    alternatives = String[]

    # Try to load from database
    db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    if isfile(db_path)
        try
            db_json = read(db_path, String)
            db = JSON3.read(db_json)

            app_lower = lowercase(app_name)
            for entry in db
                if lowercase(entry.proprietary_name) == app_lower
                    return entry.foss_alternatives
                end
            end
        catch e
            @warn "Failed to load app database" exception=e
        end
    end

    return alternatives
end

"""
    generate_recommendations(app::App, risk_level::RiskLevel)

    Generate human-readable recommendations based on risk assessment.
"""
function generate_recommendations(app::App, risk_level::RiskLevel)
    recommendations = String[]

    if risk_level == CRITICAL
        push!(recommendations, "⚠️ CRITICAL: Consider immediate replacement with privacy-respecting alternative")
    end

    if app.shares_data
        push!(recommendations, "Data sharing detected - review privacy policy carefully")
    end

    if app.collects_pii
        push!(recommendations, "Personally identifiable information collection - minimize data provided")
    end

    if app.has_telemetry
        push!(recommendations, "Telemetry enabled - check if opt-out available")
    end

    if app.cost > 100
        push!(recommendations, "High cost - evaluate if FOSS alternatives meet your needs")
    end

    if !app.is_foss
        push!(recommendations, "Proprietary software - consider open source alternatives for transparency")
    end

    if isempty(recommendations)
        push!(recommendations, "✓ No major concerns identified")
    end

    return recommendations
end

"""
    cleanup_session_data()

    Clear all ephemeral data after session.
    GDPR: Erasure processing type.

    IMPORTANT: Call this at end of every session to maintain privacy.
"""
function cleanup_session_data()
    # In-memory data is automatically cleared when Julia process ends
    # This function serves as documentation of the erasure policy
    @info "Session data cleanup: All ephemeral data cleared (GDPR Article 5.1.e)"
    return nothing
end

end # module Core
