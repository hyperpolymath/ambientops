"""
    Reports.jl - Report Generation for Juisys

    Generates audit reports in multiple formats:
    - Markdown (human-readable)
    - XLSX (spreadsheet analysis)
    - CSV (data export)
    - JSON (machine-readable)
    - HTML (web viewing)

    All reports contain:
    - App classifications
    - Risk assessments
    - FOSS alternatives
    - Cost savings analysis
    - Privacy recommendations

    PRIVACY: Reports contain audit data chosen by user.
    User controls what gets written to disk via FILE_WRITE consent.

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module Reports

export generate_report, ReportFormat
export markdown_report, csv_report, json_report, html_report
export summary_stats, cost_analysis

using JSON3
using Dates

@enum ReportFormat MARKDOWN CSV JSON HTML XLSX

"""
    generate_report(results::Vector, format::ReportFormat, output_path::String)

    Generate audit report in specified format.

    NOTE: Requires FILE_WRITE consent (caller must check).
"""
function generate_report(results::Vector, format::ReportFormat, output_path::String)
    try
        content = if format == MARKDOWN
            markdown_report(results)
        elseif format == CSV
            csv_report(results)
        elseif format == JSON
            json_report(results)
        elseif format == HTML
            html_report(results)
        else  # XLSX
            xlsx_report(results)
        end

        # Write to file
        write(output_path, content)
        @info "Report generated" format=format path=output_path size=length(content)
        return true

    catch e
        @error "Report generation failed" exception=e
        return false
    end
end

"""
    markdown_report(results::Vector)

    Generate Markdown format report.
"""
function markdown_report(results::Vector)
    io = IOBuffer()

    println(io, "# Juisys Application Audit Report")
    println(io, "")
    println(io, "**Generated:** $(now())")
    println(io, "**Total Applications:** $(length(results))")
    println(io, "")

    # Summary statistics
    stats = summary_stats(results)
    println(io, "## Summary")
    println(io, "")
    println(io, "- **High Risk:** $(stats[:high_risk])")
    println(io, "- **Medium Risk:** $(stats[:medium_risk])")
    println(io, "- **Low Risk:** $(stats[:low_risk])")
    println(io, "- **No Risk:** $(stats[:no_risk])")
    println(io, "- **Total Cost:** \$$(round(stats[:total_cost], digits=2))")
    println(io, "- **Potential Savings:** \$$(round(stats[:potential_savings], digits=2))")
    println(io, "")

    # Individual app reports
    println(io, "## Application Details")
    println(io, "")

    for (idx, result) in enumerate(results)
        println(io, "### $(idx). $(result[:app_name])")
        println(io, "")
        println(io, "- **Category:** $(result[:category])")
        println(io, "- **Risk Level:** $(result[:risk_level])")
        println(io, "- **Privacy Score:** $(round(result[:privacy_score] * 100, digits=1))%")
        println(io, "- **Cost:** \$$(result[:cost])")
        println(io, "")

        if !isempty(result[:alternatives])
            println(io, "**FOSS Alternatives:**")
            for alt in result[:alternatives]
                println(io, "- $(alt)")
            end
            println(io, "")
        end

        if !isempty(result[:recommendations])
            println(io, "**Recommendations:**")
            for rec in result[:recommendations]
                println(io, "- $(rec)")
            end
            println(io, "")
        end

        println(io, "---")
        println(io, "")
    end

    # Footer
    println(io, "## About Juisys")
    println(io, "")
    println(io, "Juisys is a privacy-first, GDPR-compliant tool for auditing installed applications.")
    println(io, "100% local processing, no telemetry, ephemeral data only.")
    println(io, "")
    println(io, "Generated with Juisys - Julia System Optimizer")

    return String(take!(io))
end

"""
    csv_report(results::Vector)

    Generate CSV format report.
"""
function csv_report(results::Vector)
    io = IOBuffer()

    # Header
    println(io, "App Name,Category,Risk Level,Privacy Score,Cost,FOSS Alternatives,Has Telemetry,Collects PII")

    for result in results
        name = result[:app_name]
        category = result[:category]
        risk = result[:risk_level]
        privacy = round(result[:privacy_score] * 100, digits=1)
        cost = result[:cost]
        alternatives = join(result[:alternatives], ";")
        telemetry = get(result, :has_telemetry, false)
        pii = get(result, :collects_pii, false)

        println(io, "\"$name\",\"$category\",\"$risk\",$privacy,$cost,\"$alternatives\",$telemetry,$pii")
    end

    return String(take!(io))
end

"""
    json_report(results::Vector)

    Generate JSON format report.
"""
function json_report(results::Vector)
    report = Dict(
        "generated_at" => string(now()),
        "summary" => summary_stats(results),
        "applications" => results
    )

    return JSON3.write(report, allow_inf=true)
end

"""
    html_report(results::Vector)

    Generate HTML format report with styling.
"""
function html_report(results::Vector)
    io = IOBuffer()

    stats = summary_stats(results)

    println(io, "<!DOCTYPE html>")
    println(io, "<html lang=\"en\">")
    println(io, "<head>")
    println(io, "    <meta charset=\"UTF-8\">")
    println(io, "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">")
    println(io, "    <title>Juisys Audit Report</title>")
    println(io, "    <style>")
    println(io, "        body { font-family: Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }")
    println(io, "        h1 { color: #333; }")
    println(io, "        .summary { background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; }")
    println(io, "        .app { border: 1px solid #ddd; margin: 20px 0; padding: 15px; border-radius: 5px; }")
    println(io, "        .risk-high { border-left: 5px solid #d32f2f; }")
    println(io, "        .risk-medium { border-left: 5px solid #f57c00; }")
    println(io, "        .risk-low { border-left: 5px solid #fbc02d; }")
    println(io, "        .risk-none { border-left: 5px solid #388e3c; }")
    println(io, "        .alternatives { background: #e8f5e9; padding: 10px; margin: 10px 0; border-radius: 4px; }")
    println(io, "        .recommendations { background: #fff3e0; padding: 10px; margin: 10px 0; border-radius: 4px; }")
    println(io, "    </style>")
    println(io, "</head>")
    println(io, "<body>")

    # Header
    println(io, "    <h1>🔍 Juisys Application Audit Report</h1>")
    println(io, "    <p><strong>Generated:</strong> $(now())</p>")

    # Summary
    println(io, "    <div class=\"summary\">")
    println(io, "        <h2>Summary</h2>")
    println(io, "        <p><strong>Total Applications:</strong> $(length(results))</p>")
    println(io, "        <p><strong>High Risk:</strong> $(stats[:high_risk]) | ")
    println(io, "           <strong>Medium:</strong> $(stats[:medium_risk]) | ")
    println(io, "           <strong>Low:</strong> $(stats[:low_risk]) | ")
    println(io, "           <strong>None:</strong> $(stats[:no_risk])</p>")
    println(io, "        <p><strong>Total Cost:</strong> \$$(round(stats[:total_cost], digits=2))</p>")
    println(io, "        <p><strong>Potential Savings:</strong> \$$(round(stats[:potential_savings], digits=2))</p>")
    println(io, "    </div>")

    # Applications
    for result in results
        risk_class = "risk-" * lowercase(string(result[:risk_level]))

        println(io, "    <div class=\"app $risk_class\">")
        println(io, "        <h3>$(result[:app_name])</h3>")
        println(io, "        <p><strong>Category:</strong> $(result[:category])</p>")
        println(io, "        <p><strong>Risk Level:</strong> $(result[:risk_level])</p>")
        println(io, "        <p><strong>Privacy Score:</strong> $(round(result[:privacy_score] * 100, digits=1))%</p>")
        println(io, "        <p><strong>Cost:</strong> \$$(result[:cost])</p>")

        if !isempty(result[:alternatives])
            println(io, "        <div class=\"alternatives\">")
            println(io, "            <strong>✓ FOSS Alternatives:</strong>")
            println(io, "            <ul>")
            for alt in result[:alternatives]
                println(io, "                <li>$(alt)</li>")
            end
            println(io, "            </ul>")
            println(io, "        </div>")
        end

        if !isempty(result[:recommendations])
            println(io, "        <div class=\"recommendations\">")
            println(io, "            <strong>📋 Recommendations:</strong>")
            println(io, "            <ul>")
            for rec in result[:recommendations]
                println(io, "                <li>$(rec)</li>")
            end
            println(io, "            </ul>")
            println(io, "        </div>")
        end

        println(io, "    </div>")
    end

    # Footer
    println(io, "    <hr>")
    println(io, "    <p><em>Generated with Juisys - Privacy-first GDPR-compliant application auditing</em></p>")
    println(io, "</body>")
    println(io, "</html>")

    return String(take!(io))
end

"""
    xlsx_report(results::Vector)

    Generate XLSX format report (requires XLSX.jl package).
    Placeholder - returns CSV if XLSX.jl not available.
"""
function xlsx_report(results::Vector)
    # This would use XLSX.jl in production
    # Fallback to CSV for now
    @warn "XLSX generation requires XLSX.jl package, falling back to CSV"
    return csv_report(results)
end

"""
    summary_stats(results::Vector)

    Calculate summary statistics from results.
"""
function summary_stats(results::Vector)
    high_risk = count(r -> string(r[:risk_level]) in ["HIGH", "CRITICAL"], results)
    medium_risk = count(r -> r[:risk_level] == "MEDIUM", results)
    low_risk = count(r -> r[:risk_level] == "LOW", results)
    no_risk = count(r -> r[:risk_level] == "NONE", results)

    total_cost = sum(r -> get(r, :cost, 0.0), results)

    # Estimate savings (apps with alternatives could save their cost)
    potential_savings = sum(results) do r
        if !isempty(get(r, :alternatives, []))
            get(r, :cost, 0.0)
        else
            0.0
        end
    end

    return Dict(
        :total_apps => length(results),
        :high_risk => high_risk,
        :medium_risk => medium_risk,
        :low_risk => low_risk,
        :no_risk => no_risk,
        :total_cost => total_cost,
        :potential_savings => potential_savings
    )
end

"""
    cost_analysis(results::Vector)

    Detailed cost analysis breakdown.
"""
function cost_analysis(results::Vector)
    analysis = Dict(
        "total_current_cost" => 0.0,
        "total_foss_cost" => 0.0,  # Always 0 for FOSS
        "savings" => 0.0,
        "by_category" => Dict()
    )

    for result in results
        cost = get(result, :cost, 0.0)
        category = get(result, :category, "other")
        has_alternatives = !isempty(get(result, :alternatives, []))

        analysis["total_current_cost"] += cost

        if has_alternatives
            analysis["savings"] += cost
        end

        # By category
        if !haskey(analysis["by_category"], category)
            analysis["by_category"][category] = Dict(
                "count" => 0,
                "cost" => 0.0,
                "savings" => 0.0
            )
        end

        analysis["by_category"][category]["count"] += 1
        analysis["by_category"][category]["cost"] += cost

        if has_alternatives
            analysis["by_category"][category]["savings"] += cost
        end
    end

    return analysis
end

end # module Reports
