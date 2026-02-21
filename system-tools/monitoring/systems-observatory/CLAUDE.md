# CLAUDE.md

This file provides context and guidelines for AI assistants (like Claude Code) working with the Juisys project.

## Project Overview

**Project Name:** Juisys (Julia System Optimizer)
**Repository:** Hyperpolymath/jusys
**Status:** Active development - Educational GDPR-compliant system auditing tool

### Description

Juisys is a privacy-first, GDPR-compliant tool for auditing and classifying installed applications on your system. It demonstrates GDPR principles, the Hazard Triangle methodology for risk management, and ambient computing concepts through a fully functional product. This is an educational tool built from comprehensive specifications that produces real-world value.

**Key Features:**
- **100% Local Processing** - No network calls, no telemetry, complete privacy
- **GDPR Compliant** - Implements all 12 GDPR processing types with explicit consent
- **Hazard Triangle** - ELIMINATE (NO PEEK mode), SUBSTITUTE (local JSON DB), CONTROL (consent + ephemeral storage)
- **Multi-Modal Interface** - CLI, GUI, ambient computing (visual/audio/IoT feedback)
- **Cross-Platform** - Supports winget, apt, dnf, brew package managers with graceful fallback

## Project Structure

```
jusys/
├── CLAUDE.md              # This file - AI assistant context
├── README.md              # Project overview and quick start
├── TUTORIAL.md            # Step-by-step user guide
├── ETHICS.md              # GDPR deep-dive and privacy principles
├── CONTRIBUTING.md        # Contribution guidelines
├── PROJECT_SUMMARY.md     # Complete technical overview
├── LICENSE                # MIT License
├── Project.toml           # Julia package configuration
├── .gitignore             # Git ignore patterns
├── .gitlab-ci.yml         # CI/CD pipeline
├── src/                   # Source code (Julia modules)
│   ├── cli.jl            # Menu-driven interface (9 modes)
│   ├── core.jl           # Classification engine
│   ├── security.jl       # GDPR consent & self-audit
│   ├── io.jl             # Manual/automated input, file I/O
│   ├── reports.jl        # XLSX/Markdown/CSV/JSON/HTML generation
│   ├── alternatives.jl   # FOSS suggestions & cost analysis
│   ├── automate.jl       # Safe system scanning
│   ├── ambient.jl        # GTK/audio/IoT feedback
│   ├── gui.jl            # Optional graphical interface
│   ├── config.jl         # Configuration management
│   ├── logging.jl        # Logging framework
│   ├── plugins.jl        # Plugin/extension system
│   ├── i18n.jl           # Internationalization
│   ├── scheduler.jl      # Automation & scheduling
│   └── web.jl            # Web dashboard interface
├── test/                  # Test suite
│   └── runtests.jl       # Main test runner
├── data/                  # Data files
│   ├── app_db.json       # App alternatives database (50+ entries)
│   ├── rules.json        # Classification rules & flags
│   └── locales/          # Translation files
├── examples/              # Usage examples
├── benchmarks/            # Performance benchmarks
├── docker/                # Docker support
└── docs/                  # Additional documentation
```

## Development Guidelines

### Code Style

- **Julia Style Guide** - Follow official Julia style conventions
- **Function Naming** - Use snake_case for functions, CamelCase for types
- **Comments** - Docstrings for all public functions, inline comments for complex logic
- **Line Length** - Prefer 92 characters max (Julia convention)
- **Modularity** - Each module has single responsibility, minimal coupling

### Testing

- **Framework** - Julia's built-in Test module
- **Coverage** - Aim for >80% code coverage
- **Test Types** - Unit tests for functions, integration tests for workflows
- **Run Tests** - `julia --project test/runtests.jl`
- **Privacy Tests** - Verify no network calls, verify consent checks

### Git Workflow

- **Main Branch** - `main` (production-ready code)
- **Feature Branches** - Use `claude/` prefix for AI assistant work
- **Commit Messages** - Clear, descriptive, conventional commits format
- **Commits** - Atomic commits, one logical change per commit
- **Push Strategy** - Push to feature branch, create PR for review

## Tech Stack

**Core:**
- **Julia** - Primary language (v1.6+)
- **JSON3.jl** - JSON parsing and generation
- **XLSX.jl** - Excel report generation
- **DataFrames.jl** - Data manipulation

**Optional Dependencies:**
- **GTK.jl** - Graphical user interface
- **HTTP.jl** - Web dashboard (local only, no external calls)
- **MQTT.jl** - IoT device integration
- **Genie.jl** - Web framework for dashboard
- **Plots.jl** - Data visualization in reports

**Development Tools:**
- **Julia Test** - Testing framework
- **GitLab CI/CD** - Continuous integration
- **Docker** - Containerization for deployment

## Key Directories

- **src/** - All Julia source modules, each with focused responsibility
- **test/** - Comprehensive test suite including unit, integration, and privacy tests
- **data/** - JSON databases and configuration (never contains personal data)
- **examples/** - Example scripts showing different usage patterns
- **docs/** - Extended documentation including architecture decisions
- **docker/** - Dockerfiles and compose configurations for deployment
- **benchmarks/** - Performance testing and optimization data

## Build & Run

### Quick Start

```bash
# Install Julia (1.6 or later)
# Clone repository
git clone <repo-url>
cd jusys

# Activate project
julia --project=.

# Install dependencies
using Pkg; Pkg.instantiate()

# Run in NO PEEK mode (no system access required)
julia --project=. -e 'include("src/cli.jl"); Juisys.CLI.run_no_peek_mode()'

# Run full audit (requires consent)
julia --project=. -e 'include("src/cli.jl"); Juisys.CLI.run_full_audit()'

# Run tests
julia --project=. test/runtests.jl

# Run with GUI (if GTK.jl available)
julia --project=. -e 'include("src/gui.jl"); Juisys.GUI.launch()'
```

### Docker

```bash
docker-compose up
# Access web dashboard at http://localhost:8080
```

## Dependencies

### Core Dependencies (Required)
- **JSON3.jl** - Fast JSON parsing for app database and rules
- **XLSX.jl** - Generate Excel reports with classifications
- **DataFrames.jl** - Data manipulation and analysis

### Optional Dependencies (Graceful Degradation)
- **GTK.jl** - Graphical interface (falls back to CLI if missing)
- **HTTP.jl** - Web dashboard server (local only)
- **MQTT.jl** - IoT device notifications (optional ambient feature)
- **Genie.jl** - Web framework for dashboard
- **Plots.jl** - Visualizations in reports

## Important Notes for AI Assistants

### Privacy-First Architecture
- **NEVER add network calls** - 100% local processing is core requirement
- **NEVER store personal data** - All data ephemeral (cleared after session)
- **ALWAYS require consent** - Before any system access, get explicit consent
- **ALWAYS verify privacy** - Test suite must validate no data leaks

### Educational Framework
- Demonstrates all 12 GDPR processing types (Collection→Recording→Organization→...→Erasure)
- Shows automation benefits AND risks (documented in ETHICS.md)
- Implements Hazard Triangle: ELIMINATE→SUBSTITUTE→CONTROL
- Follows Calm Technology principles for ambient computing

### Technical Constraints
- Julia may not be installed - code must be valid but won't run everywhere
- GTK/MQTT optional - graceful degradation required
- Package managers vary by platform - detect and fallback gracefully
- NO PEEK mode must always work (zero system dependencies)

### Key Files for Users
- **Start here:** TUTORIAL.md (step-by-step guide)
- **Privacy details:** ETHICS.md (GDPR deep-dive)
- **Technical:** PROJECT_SUMMARY.md (complete architecture)
- **Contributing:** CONTRIBUTING.md (development guide)

## Architecture Decisions

### 1. No Network Calls (Privacy)
**Decision:** 100% local processing, zero telemetry
**Rationale:** GDPR Article 5.1.f (integrity and confidentiality), builds user trust
**Trade-off:** Can't auto-update app database, but user privacy worth it

### 2. Ephemeral Storage (GDPR Article 5.1.e)
**Decision:** All data cleared after session, no persistent personal data
**Rationale:** Storage limitation principle, minimizes data breach risk
**Trade-off:** No history tracking, but can export reports for manual retention

### 3. Explicit Consent (GDPR Article 6.1.a)
**Decision:** Ask permission before any system access
**Rationale:** Legal basis for processing, respects user autonomy
**Implementation:** security.jl manages consent workflow

### 4. Hazard Triangle Implementation
**Decision:** Three-tier approach to risk management
**Rationale:** Industry best practice from safety engineering
**Levels:**
- ELIMINATE: NO PEEK mode (manual entry, zero system access)
- SUBSTITUTE: Local JSON DB (no API calls to third parties)
- CONTROL: Consent checks + ephemeral storage

### 5. Multi-Modal Interfaces (Ambient Computing)
**Decision:** CLI, GUI, web dashboard, audio, visual, IoT
**Rationale:** Accessibility, different user preferences, Calm Technology
**Principles:** Glanceable, proportional, non-intrusive feedback

### 6. Julia Language Choice
**Decision:** Use Julia for implementation
**Rationale:** Performance, expressiveness, good for data processing
**Trade-off:** Smaller ecosystem than Python, but cleaner code

## Common Tasks

### Setting Up Development Environment

```bash
# 1. Install Julia 1.6+
# Download from https://julialang.org/downloads/

# 2. Clone and setup
git clone <repo-url>
cd jusys
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# 3. Run tests to verify
julia --project=. test/runtests.jl

# 4. Try NO PEEK mode (safest, requires no permissions)
julia --project=. src/cli.jl
```

### Running Tests

```bash
# All tests
julia --project=. test/runtests.jl

# Specific module tests
julia --project=. -e 'include("test/test_core.jl")'

# With coverage
julia --project=. --code-coverage=user test/runtests.jl

# Privacy validation tests (critical!)
julia --project=. -e 'include("test/test_privacy.jl")'
```

### Adding New App Alternatives

```bash
# Edit data/app_db.json
# Follow schema:
{
  "proprietary_name": "Adobe Photoshop",
  "foss_alternatives": ["GIMP", "Krita"],
  "category": "graphics",
  "cost_savings": 239.88,
  "privacy_benefit": "high",
  "feature_parity": 0.85
}

# Validate JSON
julia --project=. -e 'include("src/io.jl"); Juisys.IO.validate_app_db()'
```

### Deploying

```bash
# Docker deployment
docker build -t juisys:latest -f docker/Dockerfile .
docker run -p 8080:8080 juisys:latest

# Or with docker-compose
docker-compose up -d

# Access web dashboard
firefox http://localhost:8080
```

## Troubleshooting

### Julia Package Installation Fails
```bash
# Clear package cache and retry
rm -rf ~/.julia/packages
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### GTK.jl Won't Install
```bash
# GTK is optional - use CLI mode instead
julia --project=. -e 'include("src/cli.jl"); Juisys.CLI.run()'

# Or install GTK system dependencies
# Ubuntu/Debian: sudo apt install libgtk-3-dev
# macOS: brew install gtk+3
```

### Package Manager Not Detected
```bash
# Use NO PEEK mode for manual entry
julia --project=. -e 'include("src/cli.jl"); Juisys.CLI.run_no_peek_mode()'

# Or specify package manager manually
julia --project=. -e 'include("src/automate.jl"); Juisys.Automate.scan("apt")'
```

### Tests Fail on Network Check
```bash
# This is INTENTIONAL - tests verify no network calls
# If tests pass, it means code is making network calls (bad!)
# Review the failing code and remove network access
```

## Additional Resources

- **Julia Documentation:** https://docs.julialang.org/
- **GDPR Full Text:** https://gdpr-info.eu/
- **Calm Technology:** http://calmtech.com/
- **Hazard Triangle:** OSHA safety hierarchy of controls
- **Book Specifications:** See ETHICS.md for educational framework details
- **Built with:** Claude Sonnet 4.5 (documented in ETHICS.md and code comments)

## Operating Modes

### 1. NO PEEK Mode (Maximum Privacy)
- Manual app entry only
- Zero system access
- No consent required
- Perfect for sensitive environments

### 2. Quick Scan Mode
- Scans package manager with consent
- Fast classification
- Basic report generation

### 3. FULL AUDIT Mode
- Complete system scan
- Detailed alternatives analysis
- Cost/privacy calculations
- Multi-format reports

### 4. Import Mode
- Load app list from file
- Useful for air-gapped systems
- Supports CSV, JSON, TXT

### 5. Export Mode
- Generate reports: XLSX, Markdown, CSV, JSON, HTML
- Include visualizations
- Shareable formats

### 6. Self-Audit Mode
- Audits Juisys own code
- Scans for privacy risks
- Transparency feature

### 7. GUI Mode
- Graphical interface
- Visual feedback (color-coding)
- Point-and-click workflow

### 8. Web Dashboard Mode
- Browser-based interface
- Local server only (no external access)
- Charts and visualizations

### 9. Ambient Mode
- Multi-modal feedback
- Audio beeps for warnings
- IoT device integration
- Calm Technology principles

---

**Note:** This file should be updated as the project evolves. Keep it current to help AI assistants work more effectively with the codebase.

**Attribution:** This educational project was developed with Claude Sonnet 4.5 to demonstrate GDPR principles, privacy-first design, and ambient computing concepts through a functional tool.
