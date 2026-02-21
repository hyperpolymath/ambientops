# Mustfile.ncl - Nickel configuration for Broad Spectrum Website Auditor
# Based on hyperpolymath/mustfile specification
# This file defines deployment contracts and build constraints

let Contract = {
  # Project metadata
  name = "broad-spectrum",
  version = "1.0.0",
  description = "CLI website auditor for security, accessibility, performance, and SEO",

  # Language policy - strictly enforced
  languages = {
    allowed = [
      "rescript",   # Primary application language
      "nickel",     # Configuration language
      "bash",       # Build scripts only
    ],
    banned = [
      "typescript", # Use ReScript instead
      "javascript", # Only generated from ReScript
      "go",         # Use Rust if systems code needed
      "python",     # Except SaltStack
      "kotlin",     # Use Tauri/Dioxus for mobile
      "swift",      # Use Tauri/Dioxus for mobile
    ],
  },

  # Package management policy
  package_managers = {
    allowed = [
      "deno",       # Runtime package management via deno.json imports
      "guix",       # Primary system package manager
      "nix",        # Fallback system package manager
    ],
    banned = [
      "npm",        # No runtime npm deps (dev deps for ReScript compiler OK)
      "bun",        # No bun
      "pnpm",       # No pnpm
      "yarn",       # No yarn
    ],
  },

  # Build system policy
  build = {
    # ReScript compiles to JS, Deno runs it
    compiler = "rescript",
    runtime = "deno",

    # Required build files
    required_files = [
      "rescript.json",
      "deno.json",
      "justfile",
      "Mustfile.ncl",
    ],

    # Forbidden build files
    banned_files = [
      "Makefile",
      "GNUmakefile",
      "makefile",
      "package-lock.json",
      "bun.lockb",
      ".npmrc",
      "tsconfig.json",
    ],
  },

  # Security requirements
  security = {
    # Minimum hash algorithm for dependencies
    min_hash_algorithm = "sha256",

    # No hardcoded secrets
    no_secrets = true,

    # HTTPS only for external URLs
    https_only = true,

    # Required security documentation
    required_docs = [
      "SECURITY.md",
      ".well-known/security.txt",
    ],
  },

  # Documentation requirements (RSR compliance)
  documentation = {
    required = [
      "README.adoc",
      "LICENSE.txt",
      "SECURITY.md",
      "CONTRIBUTING.md",
      "CODE_OF_CONDUCT.md",
      "MAINTAINERS.md",
      "CHANGELOG.md",
      "ARCHITECTURE.md",
    ],
  },

  # CI/CD requirements
  ci = {
    platform = "github-actions",
    required_workflows = [
      "ci.yml",
      "ts-blocker.yml",
      "npm-bun-blocker.yml",
      "makefile-blocker.yml",
    ],
  },
}

in Contract
