# Juisys Tutorial - Step-by-Step Guide

Welcome to Juisys! This tutorial will guide you through using the privacy-first application auditing tool.

---

## Table of Contents

1. [Installation](#installation)
2. [First Run - NO PEEK Mode](#first-run---no-peek-mode)
3. [Full System Audit](#full-system-audit)
4. [Understanding Results](#understanding-results)
5. [Generating Reports](#generating-reports)
6. [Finding Alternatives](#finding-alternatives)
7. [Privacy Self-Audit](#privacy-self-audit)
8. [Advanced Usage](#advanced-usage)

---

## Installation

### Prerequisites

1. **Install Julia** (version 1.6 or later)
   - Download from: https://julialang.org/downloads/
   - Follow installation instructions for your platform

2. **Verify Julia installation**
   ```bash
   julia --version
   # Should output: julia version 1.6.x (or later)
   ```

### Get Juisys

```bash
# Clone the repository
git clone https://github.com/your-org/jusys.git
cd jusys

# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

---

## First Run - NO PEEK Mode

**NO PEEK mode** is the safest way to use Juisys. It requires NO system access and NO permissions.

### Why Start with NO PEEK?

- ✅ Maximum privacy
- ✅ No consent required
- ✅ Works on any system
- ✅ Perfect for sensitive environments
- ✅ Complete control over data

### Running NO PEEK Mode

```bash
julia --project=. -e 'include("src/cli.jl"); using .CLI; CLI.run()'
```

Then select option **1** from the menu.

### Example Session

```
JUISYS - Julia System Optimizer
Privacy-First GDPR-Compliant Application Auditing

PRIVACY NOTICE:
- 100% local processing, no network calls
- All data ephemeral (cleared after session)
- Explicit consent required for system access
- Self-audit available (Mode 6)

──────────────────────────────────────────────────────────────────────
MAIN MENU
──────────────────────────────────────────────────────────────────────

  1. NO PEEK Mode      - Manual entry (maximum privacy)
  ...

Enter choice [0-9]: 1

======================================================================
NO PEEK MODE - Maximum Privacy
======================================================================
Manually enter application details.
NO system access required. NO consent needed.

Add an application? [y/N]: y
App name: Adobe Photoshop
✓ Added: Adobe Photoshop

Add an application? [y/N]: n

1 application(s) entered.
```

---

## Full System Audit

Once you're comfortable, try a full audit with automatic scanning.

### Step 1: Launch Juisys

```bash
julia --project=. -e 'include("src/cli.jl"); using .CLI; CLI.run()'
```

### Step 2: Select FULL AUDIT

Choose option **3** from the main menu.

### Step 3: Grant Consent

Juisys will request permission to:
1. Scan installed packages (SYSTEM_SCAN)
2. Access package manager (PACKAGE_MANAGER)

Example consent request:
```
======================================================================
CONSENT REQUEST (GDPR Article 6.1.a)
======================================================================
Juisys requests permission to perform the following operation:

  Operation: Scan installed applications
  Purpose:   To audit installed software for privacy/cost analysis
  Duration:  This session only
  Data:      Ephemeral (cleared after session)

This is required for the requested functionality.
You can revoke consent at any time.
======================================================================
Grant consent? [y/N]: y

✓ Consent granted
```

### Step 4: Review Results

Juisys will:
1. Detect your package manager (winget/apt/dnf/brew/etc.)
2. Scan installed applications
3. Classify each app by privacy/cost risk
4. Find FOSS alternatives
5. Calculate potential savings
6. Display colored summary

---

## Understanding Results

### Risk Levels

Juisys classifies applications into 5 risk levels:

| Level | Color | Meaning |
|-------|-------|---------|
| **NONE** | 🟢 Green | No identified privacy/cost concerns |
| **LOW** | 🟡 Yellow | Minor privacy concerns or low cost |
| **MEDIUM** | 🟠 Orange | Moderate privacy/cost concerns |
| **HIGH** | 🔴 Red | Significant privacy risks or high cost |
| **CRITICAL** | 🟣 Purple | Severe privacy violations and/or very high cost |

### Privacy Score

Ranges from 0% (worst) to 100% (best).

Factors:
- **-40%**: Shares data with third parties
- **-30%**: Collects personally identifiable information
- **-20%**: Has telemetry/tracking
- **-10%**: Requires account
- **-10%**: Shows advertisements
- **+30%**: Free/Open Source Software

### Example Result

```
1. Adobe Photoshop

   Risk: HIGH
   Privacy Score: 45.0%
   Cost: $239.88

   FOSS Alternatives:
   - GIMP
   - Krita
   - Photopea

   Recommendations:
   - ⚠️ CRITICAL: Consider immediate replacement with privacy-respecting alternative
   - Data sharing detected - review privacy policy carefully
   - High cost - evaluate if FOSS alternatives meet your needs
```

---

## Generating Reports

### Export Audit Results

From main menu, select option **5** (Export Report).

### Available Formats

1. **Markdown** (.md) - Human-readable, great for documentation
2. **CSV** (.csv) - Spreadsheet import, data analysis
3. **JSON** (.json) - Machine-readable, integration
4. **HTML** (.html) - Web viewing, sharing
5. **XLSX** (.xlsx) - Excel analysis (requires XLSX.jl)

### Example Export

```
EXPORT REPORT
══════════════════════════════════════════════════════════════════════
Generate audit report in various formats.

Available formats:
  1. Markdown (.md)
  2. CSV (.csv)
  3. JSON (.json)
  4. HTML (.html)
  5. XLSX (.xlsx)

Select format [1-5]: 1
Enter output path: ~/juisys-audit-2025.md

⚠️  This requires FILE_WRITE consent.
Proceed? [y/N]: y

Exporting to: ~/juisys-audit-2025.md
✓ Report generated successfully
```

### Sample HTML Report

HTML reports include:
- Color-coded risk visualization
- Interactive layout
- Summary statistics
- Cost analysis
- Alternative suggestions
- Professional styling

Perfect for sharing with team or management!

---

## Finding Alternatives

### Browse FOSS Alternatives Database

From main menu, select option **7** (View Alternatives).

```
VIEW FOSS ALTERNATIVES
══════════════════════════════════════════════════════════════════════

Enter application name to find alternatives: Microsoft Office

Searching for alternatives to: Microsoft Office

Found 3 alternatives:

📦 LibreOffice
   Category: productivity
   License: MPL (Mozilla Public License)
   Platforms: Windows, macOS, Linux

   Feature Parity: 92.0%
   Learning Curve: easy
   Maturity: mature
   Privacy Improvement: high
   Annual Savings: $149.99

   Migration Tips:
   1. Export your data from Microsoft Office before switching
   2. Install LibreOffice and explore the interface
   3. Import your data into LibreOffice
   4. LibreOffice is user-friendly - you should adapt quickly
   5. Great news: LibreOffice has excellent feature parity
   6. Significant privacy improvement - no telemetry or data collection
   7. Strong community support available for LibreOffice

📦 OnlyOffice
   ...

📦 Apache OpenOffice
   ...
```

### Adding Your Own Alternatives

Edit `data/app_db.json`:

```json
{
  "proprietary_name": "Your App",
  "foss_alternatives": ["Alternative 1", "Alternative 2"],
  "category": "productivity",
  "cost_savings": 99.00,
  "privacy_benefit": "high",
  "feature_parity": 0.85,
  "learning_curve": "medium",
  "platforms": ["Windows", "macOS", "Linux"]
}
```

---

## Privacy Self-Audit

### Verify Juisys Privacy Compliance

This is a unique transparency feature - Juisys audits itself!

From main menu, select option **6** (Self-Audit).

```
SELF-AUDIT - Privacy Compliance Check
══════════════════════════════════════════════════════════════════════
Juisys will audit its own code for privacy compliance.

Running self-audit...

JUISYS PRIVACY SELF-AUDIT REPORT
══════════════════════════════════════════════════════════════════════
Generated: 2025-11-22T01:30:00

GDPR COMPLIANCE CHECKS:
──────────────────────────────────────────────────────────────────────
✓ Network Calls Check
  ✓ No network calls found in codebase
  Severity: info

✓ Ephemeral Storage Check
  ✓ No persistent personal data storage found
  Severity: info

✓ Consent Checks
  ✓ Consent framework implemented in security.jl
  Severity: info

✓ Secrets Check
  ✓ No hardcoded secrets detected
  Severity: info

──────────────────────────────────────────────────────────────────────
SUMMARY: 4/4 checks passed
✓ COMPLIANT: All privacy checks passed
══════════════════════════════════════════════════════════════════════
```

---

## Advanced Usage

### Import from File

For air-gapped systems or batch processing:

```bash
# Create app list file (apps.txt)
Adobe Photoshop
Microsoft Office
Slack
Zoom
```

Then from main menu, select option **4** (Import from File).

Supported formats:
- **TXT**: One app per line
- **CSV**: Structured data with headers
- **JSON**: Full metadata

### Programmatic Usage

Use Juisys modules directly in your Julia code:

```julia
# Load modules
include("src/core.jl")
include("src/alternatives.jl")

using .Core
using .Alternatives

# Classify an app
rules = Core.load_rules("data/rules.json")
result = Core.classify_app("Slack", rules)

println("Risk: $(result.risk_level)")
println("Privacy Score: $(result.privacy_score * 100)%")

# Find alternatives
alternatives = Alternatives.find_alternatives("Slack", "data/app_db.json")

for alt in alternatives
    println("Alternative: $(alt.name)")
    println("  Savings: \$$(alt.cost_savings_annual)")
end
```

### Custom Classification Rules

Edit `data/rules.json` to customize:
- Category keywords
- Risk flag patterns
- Cost thresholds
- Privacy weights

### Ambient Mode Configuration

Enable multi-modal feedback:

```julia
include("src/ambient.jl")
using .Ambient

# Visual + Audio + IoT
mode = Ambient.ALL

# Trigger feedback for high-risk app
Ambient.trigger_feedback("HIGH", mode, message="Privacy concern detected")
```

---

## Tips & Best Practices

### Privacy Tips

1. **Start with NO PEEK** - Get comfortable before granting system access
2. **Review consent requests** - Understand what you're authorizing
3. **Run self-audit regularly** - Verify Juisys maintains compliance
4. **Inspect source code** - Everything is open for review

### Workflow Tips

1. **Quick Scan first** - Get overview before full audit
2. **Export reports** - Keep records of findings
3. **Evaluate alternatives gradually** - Don't switch everything at once
4. **Test FOSS alternatives** - Run parallel before full migration

### Data Management

1. **Reports are optional** - Only generate if you need permanent record
2. **Data is ephemeral** - Automatically cleared after session
3. **No history tracking** - Each audit is independent
4. **Import for air-gap** - Use file import for isolated systems

---

## Troubleshooting

### Package Manager Not Detected

**Problem**: Juisys can't find package manager

**Solution**: Use NO PEEK mode (manual entry) or Import mode

### GTK Not Available

**Problem**: GUI mode fails to load

**Solution**: Install GTK.jl or use CLI mode
```bash
julia --project=. -e 'using Pkg; Pkg.add("Gtk")'
```

### Permission Denied

**Problem**: Can't access package manager

**Solution**: Run with appropriate permissions or use NO PEEK mode

### Empty Results

**Problem**: No apps found after scan

**Solution**:
1. Verify package manager is installed
2. Check if you have apps installed via that package manager
3. Try different package manager or manual entry

---

## Next Steps

- Read [ETHICS.md](ETHICS.md) to understand GDPR implementation
- See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) for technical details
- Check [CONTRIBUTING.md](CONTRIBUTING.md) to contribute
- Explore `data/app_db.json` to add more alternatives

---

## Support

Questions? Issues?
- File an issue on GitHub
- Review documentation in `docs/`
- Check source code - it's educational!

**Remember**: Juisys is an educational tool demonstrating GDPR compliance. Learn from it and build privacy-respecting software!

---

**Happy auditing! 🔍**
