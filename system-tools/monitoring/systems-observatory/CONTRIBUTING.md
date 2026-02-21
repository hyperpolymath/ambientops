# Contributing to Juisys

Thank you for your interest in contributing to Juisys! This guide will help you get started.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Contribution Guidelines](#contribution-guidelines)
5. [Testing Requirements](#testing-requirements)
6. [Privacy Compliance](#privacy-compliance)
7. [Pull Request Process](#pull-request-process)

---

## Code of Conduct

### Privacy First

All contributions MUST maintain privacy-first architecture:
- ❌ NO network calls
- ❌ NO persistent personal data storage
- ❌ NO telemetry or tracking
- ✅ Ephemeral data only
- ✅ Explicit consent required
- ✅ Self-audit must pass

**Violations of privacy principles will be rejected.**

### Respectful Collaboration

- Be respectful and constructive
- Welcome newcomers
- Focus on code quality and privacy
- Provide helpful feedback

---

## Getting Started

### Prerequisites

- Julia 1.6+
- Git
- Text editor/IDE
- Basic understanding of GDPR principles (see [ETHICS.md](ETHICS.md))

### Fork and Clone

```bash
# Fork on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/jusys.git
cd jusys

# Add upstream remote
git remote add upstream https://github.com/original/jusys.git
```

---

## Development Setup

### Install Dependencies

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Run Tests

```bash
# All tests
julia --project=. test/runtests.jl

# Specific module
julia --project=. -e 'include("test/test_core.jl")'
```

### Verify Privacy Compliance

```bash
# CRITICAL: Run before every commit
julia --project=. -e 'include("src/security.jl"); using .Security; println(Security.get_privacy_report())'
```

---

## Contribution Guidelines

### Code Style

#### Julia Conventions

```julia
# Function names: snake_case
function calculate_privacy_score(app::App)
    # ...
end

# Type names: CamelCase
struct ClassificationResult
    # ...
end

# Constants: UPPER_CASE
const MAX_APPS = 1000

# Comments: Document why, not what
# Bad:  # Loop through apps
# Good: # Process in batches to manage memory
```

#### Line Length

- Prefer 92 characters (Julia convention)
- Hard limit: 100 characters

#### Docstrings

All public functions MUST have docstrings:

```julia
"""
    classify_app(app_name::String, rules::Dict)

Classify application by name using provided rules.

Returns ClassificationResult with risk assessment.

GDPR: Collection → Organization → Structuring
Privacy: Local processing only, no network calls
"""
function classify_app(app_name::String, rules::Dict)
    # ...
end
```

### Module Organization

Each module should have:
- Clear single responsibility
- Minimal dependencies
- Explicit exports
- Privacy documentation

### Adding New Features

1. **Check Privacy Impact**: Will this require system access? Network calls? Data storage?

2. **Design for Privacy**: Use Hazard Triangle - can you ELIMINATE risk? SUBSTITUTE? Or must you CONTROL?

3. **Implement Consent**: If system access needed, use `Security.request_consent()`

4. **Document GDPR**: Which processing types does this involve?

5. **Test Privacy**: Add tests to verify no privacy violations

### Example: Adding a New Module

```julia
"""
    NewModule.jl - Brief Description

    Explain what this module does and why.

    PRIVACY: [State privacy guarantees]
    GDPR: [List processing types involved]

    Author: Your Name
    License: MIT
"""

module NewModule

export main_function

# Minimal imports
using JSON3

"""
    main_function(arg::String)

    [Docstring with privacy notes]
"""
function main_function(arg::String)
    # Implementation
end

end # module
```

---

## Testing Requirements

### Test Categories

#### 1. Unit Tests

Test individual functions in isolation.

```julia
@testset "Core.classify_app" begin
    rules = Core.get_default_rules()
    result = Core.classify_app("TestApp", rules)

    @test result isa Core.ClassificationResult
    @test result.risk_level in [Core.NONE, Core.LOW, Core.MEDIUM, Core.HIGH, Core.CRITICAL]
end
```

#### 2. Integration Tests

Test module interactions.

```julia
@testset "Full Workflow" begin
    # Load -> Classify -> Report
    apps = IO.load_app_database("data/app_db.json")
    # ...
end
```

#### 3. Privacy Tests (CRITICAL)

**MANDATORY** for all PRs:

```julia
@testset "Privacy Compliance" begin
    @testset "No Network Calls" begin
        # Scan source for network functions
        violations = check_network_calls()
        @test isempty(violations)
    end

    @testset "No Persistent Storage" begin
        # Verify no DB writes, no file persistence
        @test verify_ephemeral_storage()
    end

    @testset "Consent Required" begin
        # Check consent framework usage
        @test verify_consent_checks()
    end
end
```

### Coverage Requirements

- Aim for >80% code coverage
- Critical paths (security, privacy) must be 100%
- Privacy tests are non-negotiable

---

## Privacy Compliance

### Before Every Commit

Run privacy checklist:

```bash
# 1. Self-audit
julia --project=. -e 'include("src/security.jl"); using .Security; Security.self_audit()'

# 2. Run tests
julia --project=. test/runtests.jl

# 3. Manual code review
# - Any new imports that could enable network?
# - Any new file I/O without consent?
# - Any persistent storage of user data?
```

### Network Calls

**NEVER ALLOWED** except:
- MQTT to localhost (with IOT_PUBLISH consent)
- HTTP.jl for local web dashboard (with GUI_ACCESS consent)

### Data Storage

**Ephemeral only:**
- In-memory variables
- Session-scoped structs
- Cleared on process exit

**Persistent allowed ONLY:**
- User-requested exports (with FILE_WRITE consent)
- Local configuration files (non-personal data)

### Consent Pattern

```julia
# 1. Check if consent already granted
if !Security.has_consent(Security.OPERATION_TYPE)
    # 2. Request consent with clear purpose
    granted = Security.request_consent(
        Security.OPERATION_TYPE,
        "Clear explanation of why this is needed"
    )

    # 3. Respect denial
    if !granted
        @warn "Operation cancelled - consent denied"
        return nothing
    end
end

# 4. Proceed with operation
perform_operation()
```

---

## Pull Request Process

### 1. Create Branch

```bash
git checkout -b feature/your-feature-name
# OR
git checkout -b fix/issue-number-description
```

### 2. Make Changes

- Follow code style guidelines
- Add tests
- Update documentation
- Verify privacy compliance

### 3. Commit

```bash
# Good commit messages
git commit -m "Add FOSS alternative lookup caching

Improves performance by caching database reads.
No privacy impact - cache is ephemeral.
Adds unit tests and updates documentation."
```

### 4. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create pull request on GitHub.

### PR Template

```markdown
## Description
[What does this PR do?]

## Privacy Impact
- [ ] No new system access required
- [ ] No new network calls
- [ ] No persistent data storage
- [ ] Self-audit passes
- [ ] Privacy tests pass

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Privacy compliance tests pass
- [ ] Manual testing performed

## Documentation
- [ ] Code comments added
- [ ] Docstrings updated
- [ ] User documentation updated (if needed)
- [ ] CHANGELOG updated

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests added and passing
- [ ] Self-audit passes
- [ ] Documentation updated
- [ ] Commits are clear and descriptive
```

### Review Process

1. **Automated**: CI/CD runs tests, privacy checks
2. **Manual**: Maintainer reviews code, architecture
3. **Privacy**: Special focus on privacy compliance
4. **Iteration**: Address feedback, update as needed
5. **Merge**: Once approved and tests pass

---

## Common Contributions

### Adding FOSS Alternatives

Edit `data/app_db.json`:

```json
{
  "proprietary_name": "App Name",
  "foss_alternatives": ["Alternative 1", "Alternative 2"],
  "category": "productivity",
  "cost_savings": 99.00,
  "privacy_benefit": "high",
  "feature_parity": 0.85,
  "learning_curve": "medium",
  "migration_effort": "medium",
  "maturity": "stable",
  "platforms": ["Windows", "macOS", "Linux"],
  "license": "GPL/MIT",
  "community_size": "large"
}
```

Submit PR with:
- Accurate data
- Verification of alternatives
- Cost research
- Feature parity justification

### Adding Classification Rules

Edit `data/rules.json`:

```json
{
  "categories": {
    "new_category": ["keyword1", "keyword2"]
  },
  "risk_flags": {
    "new_flag_keywords": ["pattern1", "pattern2"]
  }
}
```

### Improving Documentation

- Fix typos
- Clarify explanations
- Add examples
- Translate (future)

Documentation PRs are always welcome!

---

## Development Tips

### Debugging

```julia
# Enable debug logging
using Logging
global_logger(ConsoleLogger(stderr, Logging.Debug))

# Test specific function
include("src/core.jl")
using .Core

rules = Core.get_default_rules()
result = Core.classify_app("TestApp", rules)
println(result)
```

### Iterative Testing

```bash
# Watch for changes and auto-test
while inotifywait -r src/ test/; do
    julia --project=. test/runtests.jl
done
```

### Performance Profiling

```julia
using Profile

@profile begin
    # Code to profile
end

Profile.print()
```

---

## Questions?

- Open an issue for discussion
- Check existing issues/PRs
- Read [ETHICS.md](ETHICS.md) for privacy principles
- Review [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) for architecture

---

## License

By contributing, you agree your contributions will be licensed under MIT License.

---

**Thank you for contributing to privacy-first software! 🔒**
