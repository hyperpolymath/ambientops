#!/usr/bin/env julia

"""
    generate_html_report.jl - HTML Report Generator

    Generates beautiful, interactive HTML reports for Juisys database analysis.
    Perfect for presentations, stakeholder reports, and documentation.

    Usage: julia --project=. tools/generate_html_report.jl [output.html]
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

function generate_css()
    return """
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-radius: 8px;
        }

        h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
            border-bottom: 4px solid #3498db;
            padding-bottom: 15px;
        }

        h2 {
            color: #34495e;
            font-size: 1.8em;
            margin-top: 40px;
            margin-bottom: 20px;
            border-left: 5px solid #3498db;
            padding-left: 15px;
        }

        h3 {
            color: #555;
            font-size: 1.3em;
            margin-top: 25px;
            margin-bottom: 15px;
        }

        .meta {
            color: #7f8c8d;
            font-size: 0.9em;
            margin-bottom: 30px;
        }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }

        .summary-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        .summary-card.green {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }

        .summary-card.orange {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }

        .summary-card.blue {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
        }

        .summary-card h3 {
            font-size: 1.1em;
            margin: 0 0 10px 0;
            color: rgba(255,255,255,0.9);
        }

        .summary-card .value {
            font-size: 2.5em;
            font-weight: bold;
            color: white;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }

        th {
            background: #3498db;
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }

        td {
            padding: 12px 15px;
            border-bottom: 1px solid #ecf0f1;
        }

        tr:hover {
            background: #f8f9fa;
        }

        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
            color: white;
        }

        .badge.critical { background: #e74c3c; }
        .badge.high { background: #e67e22; }
        .badge.medium { background: #f39c12; }
        .badge.low { background: #95a5a6; }

        .badge.easy { background: #27ae60; }
        .badge.moderate { background: #f39c12; }
        .badge.hard { background: #e74c3c; }

        .progress-bar {
            width: 100%;
            height: 25px;
            background: #ecf0f1;
            border-radius: 12px;
            overflow: hidden;
            margin: 10px 0;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #11998e 0%, #38ef7d 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 0.85em;
        }

        .chart-bar {
            display: flex;
            align-items: center;
            margin: 15px 0;
        }

        .chart-label {
            width: 150px;
            font-weight: 600;
            color: #555;
        }

        .chart-fill {
            flex: 1;
            height: 30px;
            background: #3498db;
            margin: 0 15px;
            border-radius: 5px;
            position: relative;
            transition: width 0.3s ease;
        }

        .chart-value {
            font-weight: bold;
            color: #333;
            min-width: 60px;
        }

        .alternatives-list {
            list-style: none;
            padding: 0;
        }

        .alternatives-list li {
            padding: 8px 0;
            padding-left: 25px;
            position: relative;
        }

        .alternatives-list li:before {
            content: "✓";
            position: absolute;
            left: 0;
            color: #27ae60;
            font-weight: bold;
        }

        .footer {
            margin-top: 50px;
            padding-top: 20px;
            border-top: 2px solid #ecf0f1;
            text-align: center;
            color: #7f8c8d;
            font-size: 0.9em;
        }

        @media print {
            body { background: white; padding: 0; }
            .container { box-shadow: none; }
            .summary-card { break-inside: avoid; }
            table { page-break-inside: avoid; }
        }
    </style>
    """
end

function generate_summary_cards(apps)
    total_apps = length(apps)
    total_savings = sum([app[:cost_savings] for app in apps])
    avg_parity = sum([app[:feature_parity] for app in apps]) / total_apps * 100
    critical_privacy = count(app -> app[:privacy_benefit] == "critical", apps)

    return """
    <div class="summary-grid">
        <div class="summary-card">
            <h3>Applications Analyzed</h3>
            <div class="value">$total_apps</div>
        </div>
        <div class="summary-card green">
            <h3>Annual Savings Potential</h3>
            <div class="value">\$$(round(total_savings, digits=0))</div>
        </div>
        <div class="summary-card orange">
            <h3>Average Feature Parity</h3>
            <div class="value">$(round(avg_parity, digits=0))%</div>
        </div>
        <div class="summary-card blue">
            <h3>Critical Privacy Benefits</h3>
            <div class="value">$critical_privacy</div>
        </div>
    </div>
    """
end

function generate_category_chart(apps)
    by_category = Dict{String, Int}()
    for app in apps
        cat = app[:category]
        by_category[cat] = get(by_category, cat, 0) + 1
    end

    sorted_cats = sort(collect(by_category), by=x->x[2], rev=true)
    max_count = maximum([count for (_, count) in sorted_cats])

    html = "<h3>Applications by Category</h3>\n"

    for (cat, count) in sorted_cats
        width_pct = (count / max_count) * 100
        html *= """
        <div class="chart-bar">
            <div class="chart-label">$(uppercase(cat))</div>
            <div class="chart-fill" style="width: $(width_pct)%"></div>
            <div class="chart-value">$count apps</div>
        </div>
        """
    end

    return html
end

function generate_top_savings_table(apps)
    sorted_apps = sort(apps, by=x->x[:cost_savings], rev=true)
    top_10 = sorted_apps[1:min(10, length(sorted_apps))]

    html = """
    <h3>Top 10 Cost Savings Opportunities</h3>
    <table>
        <thead>
            <tr>
                <th>Rank</th>
                <th>Proprietary App</th>
                <th>FOSS Alternative</th>
                <th>Annual Savings</th>
                <th>Feature Parity</th>
                <th>Migration Effort</th>
            </tr>
        </thead>
        <tbody>
    """

    for (i, app) in enumerate(top_10)
        savings = app[:cost_savings]
        parity = app[:feature_parity] * 100
        alt = app[:foss_alternatives][1]
        effort = app[:migration_effort]
        effort_class = effort == "low" ? "easy" : (effort == "high" ? "hard" : "moderate")

        html *= """
        <tr>
            <td><strong>$i</strong></td>
            <td>$(app[:proprietary_name])</td>
            <td>$alt</td>
            <td><strong>\$$(round(savings, digits=2))</strong></td>
            <td>
                <div class="progress-bar" style="width: 150px;">
                    <div class="progress-fill" style="width: $(parity)%">$(round(parity, digits=0))%</div>
                </div>
            </td>
            <td><span class="badge $effort_class">$(uppercase(effort))</span></td>
        </tr>
        """
    end

    html *= """
        </tbody>
    </table>
    """

    return html
end

function generate_privacy_analysis(apps)
    critical = filter(app -> app[:privacy_benefit] == "critical", apps)
    high = filter(app -> app[:privacy_benefit] == "high", apps)

    html = """
    <h3>Privacy-Critical Applications</h3>
    <p>These applications have the highest privacy benefits when switching to FOSS alternatives:</p>
    <table>
        <thead>
            <tr>
                <th>Proprietary App</th>
                <th>FOSS Alternatives</th>
                <th>Privacy Benefit</th>
                <th>Category</th>
            </tr>
        </thead>
        <tbody>
    """

    for app in vcat(critical, high)[1:min(15, length(vcat(critical, high)))]
        benefit = app[:privacy_benefit]
        badge_class = benefit == "critical" ? "critical" : "high"
        alts = join(app[:foss_alternatives], ", ")

        html *= """
        <tr>
            <td><strong>$(app[:proprietary_name])</strong></td>
            <td>$alts</td>
            <td><span class="badge $badge_class">$(uppercase(benefit))</span></td>
            <td>$(app[:category])</td>
        </tr>
        """
    end

    html *= """
        </tbody>
    </table>
    """

    return html
end

function generate_quick_wins_section(apps)
    quick_wins = filter(app -> app[:migration_effort] == "low" &&
                              app[:feature_parity] >= 0.85 &&
                              app[:cost_savings] > 0, apps)

    sorted_wins = sort(quick_wins, by=x->x[:cost_savings], rev=true)

    html = """
    <h3>Quick Wins (Easy Migration + High Parity)</h3>
    <p>These applications are ideal for immediate migration with minimal effort and strong feature coverage:</p>
    <table>
        <thead>
            <tr>
                <th>Proprietary App</th>
                <th>Recommended FOSS</th>
                <th>Annual Savings</th>
                <th>Feature Parity</th>
                <th>Learning Curve</th>
            </tr>
        </thead>
        <tbody>
    """

    for app in sorted_wins[1:min(10, length(sorted_wins))]
        parity = app[:feature_parity] * 100
        learning = app[:learning_curve]
        learning_class = learning == "easy" ? "easy" : (learning == "high" ? "hard" : "moderate")

        html *= """
        <tr>
            <td><strong>$(app[:proprietary_name])</strong></td>
            <td>$(app[:foss_alternatives][1])</td>
            <td>\$$(round(app[:cost_savings], digits=2))</td>
            <td>$(round(parity, digits=0))%</td>
            <td><span class="badge $learning_class">$(uppercase(learning))</span></td>
        </tr>
        """
    end

    html *= """
        </tbody>
    </table>
    """

    return html
end

function generate_html_report(apps, rules)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")

    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Juisys Database Analysis Report</title>
        $(generate_css())
    </head>
    <body>
        <div class="container">
            <h1>📊 Juisys Database Analysis Report</h1>
            <div class="meta">
                Generated: $timestamp<br>
                Database Version: 1.0.0<br>
                Privacy-First | GDPR Compliant | 100% Local Processing
            </div>

            <h2>Executive Summary</h2>
            $(generate_summary_cards(apps))

            <h2>Database Overview</h2>
            $(generate_category_chart(apps))

            <h2>Cost Savings Analysis</h2>
            $(generate_top_savings_table(apps))

            <h2>Privacy & Security</h2>
            $(generate_privacy_analysis(apps))

            <h2>Migration Strategy</h2>
            $(generate_quick_wins_section(apps))

            <h2>Methodology</h2>
            <p>
                This report analyzes $(length(apps)) proprietary applications and their FOSS (Free and Open Source)
                alternatives across multiple dimensions:
            </p>
            <ul>
                <li><strong>Feature Parity:</strong> How well FOSS alternatives match proprietary features (0-100%)</li>
                <li><strong>Cost Savings:</strong> Annual subscription/license fees that can be eliminated</li>
                <li><strong>Privacy Benefit:</strong> Reduction in tracking, telemetry, and data collection (Low/Medium/High/Critical)</li>
                <li><strong>Migration Effort:</strong> Complexity of switching to FOSS alternative (Low/Medium/High)</li>
                <li><strong>Learning Curve:</strong> Time required to become proficient (Easy/Medium/High)</li>
            </ul>

            <h2>Privacy Guarantees</h2>
            <p>
                All Juisys tools, including this report generator, maintain strict privacy standards:
            </p>
            <ul>
                <li>✓ <strong>100% Local Processing</strong> - No network calls, no telemetry</li>
                <li>✓ <strong>Ephemeral Data Only</strong> - All processing in-memory, cleared after session</li>
                <li>✓ <strong>No Personal Data Collection</strong> - Analyzes application metadata only</li>
                <li>✓ <strong>Open Source</strong> - Fully auditable codebase</li>
                <li>✓ <strong>GDPR Compliant</strong> - Implements all 12 GDPR processing types</li>
            </ul>

            <h2>Next Steps</h2>
            <ol>
                <li>Review the <strong>Quick Wins</strong> section for easy migration opportunities</li>
                <li>Use the Migration Planner tool for personalized recommendations: <code>julia tools/migration_planner.jl</code></li>
                <li>Compare specific applications in detail: <code>julia tools/compare_alternatives.jl [app_name]</code></li>
                <li>Start with Phase 1 migrations (low effort, high value)</li>
                <li>Track progress and update this report periodically</li>
            </ol>

            <div class="footer">
                <p>
                    Generated by <strong>Juisys</strong> - Privacy-First GDPR-Compliant Application Auditing<br>
                    © 2025 | MIT License | Developed with Claude Sonnet 4.5
                </p>
            </div>
        </div>
    </body>
    </html>
    """

    return html
end

function main()
    println("\n" * "="^70)
    println("JUISYS HTML REPORT GENERATOR")
    println("="^70)
    println()

    # Load databases
    println("Loading databases...")
    apps, rules = load_databases()
    println("✓ Loaded $(length(apps)) applications")
    println()

    # Generate report
    println("Generating HTML report...")
    html = generate_html_report(apps, rules)

    # Determine output path
    output_path = if length(ARGS) > 0
        ARGS[1]
    else
        timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
        "juisys_report_$timestamp.html"
    end

    # Ensure .html extension
    if !endswith(output_path, ".html")
        output_path *= ".html"
    end

    # Write report
    open(output_path, "w") do f
        write(f, html)
    end

    file_size = filesize(output_path)

    println("✓ Report generated successfully!")
    println()
    println("Output file: $output_path")
    println("File size: $(round(file_size / 1024, digits=2)) KB")
    println()
    println("To view:")
    println("  • Open in browser: file://$(abspath(output_path))")
    println("  • Or: open $output_path")
    println()

    println("="^70)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
