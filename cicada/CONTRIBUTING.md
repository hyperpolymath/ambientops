# Contributing to CIcaDA

Thank you for your interest in contributing to CIcaDA! This document provides guidelines for contributing to the Palimpsest Crypto Identity project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Process](#development-process)
- [Contribution Types](#contribution-types)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Security Guidelines](#security-guidelines)
- [Documentation](#documentation)

## Code of Conduct

This project adheres to the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to conduct@hyperpolymath.org.

## Getting Started

### Prerequisites

- Julia 1.9 or higher
- Git
- `ssh-keygen` (for classical key generation)
- Familiarity with cryptographic concepts (recommended)

### Setup Development Environment

```bash
# Clone repository
git clone https://github.com/Hyperpolymath/CIcaDA.git
cd CIcaDA

# Initialize submodules
git submodule update --init --recursive

# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run tests to verify setup
julia --project=. test/runtests.jl

# Initialize configuration
julia --project=. src/main.jl init
```

## Development Process

### Tri-Perimeter Contribution Framework (TPCF)

CIcaDA operates under **Perimeter 3: Community Sandbox**
- All contributors welcome
- Open issues and pull requests
- Maintainer approval required for merge
- Security-critical code requires elevated review

### Workflow

1. **Find or Create an Issue**
   - Check existing issues first
   - Create new issue describing your contribution
   - Discuss approach with maintainers

2. **Fork and Branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/bug-description
   ```

3. **Develop and Test**
   - Write code following Julia style guide
   - Add tests for new functionality
   - Update documentation
   - Run full test suite

4. **Commit**
   ```bash
   git add .
   git commit -m "Brief description of changes"
   ```

   Use conventional commit format:
   - `feat:` New feature
   - `fix:` Bug fix
   - `docs:` Documentation only
   - `test:` Adding tests
   - `refactor:` Code refactoring
   - `security:` Security improvement

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   - Open pull request on GitHub
   - Fill out PR template completely
   - Link related issues
   - Request review from maintainers

## Contribution Types

### Welcome Contributions

#### Easy (Good First Issues)
- Documentation improvements
- Example scripts and workflows
- Test coverage improvements
- Bug fixes in non-critical code
- UI/UX enhancements

#### Medium
- New CLI commands
- Integration with other services
- Performance optimizations
- Backup/restore features
- Configuration enhancements

#### Advanced
- New key algorithms (requires crypto expertise)
- Security auditing improvements
- Post-quantum cryptography (full implementation)
- Multi-factor authentication
- Hardware security module support

### Security-Critical Contributions

These require **elevated review** by cryptography experts:
- Key generation algorithms (`src/keygen/`)
- Key storage and handling (`src/storage/keystore.jl`)
- Security validation (`src/validation/`)
- Cryptographic operations

**Requirements**:
1. Demonstrate cryptography expertise
2. Provide security analysis
3. Include formal verification (where applicable)
4. Comprehensive testing
5. External security review

## Pull Request Process

### PR Template

```markdown
## Description
[Clear description of changes]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update
- [ ] Security improvement

## Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing performed

## Security
- [ ] No security implications
- [ ] Security review requested (if applicable)
- [ ] Cryptography expert review (if applicable)

## Documentation
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] Docstrings added
- [ ] Examples updated (if applicable)

## Checklist
- [ ] Code follows Julia style guide
- [ ] Commits follow conventional format
- [ ] No merge conflicts
- [ ] PR linked to issue
```

### Review Process

1. **Automated Checks**
   - CI/CD pipeline must pass
   - All tests must pass
   - Code quality checks

2. **Maintainer Review**
   - Code quality
   - Architecture fit
   - Documentation completeness
   - Test coverage

3. **Security Review** (if applicable)
   - Cryptographic correctness
   - Security implications
   - Vulnerability assessment

4. **Merge**
   - Squash and merge (default)
   - Maintainer performs merge
   - Delete branch after merge

## Coding Standards

### Julia Style Guide

Follow [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/):

```julia
# Good
function generate_keypair(email::String; comment::String="")
    metadata = KeyMetadata(ED25519, SSH_AUTH, email, comment)
    # ...
end

# Bad
function genKey(e)
    # ...
end
```

### Documentation

All public functions require docstrings:

```julia
"""
Generate Ed25519 SSH key pair

# Arguments
- `email::String`: Email address for key identification
- `comment::String=""`: Optional comment for key

# Returns
- `KeyPair`: Generated key pair with metadata

# Examples
```julia
keypair = generate_ed25519("user@example.com", comment="dev key")
```

# Security
This function handles cryptographic key material. Ensure proper
storage and never log private keys.
"""
function generate_ed25519(email::String; comment::String="")::KeyPair
    # ...
end
```

### Error Handling

Use custom error types:

```julia
# Good
throw(KeyGenerationError("Failed to generate Ed25519 key: $(e)"))

# Bad
error("Key generation failed")
```

### Logging

Use structured logging:

```julia
@info "Generating Ed25519 key" email=email algorithm=ED25519
log_key_operation("GENERATE", "Creating Ed25519 key pair for $email")
log_security("SECURITY EVENT: Key rotation initiated")
```

## Testing Requirements

### Test Coverage

- **Minimum**: 80% code coverage
- **Target**: 90%+ code coverage
- **Security-critical**: 100% coverage required

### Test Structure

```julia
@testset "Feature Name" begin
    @testset "Specific behavior" begin
        # Arrange
        test_data = setup_test_data()

        # Act
        result = function_under_test(test_data)

        # Assert
        @test result == expected_value
        @test validate_result(result)
    end

    @testset "Error handling" begin
        @test_throws SpecificError function_under_test(invalid_data)
    end
end
```

### Running Tests

```bash
# All tests
julia --project=. test/runtests.jl

# Specific test file
julia --project=. -e 'include("test/test_keygen.jl")'

# With coverage
julia --project=. --code-coverage=user test/runtests.jl
```

## Security Guidelines

### Secure Coding Practices

1. **Never Log Secrets**
   ```julia
   # Good
   @info "Key generated" key_id=keypair.metadata.id

   # Bad
   @info "Key generated" private_key=keypair.private_key
   ```

2. **Validate All Inputs**
   ```julia
   function process_key(key_id::UUID)
       if !isvalid(key_id)
           throw(ValidationError("Invalid key ID"))
       end
       # ...
   end
   ```

3. **Use Constant-Time Comparisons** (for crypto)
   ```julia
   # For cryptographic comparisons, use timing-safe functions
   ```

4. **Secure File Permissions**
   ```julia
   chmod(private_key_path, 0o600)  # Owner read/write only
   chmod(key_dir, 0o700)            # Owner full access only
   ```

### Security Review Checklist

For security-critical contributions:
- [ ] No hardcoded secrets
- [ ] All inputs validated
- [ ] Error messages don't leak sensitive info
- [ ] Cryptographic operations use established libraries
- [ ] Timing attacks considered
- [ ] File permissions set correctly
- [ ] No use of unsafe operations
- [ ] External security review obtained

### Vulnerability Disclosure

Found a security issue? **DO NOT** open a public issue.

1. Email security@hyperpolymath.org
2. Include detailed description
3. Provide steps to reproduce
4. Suggest fix (if available)

See [SECURITY.md](SECURITY.md) for full policy.

## Documentation

### Required Documentation

1. **Code Comments**
   - Explain complex algorithms
   - Note security considerations
   - Reference relevant RFCs/standards

2. **Docstrings**
   - All public functions
   - Include examples
   - Document exceptions

3. **README Updates**
   - New features
   - Changed behavior
   - Breaking changes

4. **CHANGELOG**
   - All notable changes
   - Follow Keep a Changelog format
   - Version bumps

5. **User Guide**
   - Update for new commands
   - Add examples
   - Update workflows

### Documentation Style

- Use present tense
- Be concise but complete
- Include code examples
- Link to related docs
- Explain the "why," not just the "how"

## Recognition

All contributors are:
- Listed in `humans.txt`
- Credited in CHANGELOG
- Acknowledged in release notes
- Thanked in project README

Thank you for contributing to CIcaDA! 🔐

## Questions?

- Open a discussion: https://github.com/Hyperpolymath/CIcaDA/discussions
- Email: maintainers@hyperpolymath.org
- See: [MAINTAINERS.md](MAINTAINERS.md)
