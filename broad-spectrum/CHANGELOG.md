# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-22

### Added

**Core Features:**
- Complete CLI website auditor implementation
- Link checking with broken link detection
- Accessibility auditing (WCAG A/AA/AAA compliance)
- Performance metrics collection (Core Web Vitals estimation)
- SEO analysis (meta tags, structured data, content)
- Multiple report formats (Console, JSON, HTML, Markdown)

**ReScript Modules:**
- `Config.res` - Configuration types and defaults
- `UrlParser.res` - URL parsing and validation
- `Fetcher.res` - HTTP client with retry logic
- `LinkChecker.res` - Link validation
- `Accessibility.res` - WCAG compliance checking
- `Performance.res` - Performance analysis
- `SEO.res` - SEO auditing
- `Report.res` - Multi-format report generation
- `Auditor.res` - Main orchestrator

**TypeScript Bindings:**
- `ada.ts` - URL parsing (native URL API)
- `fetcher.ts` - HTTP fetch with timeout/retry
- `htmlParser.ts` - HTML parsing and link extraction
- `a11y.ts` - Accessibility rule checking
- `seoParser.ts` - SEO data extraction
- `report.ts` - Report formatting

**CLI Features:**
- Single URL auditing
- Multiple URL auditing from file
- Configurable concurrency
- Automatic retry with exponential backoff
- Verbose mode for debugging
- Help and version commands
- Custom user agent support
- Timeout configuration
- Enable/disable individual scanners

**Documentation:**
- Comprehensive README with examples
- Architecture documentation
- Contributing guidelines
- CLAUDE.md for AI-assisted development
- License (MIT)

**Tests:**
- URL parser tests
- Accessibility checker tests
- SEO analyzer tests
- Test infrastructure setup

**Examples:**
- Example URLs file
- Example configuration JSON
- Usage examples in README

### Technical Details

**Build System:**
- ReScript compiler configuration
- Deno task definitions
- npm scripts for building
- GenType for TypeScript FFI

**Performance:**
- Parallel scanner execution
- Batch-limited link checking
- Configurable concurrency (default: 10)
- Automatic retry logic (default: 3 attempts)
- Exponential backoff for retries

**Type Safety:**
- Full ReScript type checking
- TypeScript strict mode
- GenType-generated type definitions
- No runtime type errors

**Error Handling:**
- Result types for expected errors
- Option types for missing data
- Exception handling for unexpected errors
- Graceful degradation

### Design Decisions

- **ReScript over TypeScript** - Compile-time type safety, functional patterns
- **Deno over Node.js** - Security, built-in TypeScript, no node_modules
- **Separate Config module** - Solves circular dependencies
- **Native URL API** - Fast, standards-compliant parsing
- **Functional programming** - Immutability, pure functions, no side effects

### Known Limitations

- HTML parsing is regex-based (future: use proper parser)
- Performance metrics are estimated (future: integrate with Lighthouse)
- No JavaScript execution (future: headless browser support)
- Link checking is sequential per batch (future: optimize further)

### Migration Notes

This is a complete rewrite of the zotero-voyant-export Firefox/Zotero add-on
as a standalone CLI tool. No migration path exists from the previous version.

## [Unreleased]

### Planned Features

- [ ] WebSocket support for real-time monitoring
- [ ] Database integration for historical tracking
- [ ] Docker containerization
- [ ] CI/CD integration examples
- [ ] Web UI for report viewing
- [ ] Plugin system for custom checks
- [ ] Lighthouse integration
- [ ] Screenshot capture
- [ ] PDF report generation
- [ ] Caching layer (Redis)
- [ ] Distributed execution (worker pools)
- [ ] More comprehensive accessibility rules
- [ ] JavaScript execution (headless browser)
- [ ] Sitemap crawling
- [ ] robots.txt compliance checking

---

[1.0.0]: https://github.com/Hyperpolymath/broad-spectrum/releases/tag/v1.0.0
