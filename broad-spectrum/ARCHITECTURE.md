# Architecture Documentation

## Overview

Broad Spectrum is a modular website auditing system built with functional programming principles using ReScript, with runtime bindings to Deno/TypeScript for system-level operations.

## Core Architecture

### Layer 1: Configuration & Types (Config.res)

The foundation layer defines all configuration types and defaults. This module has no dependencies and is imported by all other modules.

**Key Responsibilities:**
- Define `config` type with all audit parameters
- Provide sensible defaults
- Export helper functions for format conversion

**Design Decision:** Separate config module solves circular dependency issues between Auditor and domain modules.

### Layer 2: Foundation Modules

**UrlParser.res**
- URL parsing and validation
- Absolute URL construction
- Same-domain checking
- Link extraction from HTML

**Fetcher.res**
- HTTP request handling
- Timeout management
- Automatic retry with exponential backoff
- Error categorization (Network, Timeout, HTTP)

**Design Pattern:** Both modules expose pure functions and delegate I/O to TypeScript bindings.

### Layer 3: Domain Scanners

Each scanner is independent and focuses on a single audit dimension:

**LinkChecker.res**
- Validates URLs in parallel (respecting concurrency limits)
- Tracks broken links, redirects, response times
- Deduplicates URLs before checking
- Returns comprehensive statistics

**Accessibility.res**
- WCAG compliance checking
- Image alt text validation
- Form label verification
- Heading hierarchy checks
- Calculates weighted score based on severity

**Performance.res**
- Page size analysis
- Resource counting and categorization
- Core Web Vitals estimation
- Performance score calculation

**SEO.res**
- Meta tag extraction and validation
- Open Graph and Twitter Cards
- Heading structure analysis
- Content length analysis
- Structured data detection

**Design Pattern:** All scanners follow the same interface:
1. Take HTML + URL as input
2. Return results object with findings + score
3. Calculate scores independently
4. No cross-scanner dependencies

### Layer 4: Report Generation (Report.res)

**Responsibilities:**
- Aggregate results from all scanners
- Calculate weighted overall score
- Format output in multiple formats (Console/JSON/HTML/Markdown)
- Handle missing scanner results gracefully

**Scoring Weights:**
- Link checking: 20%
- Accessibility: 30%
- Performance: 30%
- SEO: 20%

### Layer 5: Orchestration (Auditor.res)

The top-level module that coordinates the entire audit process:

**Workflow:**
1. Validate URL
2. Fetch HTML content
3. Launch all enabled scanners in parallel
4. Collect results
5. Generate report
6. Handle errors gracefully

**Concurrency Model:**
- All scanners run in parallel via Promise.all
- Individual link checks batch-limited
- Configurable max concurrency per scanner

## TypeScript/Deno Bindings Layer

Located in `src/bindings/`, these provide the FFI between ReScript and Deno:

**ada.ts** - URL parsing using native URL API
**fetcher.ts** - HTTP client with fetch() and AbortController
**htmlParser.ts** - HTML parsing and link extraction
**a11y.ts** - Accessibility rule checking
**seoParser.ts** - SEO data extraction
**report.ts** - Report formatting

**Design Decision:** Keep I/O and external dependencies in TypeScript, business logic in ReScript. This provides:
- Type safety where it matters (business logic)
- Flexibility where needed (system integration)
- Clear separation of concerns

## Data Flow

```
CLI (main.ts)
    ↓
Auditor.auditWebsite()
    ↓
Fetcher.fetch() → [TypeScript: HTTP]
    ↓
Parse HTML → [TypeScript: Parsing]
    ↓
Parallel Execution:
    ├→ LinkChecker.checkLinks()
    ├→ Accessibility.check()
    ├→ Performance.analyze()
    └→ SEO.analyze()
    ↓
Report.create()
    ↓
Report.format() → [TypeScript: Formatting]
    ↓
Output (Console/File)
```

## Error Handling Strategy

**Three-Tier Approach:**

1. **Result Types** - Used for expected errors
   ```rescript
   type result<'a, 'b> = Ok('a) | Error('b)
   ```

2. **Option Types** - Used for missing data
   ```rescript
   type option<'a> = Some('a) | None
   ```

3. **Exception Handling** - Used for unexpected errors
   ```rescript
   try {
     // ... risky code
   } catch {
   | Exn.Error(obj) => Error(message)
   }
   ```

**Error Propagation:**
- Scanners never throw - return Result types
- Fetcher returns Result with categorized errors
- Auditor catches all exceptions and converts to Error results
- CLI exits with appropriate exit codes

## State Management

**Immutable by Default:**
- All data structures are immutable
- Mutations use `ref` type explicitly
- No global mutable state

**Refs Used For:**
- Score accumulation in calculate functions
- Result collection in loops
- Seen sets for deduplication

## Concurrency Model

**Parallel Scanner Execution:**
```rescript
let (linkCheck, accessibility, performance, seo) =
  await Promise.all4((
    linkCheckPromise,
    accessibilityPromise,
    performancePromise,
    seoPromise,
  ))
```

**Batch-Limited Link Checking:**
```rescript
for i in 0 to batchCount {
  let batch = Array.slice(urls, ~start, ~end)
  let results = await Promise.all(
    batch->Array.map(url => checkLink(url))
  )
}
```

**Rate Limiting:**
- Configurable max concurrency
- Sequential batch processing
- Polite delays between requests

## Type Safety

**ReScript Benefits:**
- Compile-time type checking
- No `null` or `undefined` (use Option instead)
- Exhaustive pattern matching
- Guaranteed totality

**GenType Integration:**
- Auto-generates TypeScript definitions
- Type-safe FFI boundary
- Editor autocomplete across languages

## Testing Strategy

**Unit Tests** (Deno test framework)
- Test individual bindings
- Mock external dependencies
- Fast, isolated tests

**Integration Tests**
- Test full audit flow
- Use real HTTP requests
- Validate report generation

**Type Tests**
- ReScript compiler catches type errors
- No runtime type checking needed

## Performance Considerations

**Optimization Techniques:**
1. Parallel scanner execution
2. Batched link checking
3. URL deduplication
4. Efficient string operations
5. Minimal allocations in hot paths

**Bottlenecks:**
- Network I/O (link checking)
- HTML parsing (large pages)
- Report formatting (HTML generation)

## Extension Points

**Adding New Scanners:**
1. Create new module in `src/`
2. Follow scanner interface pattern
3. Add TypeScript binding if needed
4. Wire into Auditor.res
5. Update Report.res scoring weights

**Adding New Report Formats:**
1. Add format type to Config.res
2. Implement formatter in report.ts
3. Add case in Report.format()

**Adding New Checks:**
1. Extend scanner module
2. Add new issue types
3. Update scoring logic
4. Document in README

## Security Considerations

**Input Validation:**
- All URLs validated before use
- HTML parsing uses safe methods
- No `eval()` or code execution

**Resource Limits:**
- Timeout on all HTTP requests
- Maximum concurrency limits
- Request size limits (implicit via timeout)

**Permissions (Deno):**
- `--allow-net`: Required for HTTP requests
- `--allow-read`: Required for reading URL files
- `--allow-env`: Optional for environment config

## Future Architecture

**Potential Enhancements:**
1. Plugin system for custom scanners
2. Persistent storage (database integration)
3. Distributed execution (worker pools)
4. Real-time monitoring (WebSocket support)
5. Caching layer (Redis integration)

## Build Pipeline

```
ReScript Source (.res files)
    ↓ [rescript compiler]
JavaScript Modules (.js files)
    ↓ [gentype]
TypeScript Definitions (.gen.tsx files)
    ↓ [deno runtime]
Execution
```

**No Bundler Required:**
- ES modules natively supported
- Deno handles imports
- Fast iteration cycles

## Deployment Options

1. **Standalone Binary** (deno compile)
2. **Docker Container**
3. **CI/CD Integration** (GitHub Actions, GitLab CI)
4. **Serverless Function** (Deno Deploy)
5. **Cron Job** (scheduled audits)

## Monitoring & Observability

**Logging:**
- Verbose mode for debugging
- Error messages to stderr
- Results to stdout

**Metrics:**
- Execution time tracking
- Response time measurements
- Success/failure counts

**Future Additions:**
- Structured logging (JSON)
- Metrics export (Prometheus)
- Distributed tracing (OpenTelemetry)
