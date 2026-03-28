"""
    IO.jl - Input/Output Handling for Juisys

    Handles all file I/O operations including:
    - Loading app database and rules
    - Manual app entry
    - Importing app lists from files (CSV, JSON, TXT)
    - Exporting results (handled in coordination with reports.jl)
    - Data validation

    PRIVACY: All I/O is local filesystem only, no network operations.

    GDPR Processing Types:
    - Collection (input from user/files)
    - Recording (temporary storage)
    - Organization (parsing and structuring)
    - Retrieval (database queries)

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module IO

export load_app_database, load_rules, validate_app_db
export manual_entry, import_from_file
export save_to_file, FileFormat
export parse_csv, parse_json, parse_txt

using JSON3

"""
    FileFormat

    Supported file formats for import/export.
"""
@enum FileFormat begin
    CSV = 1
    JSON = 2
    TXT = 3
    XLSX = 4
    MARKDOWN = 5
    HTML = 6
end

"""
    load_app_database(db_path::String)

    Load application alternatives database from JSON file.

    Returns: Vector of app entries with alternatives and metadata.
    PRIVACY: Loads from local file only, no network access.
"""
function load_app_database(db_path::String)
    if !isfile(db_path)
        @warn "App database not found: $db_path"
        return []
    end

    try
        json_content = read(db_path, String)
        db = JSON3.read(json_content)

        @info "App database loaded" entries=length(db)
        return db
    catch e
        @error "Failed to load app database" exception=e path=db_path
        return []
    end
end

"""
    load_rules(rules_path::String)

    Load classification rules from JSON file.

    Returns: Dict with categorization rules and risk flags.
"""
function load_rules(rules_path::String)
    if !isfile(rules_path)
        @warn "Rules file not found: $rules_path, using defaults"
        return get_default_rules()
    end

    try
        json_content = read(rules_path, String)
        rules = JSON3.read(json_content)

        @info "Rules loaded successfully"
        return rules
    catch e
        @error "Failed to load rules" exception=e path=rules_path
        return get_default_rules()
    end
end

"""
    get_default_rules()

    Returns minimal default rules if rules.json missing.
    Fallback to ensure tool still functions.
"""
function get_default_rules()
    return Dict(
        "categories" => Dict(
            "productivity" => ["office", "word", "excel", "notepad"],
            "graphics" => ["photoshop", "gimp", "paint"],
            "development" => ["vscode", "visual studio", "sublime"],
            "other" => []
        ),
        "risk_flags" => Dict(
            "telemetry_keywords" => ["telemetry", "analytics", "tracking"],
            "ad_keywords" => ["ad-supported", "advertisements"],
            "account_keywords" => ["requires login", "account required"],
            "pii_keywords" => ["personal data", "user information"],
            "sharing_keywords" => ["third party", "partners"]
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
    validate_app_db(db_path::String)

    Validate app database structure and content.
    Returns (valid::Bool, errors::Vector{String}).
"""
function validate_app_db(db_path::String)
    errors = String[]

    if !isfile(db_path)
        push!(errors, "Database file does not exist: $db_path")
        return (false, errors)
    end

    try
        db = load_app_database(db_path)

        if isempty(db)
            push!(errors, "Database is empty")
            return (false, errors)
        end

        # Validate each entry
        for (idx, entry) in enumerate(db)
            # Check required fields
            if !haskey(entry, :proprietary_name)
                push!(errors, "Entry $idx missing 'proprietary_name'")
            end

            if !haskey(entry, :foss_alternatives)
                push!(errors, "Entry $idx missing 'foss_alternatives'")
            end

            if !haskey(entry, :category)
                push!(errors, "Entry $idx missing 'category'")
            end

            # Validate data types
            if haskey(entry, :cost_savings) && !isa(entry.cost_savings, Number)
                push!(errors, "Entry $idx 'cost_savings' must be numeric")
            end

            if haskey(entry, :feature_parity) && !isa(entry.feature_parity, Number)
                push!(errors, "Entry $idx 'feature_parity' must be numeric")
            end
        end

        if isempty(errors)
            @info "Database validation passed" entries=length(db)
            return (true, errors)
        else
            @warn "Database validation failed" error_count=length(errors)
            return (false, errors)
        end

    catch e
        push!(errors, "Failed to parse database: $(sprint(showerror, e))")
        return (false, errors)
    end
end

"""
    manual_entry()

    Interactive manual entry of application information.
    Used in NO PEEK mode when no system access granted.

    Returns: Dict with app metadata.
    GDPR: Collection processing type.
"""
function manual_entry()
    println("\n" * "="^70)
    println("MANUAL APP ENTRY (NO PEEK Mode)")
    println("="^70)
    println("Enter application details manually.")
    println("This mode requires NO system access - maximum privacy.")
    println()

    print("Application name: ")
    app_name = strip(readline())

    if isempty(app_name)
        @warn "Empty app name, aborting manual entry"
        return nothing
    end

    print("Version (optional, press Enter to skip): ")
    version = strip(readline())

    print("Publisher (optional): ")
    publisher = strip(readline())

    print("Is this Free/Open Source Software? [y/N]: ")
    is_foss = lowercase(strip(readline())) in ["y", "yes"]

    print("Monthly/annual cost (0 if free): ")
    cost_str = strip(readline())
    cost = try
        parse(Float64, cost_str)
    catch
        0.0
    end

    print("Does it have telemetry/tracking? [y/N]: ")
    has_telemetry = lowercase(strip(readline())) in ["y", "yes"]

    print("Does it show advertisements? [y/N]: ")
    has_ads = lowercase(strip(readline())) in ["y", "yes"]

    print("Does it require an account? [y/N]: ")
    requires_account = lowercase(strip(readline())) in ["y", "yes"]

    print("Does it collect personal information? [y/N]: ")
    collects_pii = lowercase(strip(readline())) in ["y", "yes"]

    print("Does it share data with third parties? [y/N]: ")
    shares_data = lowercase(strip(readline())) in ["y", "yes"]

    metadata = Dict{String, Any}(
        "name" => app_name,
        "version" => isempty(version) ? nothing : version,
        "publisher" => isempty(publisher) ? nothing : publisher,
        "is_foss" => is_foss,
        "cost" => cost,
        "description" => "",  # Build from flags
        "platform" => "manual_entry"
    )

    # Build description from flags (for classification)
    desc_parts = String[]
    has_telemetry && push!(desc_parts, "telemetry")
    has_ads && push!(desc_parts, "ad-supported")
    requires_account && push!(desc_parts, "requires login")
    collects_pii && push!(desc_parts, "personal data")
    shares_data && push!(desc_parts, "third party")

    metadata["description"] = join(desc_parts, " ")

    println()
    @info "Manual entry complete" app=app_name

    return metadata
end

"""
    import_from_file(filepath::String, format::FileFormat)

    Import app list from file in specified format.

    Supported formats:
    - CSV: app_name, version, publisher, is_foss, cost
    - JSON: array of app objects
    - TXT: one app name per line

    Returns: Vector of app metadata dicts.
    PRIVACY: Local file read only.
"""
function import_from_file(filepath::String, format::FileFormat)
    if !isfile(filepath)
        @error "Import file not found" path=filepath
        return []
    end

    try
        if format == CSV
            return parse_csv(filepath)
        elseif format == JSON
            return parse_json(filepath)
        elseif format == TXT
            return parse_txt(filepath)
        else
            @error "Unsupported import format" format=format
            return []
        end
    catch e
        @error "Import failed" exception=e path=filepath
        return []
    end
end

"""
    parse_csv(filepath::String)

    Parse CSV file with app data.
    Expected columns: name, version, publisher, is_foss, cost
"""
function parse_csv(filepath::String)
    apps = []

    lines = readlines(filepath)

    # Skip header if present
    start_idx = 1
    if !isempty(lines) && occursin("name", lowercase(lines[1]))
        start_idx = 2
    end

    for line in lines[start_idx:end]
        line = strip(line)
        isempty(line) && continue

        parts = split(line, ',')

        if length(parts) < 1
            @warn "Skipping invalid CSV line" line=line
            continue
        end

        app_name = strip(parts[1])
        version = length(parts) >= 2 ? strip(parts[2]) : nothing
        publisher = length(parts) >= 3 ? strip(parts[3]) : nothing

        is_foss = if length(parts) >= 4
            lowercase(strip(parts[4])) in ["true", "yes", "1", "y"]
        else
            false
        end

        cost = if length(parts) >= 5
            try
                parse(Float64, strip(parts[5]))
            catch
                0.0
            end
        else
            0.0
        end

        metadata = Dict{String, Any}(
            "name" => app_name,
            "version" => isempty(something(version, "")) ? nothing : version,
            "publisher" => isempty(something(publisher, "")) ? nothing : publisher,
            "is_foss" => is_foss,
            "cost" => cost,
            "platform" => "csv_import"
        )

        push!(apps, metadata)
    end

    @info "CSV import complete" apps_count=length(apps)
    return apps
end

"""
    parse_json(filepath::String)

    Parse JSON file with app data.
    Expected: array of app objects.
"""
function parse_json(filepath::String)
    json_content = read(filepath, String)
    apps_json = JSON3.read(json_content)

    apps = []

    for app_obj in apps_json
        metadata = Dict{String, Any}(
            "name" => get(app_obj, :name, "Unknown"),
            "version" => get(app_obj, :version, nothing),
            "publisher" => get(app_obj, :publisher, nothing),
            "is_foss" => get(app_obj, :is_foss, false),
            "cost" => get(app_obj, :cost, 0.0),
            "platform" => "json_import"
        )

        push!(apps, metadata)
    end

    @info "JSON import complete" apps_count=length(apps)
    return apps
end

"""
    parse_txt(filepath::String)

    Parse plain text file with one app name per line.
    Minimal metadata - just app names.
"""
function parse_txt(filepath::String)
    apps = []

    lines = readlines(filepath)

    for line in lines
        app_name = strip(line)
        isempty(app_name) && continue

        # Skip comments
        startswith(app_name, '#') && continue

        metadata = Dict{String, Any}(
            "name" => app_name,
            "version" => nothing,
            "publisher" => nothing,
            "is_foss" => false,
            "cost" => 0.0,
            "platform" => "txt_import"
        )

        push!(apps, metadata)
    end

    @info "TXT import complete" apps_count=length(apps)
    return apps
end

"""
    save_to_file(data::String, filepath::String)

    Save data to file. Used for report exports.

    Requires FILE_WRITE consent (checked by caller).
    GDPR: Recording processing type.
"""
function save_to_file(data::String, filepath::String)
    try
        # Create parent directory if needed
        dir = dirname(filepath)
        if !isempty(dir) && !isdir(dir)
            mkpath(dir)
        end

        write(filepath, data)
        @info "Data saved to file" path=filepath size=length(data)
        return true
    catch e
        @error "Failed to save file" exception=e path=filepath
        return false
    end
end

"""
    detect_format(filepath::String)

    Auto-detect file format from extension.
"""
function detect_format(filepath::String)
    ext = lowercase(split(filepath, '.')[end])

    mapping = Dict(
        "csv" => CSV,
        "json" => JSON,
        "txt" => TXT,
        "xlsx" => XLSX,
        "md" => MARKDOWN,
        "markdown" => MARKDOWN,
        "html" => HTML,
        "htm" => HTML
    )

    return get(mapping, ext, TXT)
end

"""
    batch_import(filepaths::Vector{String})

    Import from multiple files at once.
    Detects format automatically.

    Returns: Combined vector of all imported apps.
"""
function batch_import(filepaths::Vector{String})
    all_apps = []

    for filepath in filepaths
        format = detect_format(filepath)
        apps = import_from_file(filepath, format)
        append!(all_apps, apps)
    end

    @info "Batch import complete" total_apps=length(all_apps) files=length(filepaths)
    return all_apps
end

end # module IO
