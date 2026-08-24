# CLAUDE.md

This file contains instructions and context for Claude Code when working on this project.

## Project Overview

**Repository:** Hyperpolymath/broad-spectrum
**Project:** Website Auditor

A standalone CLI website auditor that performs comprehensive security, accessibility, performance, and SEO audits. Written entirely in AffineScript with Deno as the runtime.

**Key Features:**
- Broken link detection and validation
- Accessibility auditing (WCAG compliance)
- Performance metrics collection
- SEO issue identification
- Multiple report formats (console, JSON, HTML, markdown)

## Technology Stack

**Core Technologies:**
- **AffineScript**: Primary language (100% AffineScript, no TypeScript)
- **Deno**: Secure runtime (no Node.js runtime deps)
- **Native URL API**: WHATWG-compliant URL parsing via browser/Deno APIs

**Build Pipeline:**
- AffineScript compiler (`affinescript`) → JavaScript modules
- Deno for runtime execution
- `just` for task orchestration
- Nickel (`Mustfile.ncl`) for configuration contracts

## Language Policy

See `.claude/CLAUDE.md` for the complete language policy. Key points:

**ALLOWED:**
- AffineScript (primary application code)
- Nickel (configuration)
- Bash (minimal scripts)

**BANNED:**
- TypeScript - Use AffineScript
- Node.js/npm/bun - Use Deno
- Makefiles - Use Justfile

## Project Structure

```
broad-spectrum/
├── src/                    # AffineScript source files
│   ├── Main.res           # CLI entry point
│   ├── Auditor.res        # Main orchestrator
│   ├── Config.res         # Shared configuration types
│   ├── DenoBindings.res   # Deno/Web API bindings
│   ├── UrlParser.res      # URL parsing (facade)
│   ├── UrlParserImpl.res  # URL parsing implementation
│   ├── Fetcher.res        # HTTP handling (facade)
│   ├── FetcherImpl.res    # HTTP implementation
│   ├── LinkChecker.res    # Broken link detection
│   ├── Accessibility.res  # WCAG compliance (facade)
│   ├── AccessibilityImpl.res  # A11y implementation
│   ├── Performance.res    # Performance metrics (facade)
│   ├── HtmlParserImpl.res # HTML/performance implementation
│   ├── SEO.res           # SEO analysis (facade)
│   ├── SeoParserImpl.res # SEO implementation
│   ├── Report.res        # Report generation (facade)
│   └── ReportImpl.res    # Report implementation
├── tests/                 # AffineScript test files
├── lib/                   # Compiled JavaScript output
├── affinescript.json          # AffineScript build configuration
├── deno.json             # Deno task definitions
├── Justfile              # Task runner (replaces Makefile)
├── Mustfile.ncl          # Nickel configuration contract
└── package.json          # Dev deps only (AffineScript compiler)
```

## Common Tasks

### Development Setup

```bash
# Install AffineScript compiler (dev dependency)
npm install

# Build the project
just build
# OR: affinescript build

# Watch mode
just watch
```

### Running the Auditor

```bash
# Audit a website
just audit "https://example.com"

# With specific format
just audit-json "https://example.com"
just audit-html "https://example.com"

# From file
just audit-file urls.txt
```

### Running Tests

```bash
just test
```

### Quality Checks

```bash
just check       # Run all checks (format, lint, typecheck, test)
just validate    # Full validation including docs
just rsr-status  # Show compliance status
```

## Architecture Notes

**Pure AffineScript Implementation:**
All functionality is implemented in AffineScript. The `*Impl.res` files contain the actual implementations, while the facade modules (without `Impl`) provide the public API. This allows for:
- Clean module interfaces
- Easy testing
- No TypeScript dependencies

**DenoBindings.res:**
Contains direct bindings to Deno/Web APIs including:
- `fetch` API
- `URL` constructor
- `AbortController`
- `performance.now()`
- Console and filesystem operations

**No External Dependencies:**
The project uses only:
- Native Web/Deno APIs for URL parsing, HTTP, etc.
- AffineScript standard library
- No npm runtime dependencies

## AffineScript Best Practices

1. **Use @affinescript/core Array module:**
   ```affinescript
   Array.push(arr, item)->ignore
   Array.map(arr, fn)
   ```

2. **Escape reserved keywords:**
   ```affinescript
   type linkStatus = {
     \"external": bool
   }
   ```

3. **Promise handling:**
   ```affinescript
   let result = await someAsyncFn()
   ```

4. **External bindings:**
   ```affinescript
   @scope("Deno") @val external args: array<string> = "args"
   ```

## CI/CD Enforcement

GitHub Actions enforce:
- **runtime-policy.yml**: No npm/bun lock files
- **makefile-blocker.yml**: No Makefiles (use Justfile)

## Resources

- [AffineScript Documentation](https://affinescript-lang.org/docs/manual/latest)
- [Deno Documentation](https://deno.land/manual)
- [just Command Runner](https://github.com/casey/just)
- [Nickel Configuration](https://nickel-lang.org/)

---

*This file is updated to reflect the pure AffineScript architecture.*
