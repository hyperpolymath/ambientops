# Juisys Tools

Comprehensive utilities for database analysis, migration planning, and alternative comparison.

---

## Overview

This directory contains standalone tools that extend Juisys functionality with specialized features for power users, developers, and organizations planning large-scale migrations.

---

## Available Tools

### 1. Migration Planner (`migration_planner.jl`)

Interactive tool for creating personalized migration plans based on your priorities.

**Features:**
- Priority-based scoring (cost, privacy, ease, features, time)
- Phased migration planning (Quick Wins, Main Migration, Advanced)
- Personalized recommendations
- Export migration plans to JSON
- Category and app filtering

**Usage:**
```bash
julia --project=. tools/migration_planner.jl
```

**Interactive Flow:**
1. Define your priorities (1-10 scale)
2. Select applications to analyze
3. Review generated migration plan
4. Export plan for future reference

**Example Session:**
```
STEP 1: Define Your Priorities
  Cost savings: 8
  Privacy protection: 9
  Ease of migration: 7
  Feature completeness: 8
  Time investment: 6

STEP 2: Select Applications
  [Choose from 5 options: all apps, by category, specific apps, etc.]

STEP 3: Generating Migration Plan
  PHASE 1: Quick Wins (Weeks 1-4)
    1. WinRAR → 7-Zip (Score: 95%, Savings: $29/year)
    2. Evernote → Joplin (Score: 92%, Savings: $70/year)
    ...
```

**Output:**
- Phased migration timeline
- Cost-benefit analysis
- Risk assessment
- JSON export for tracking

---

### 2. Compare Alternatives (`compare_alternatives.jl`)

Side-by-side comparison tool for proprietary apps vs FOSS alternatives.

**Features:**
- Detailed feature parity analysis
- Privacy benefit breakdown
- Migration complexity assessment
- Cost-benefit calculations with ROI
- Platform support verification
- Star ratings and recommendations

**Usage:**

**Command-line mode:**
```bash
julia --project=. tools/compare_alternatives.jl "Photoshop"
julia --project=. tools/compare_alternatives.jl Office
```

**Interactive mode:**
```bash
julia --project=. tools/compare_alternatives.jl
> photoshop
> office
> list          # See all available apps
> quit
```

**Example Output:**
```
================================================================================
COMPARISON: Adobe Photoshop vs FOSS Alternatives
================================================================================

FOSS Alternatives:
  • GIMP
  • Krita
  • Photopea

FEATURE PARITY ANALYSIS
Overall Feature Parity: 85.0%
[██████████████████████████████████████████░░░░░]
Assessment: GOOD - FOSS alternatives cover most essential features

PRIVACY & SECURITY BENEFITS
Privacy Benefit Level: HIGH
✓ No telemetry or tracking
✓ No data collection for advertising
✓ Source code publicly auditable

COST-BENEFIT ANALYSIS
Annual Savings:        $239.88
5-Year Savings:        $1,199.40
10-Year Savings:       $2,398.80
Migration Time:        20 hours
Break-even Period:     4.2 months
First Year ROI:        24%

RECOMMENDATIONS
★★★★☆ RECOMMENDED
Action: Evaluate alternatives, plan migration
```

---

## Benchmarks

### Database Performance Benchmark (`benchmark_database.jl`)

Comprehensive performance testing suite for database operations.

**Tests:**
- Database loading (JSON parsing)
- Query performance (filtering, sorting)
- String operations (search, grouping)
- Scoring algorithms
- Memory usage analysis

**Usage:**
```bash
julia --project=. benchmarks/benchmark_database.jl
```

**Metrics Measured:**
- Average execution time (ms)
- Min/max times
- Throughput (operations per second)
- Memory footprint
- File sizes

**Example Output:**
```
PHASE 1: Database Loading Performance
──────────────────────────────────────────────────────────────────────
Load App Database (JSON parsing)
  Iterations:       1000
  Average Time:     0.523 ms
  Throughput:       1912 ops/sec

PHASE 2: Database Query Performance
──────────────────────────────────────────────────────────────────────
Complex Query (multi-criteria)
  Average Time:     0.089 ms
  Throughput:       11235 ops/sec

BENCHMARK SUMMARY
✓ EXCELLENT - All operations under 1ms average
```

---

## Integration with Core Juisys

These tools complement the main Juisys CLI:

**Core Juisys CLI:**
- NO PEEK Mode (manual entry)
- Quick Scan (package manager)
- FULL AUDIT (comprehensive)
- Self-Audit (privacy check)

**Tools Directory:**
- Migration planning (priority-based)
- Alternative comparison (detailed analysis)
- Performance benchmarking (developers)

---

## Installation

No additional installation required beyond Juisys core dependencies:

```bash
cd jusys
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

---

## Use Cases

### Individual Users

**Scenario 1: "I want to save money"**
```bash
julia tools/migration_planner.jl
# Set cost_savings priority to 9-10
# Review recommendations sorted by savings
```

**Scenario 2: "I'm concerned about privacy"**
```bash
julia tools/migration_planner.jl
# Set privacy priority to 10
# Focus on critical/high privacy apps
```

**Scenario 3: "Should I switch from Photoshop to GIMP?"**
```bash
julia tools/compare_alternatives.jl Photoshop
# Review feature parity (85%)
# Check migration effort (medium)
# See cost savings ($240/year)
```

### Organizations

**Scenario: "Plan department-wide migration"**
```bash
# 1. Analyze all productivity tools
julia tools/migration_planner.jl
> Select by category: productivity

# 2. Compare specific tools
julia tools/compare_alternatives.jl "Microsoft Office"

# 3. Export migration plan
# Plan saved to migration_plan_2025-11-22.json
```

**Scenario: "Performance validation"**
```bash
# Verify database scales with organizational app lists
julia benchmarks/benchmark_database.jl
# Review ops/sec for expected load
```

### Developers

**Scenario: "Extend Juisys functionality"**
```bash
# Study scoring algorithms
julia benchmarks/benchmark_database.jl

# Review example code
julia examples/example_advanced_analysis.jl

# Test new features
julia test/test_database.jl
```

---

## Output Formats

### Migration Plan JSON

```json
{
  "generated_at": "2025-11-22T02:30:00",
  "priorities": {
    "cost_savings": 0.25,
    "privacy": 0.30,
    "ease_of_migration": 0.20,
    "feature_completeness": 0.15,
    "time_investment": 0.10
  },
  "total_apps": 15,
  "total_savings": 1250.50,
  "apps": [
    {
      "proprietary": "Adobe Photoshop",
      "foss_alternative": "GIMP",
      "score": 0.85,
      "cost_savings": 239.88,
      "feature_parity": 0.85,
      "privacy_benefit": "high"
    }
  ]
}
```

### Benchmark Results JSON

```json
{
  "generated_at": "2025-11-22T02:35:00",
  "total_benchmarks": 18,
  "results": [
    {
      "name": "Load App Database",
      "iterations": 1000,
      "avg_time_ms": 0.523,
      "ops_per_second": 1912
    }
  ]
}
```

---

## Advanced Features

### Migration Planner Strategies

The migration planner supports different selection strategies:

**All Applications:**
- Complete portfolio analysis
- Total savings calculation
- Comprehensive timeline

**By Category:**
- Focus on specific app types
- Ideal for department-level planning
- Easier to coordinate team migrations

**Specific Applications:**
- Targeted analysis
- Quick evaluation
- Individual use cases

**High-Cost Applications:**
- Maximum ROI focus
- Budget-driven decisions
- Quick wins for cost reduction

**Privacy-Critical:**
- Security-first approach
- Compliance-driven (GDPR, etc.)
- Risk mitigation

### Scoring Algorithms

Both tools use sophisticated multi-factor scoring:

**Factors Weighted:**
1. Feature Parity (25%) - Does it do what you need?
2. Privacy Benefit (25%) - How much privacy do you gain?
3. Migration Ease (20%) - How hard is the switch?
4. Learning Curve (15%) - How quickly can you adapt?
5. Maturity (15%) - Is the FOSS alternative stable?

**Customizable:**
- Migration planner allows user-defined weights
- Compare alternatives uses balanced weights
- Both extensible for custom criteria

---

## Privacy Guarantees

All tools maintain Juisys privacy principles:

✅ **100% Local Processing** - No network calls
✅ **Ephemeral Data** - No persistent personal data
✅ **No Telemetry** - Zero tracking or analytics
✅ **Transparent** - Open source, auditable code

**Data Handling:**
- Reads: app_db.json, rules.json (static data)
- Writes: Optional exports (user-controlled)
- Network: NONE (completely offline)
- Logging: Console output only

---

## Development

### Creating New Tools

Template for new tools:

```julia
#!/usr/bin/env julia

push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using JSON3

function load_app_database()
    app_db_path = joinpath(@__DIR__, "..", "data", "app_db.json")
    return JSON3.read(read(app_db_path, String))
end

function main()
    apps = load_app_database()
    # Your tool logic here
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
```

**Best Practices:**
- Keep tools focused (single responsibility)
- Support both CLI and interactive modes
- Provide clear output formatting
- Include usage examples in comments
- Maintain privacy guarantees
- Add error handling

---

## Testing

Run tool tests:

```bash
# Test database integrity (includes tool data sources)
julia --project=. test/test_database.jl

# Benchmark performance
julia --project=. benchmarks/benchmark_database.jl

# Test specific tool manually
julia --project=. tools/migration_planner.jl
```

---

## Troubleshooting

### "File not found: app_db.json"

**Solution:**
```bash
# Ensure you're in the jusys directory
cd /path/to/jusys

# Run tools with --project flag
julia --project=. tools/migration_planner.jl
```

### "No applications found"

**Solution:**
```bash
# Verify database loaded correctly
julia --project=. -e 'using JSON3; apps = JSON3.read(read("data/app_db.json")); println(length(apps))'

# Should output: 62
```

### Performance Issues

**Check benchmarks:**
```bash
julia --project=. benchmarks/benchmark_database.jl
# Review ops/sec metrics
# Compare with expected performance
```

---

## Roadmap

Planned tool additions:

- [ ] **Team Collaboration Tool** - Multi-user migration coordination
- [ ] **Cost Tracker** - Real-time savings monitoring
- [ ] **Training Planner** - Learning resource recommendations
- [ ] **Data Migration Assistant** - File format conversion helpers
- [ ] **Compliance Checker** - GDPR/regulatory audit tool
- [ ] **Custom Scoring Tool** - Build your own scoring criteria

---

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development guidelines.

**Tool Development Checklist:**
- [ ] Follows privacy-first principles
- [ ] Includes usage documentation
- [ ] Provides example output
- [ ] Handles errors gracefully
- [ ] Supports both CLI and interactive modes
- [ ] Includes performance considerations
- [ ] Maintains consistent code style

---

## License

MIT License - Same as Juisys core

---

## Support

For issues or questions:
1. Check this README
2. Review tool source code comments
3. See [examples/](../examples/) directory
4. File issue on GitHub

---

**Last Updated:** 2025-11-22
**Tools Version:** 1.0.0
**Juisys Version:** 1.0.0
