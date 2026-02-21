# CLAUDE.md

This file contains instructions and context for Claude Code when working on this project.

## Project Overview

**Repository:** Hyperpolymath/broad-spectrum
**Project:** Website Auditor

A standalone CLI website auditor that performs comprehensive security, accessibility, performance, and SEO audits. Written entirely in ReScript with Deno as the runtime.

**Key Features:**
- Broken link detection and validation
- Accessibility auditing (WCAG compliance)
- Performance metrics collection
- SEO issue identification
- Multiple report formats (console, JSON, HTML, markdown)

## Technology Stack

**Core Technologies:**
- **ReScript**: Primary language (100% ReScript, no TypeScript)
- **Deno**: Secure runtime (no Node.js runtime deps)
- **Native URL API**: WHATWG-compliant URL parsing via browser/Deno APIs

**Build Pipeline:**
- ReScript compiler (`rescript`) → JavaScript modules
- Deno for runtime execution
- `just` for task orchestration
- Nickel (`Mustfile.ncl`) for configuration contracts

## Language Policy

See `.claude/CLAUDE.md` for the complete language policy. Key points:

**ALLOWED:**
- ReScript (primary application code)
- Nickel (configuration)
- Bash (minimal scripts)

**BANNED:**
- TypeScript - Use ReScript
- Node.js/npm/bun - Use Deno
- Makefiles - Use justfile

## Project Structure

```
broad-spectrum/
├── src/                    # ReScript source files
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
├── tests/                 # ReScript test files
├── lib/                   # Compiled JavaScript output
├── rescript.json          # ReScript build configuration
├── deno.json             # Deno task definitions
├── justfile              # Task runner (replaces Makefile)
├── Mustfile.ncl          # Nickel configuration contract
└── package.json          # Dev deps only (ReScript compiler)
```

## Common Tasks

### Development Setup

```bash
# Install ReScript compiler (dev dependency)
npm install

# Build the project
just build
# OR: rescript build

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

**Pure ReScript Implementation:**
All functionality is implemented in ReScript. The `*Impl.res` files contain the actual implementations, while the facade modules (without `Impl`) provide the public API. This allows for:
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
- ReScript standard library
- No npm runtime dependencies

## ReScript Best Practices

1. **Use @rescript/core Array module:**
   ```rescript
   Array.push(arr, item)->ignore
   Array.map(arr, fn)
   ```

2. **Escape reserved keywords:**
   ```rescript
   type linkStatus = {
     \"external": bool
   }
   ```

3. **Promise handling:**
   ```rescript
   let result = await someAsyncFn()
   ```

4. **External bindings:**
   ```rescript
   @scope("Deno") @val external args: array<string> = "args"
   ```

## CI/CD Enforcement

GitHub Actions enforce:
- **ts-blocker.yml**: No TypeScript files allowed
- **npm-bun-blocker.yml**: No npm/bun lock files
- **makefile-blocker.yml**: No Makefiles (use justfile)

## Resources

- [ReScript Documentation](https://rescript-lang.org/docs/manual/latest)
- [Deno Documentation](https://deno.land/manual)
- [just Command Runner](https://github.com/casey/just)
- [Nickel Configuration](https://nickel-lang.org/)

---

*This file is updated to reflect the pure ReScript architecture.*
