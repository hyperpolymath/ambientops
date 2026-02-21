# Contributing to Broad Spectrum

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

Be respectful, inclusive, and professional. We value:
- Constructive feedback
- Collaborative problem-solving
- Clear communication
- Quality over quantity

## Getting Started

### Prerequisites

1. **Deno** v1.30 or later
2. **Node.js** v18 or later
3. **ReScript** v11.0 or later
4. **Git** for version control

### Development Setup

```bash
# Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/broad-spectrum.git
cd broad-spectrum

# Install dependencies
npm install

# Build the project
npm run build

# Run tests
deno test --allow-net --allow-read
```

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

**Branch Naming:**
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test additions/improvements

### 2. Make Changes

**ReScript Files:**
- Follow functional programming principles
- Use immutable data structures
- Prefer `option` over null checks
- Use pattern matching for conditionals
- Add type annotations for public APIs

**TypeScript Files:**
- Follow existing code style
- Use strict type checking
- Avoid `any` types
- Document complex functions

**Code Style:**
- Run formatter before committing
- Follow existing conventions
- Keep functions small and focused
- Write self-documenting code

### 3. Test Your Changes

```bash
# Run existing tests
deno test --allow-net --allow-read

# Add new tests for your changes
# See tests/ directory for examples

# Manual testing
npm run build
deno task audit --url https://example.com
```

### 4. Commit Your Changes

**Commit Message Format:**
```
type(scope): subject

body (optional)

footer (optional)
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `test`: Test additions
- `chore`: Maintenance

**Examples:**
```
feat(accessibility): add color contrast checking

Add WCAG AA color contrast validation for text elements.
Checks foreground/background color ratios.

Closes #123
```

```
fix(fetcher): handle network timeouts correctly

Previously, network timeouts weren't properly caught.
Now uses AbortController to enforce strict timeouts.
```

### 5. Push and Create Pull Request

```bash
git push origin your-branch-name
```

Then create a Pull Request on GitHub with:
- Clear title and description
- Reference to related issues
- Screenshots (if UI changes)
- Test results

## Areas for Contribution

### High Priority

1. **Test Coverage**
   - Unit tests for all modules
   - Integration tests
   - Edge case coverage
   - Performance benchmarks

2. **Documentation**
   - API documentation
   - Usage examples
   - Tutorial content
   - Architecture diagrams

3. **Bug Fixes**
   - See GitHub Issues
   - Fix compilation warnings
   - Runtime error handling

### Medium Priority

1. **New Features**
   - Additional accessibility checks
   - More SEO rules
   - Performance optimizations
   - New report formats (PDF, CSV)

2. **Tooling**
   - CI/CD pipeline improvements
   - Docker containerization
   - Development scripts
   - Automated releases

3. **Examples**
   - CI/CD integration examples
   - Configuration templates
   - Real-world use cases

### Low Priority

1. **Enhancements**
   - CLI UX improvements
   - Progress indicators
   - Colorized output
   - Interactive mode

2. **Refactoring**
   - Code organization
   - Performance improvements
   - Technical debt reduction

## Pull Request Guidelines

### Before Submitting

- [ ] Code compiles without errors
- [ ] All tests pass
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if applicable)
- [ ] No unrelated changes included

### PR Checklist

- [ ] Clear, descriptive title
- [ ] Detailed description of changes
- [ ] References related issues
- [ ] Includes test results
- [ ] Screenshots/examples (if applicable)
- [ ] Ready for review

### Review Process

1. **Automated Checks** - CI/CD runs tests
2. **Code Review** - Maintainer reviews code
3. **Feedback** - Address review comments
4. **Approval** - Maintainer approves PR
5. **Merge** - PR merged to main branch

## Style Guide

### ReScript Style

```rescript
// Good
let calculateScore = (violations: array<issue>): float => {
  violations
  ->Array.reduce(100.0, (score, violation) => {
    score -. getSeverityPenalty(violation)
  })
}

// Avoid
let calculateScore = (violations) => {
  let mut score = 100.0
  for i in 0 to Array.length(violations) - 1 {
    score = score - getSeverityPenalty(violations[i])
  }
  score
}
```

### TypeScript Style

```typescript
// Good
export async function fetchUrl(
  url: string,
  timeout: number
): Promise<Result<Response, Error>> {
  // ...
}

// Avoid
export async function fetchUrl(url: any, timeout: any): Promise<any> {
  // ...
}
```

## Testing Guidelines

### Unit Tests

```typescript
Deno.test("function name - what it tests", async () => {
  // Arrange
  const input = createTestData();

  // Act
  const result = await functionUnderTest(input);

  // Assert
  assertEquals(result.value, expectedValue);
});
```

### Integration Tests

```typescript
Deno.test("audit flow - full website audit", async () => {
  const result = await auditWebsite("https://example.com", defaultConfig);

  assert(result.TAG === "Ok");
  assert(result._0.overallScore > 0);
});
```

## Documentation Guidelines

### Code Documentation

```rescript
// Public functions should have docstrings
/// Calculates the overall audit score from individual scanner results.
///
/// Weights:
/// - Links: 20%
/// - Accessibility: 30%
/// - Performance: 30%
/// - SEO: 20%
///
/// @param linkCheck - Link checking results (optional)
/// @param accessibility - Accessibility results (optional)
/// @param performance - Performance results (optional)
/// @param seo - SEO results (optional)
/// @returns Weighted overall score (0-100)
let calculateOverallScore = (
  linkCheck: option<linkCheckResult>,
  // ...
): float => {
  // Implementation
}
```

### README Updates

- Keep examples up-to-date
- Add new features to feature list
- Update usage instructions
- Include migration guides for breaking changes

## Release Process

(For maintainers)

1. Update version in `package.json`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.0.0`
4. Push tag: `git push --tags`
5. Create GitHub release
6. Publish artifacts (if applicable)

## Getting Help

- **GitHub Issues** - Bug reports, feature requests
- **Discussions** - Questions, ideas, general discussion
- **Documentation** - README.md, ARCHITECTURE.md
- **Code Examples** - examples/ directory

## Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited in documentation

Thank you for contributing to Broad Spectrum!
