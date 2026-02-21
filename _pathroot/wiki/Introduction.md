# Introduction

Welcome, Head of DevOps. This guide is your walkthrough of a modular devtools scaffold built for clarity, introspection, and automation. It's designed to be teachable, tweakable, and explainable—so you can understand not just *what* it does, but *why* it does it.

## As You Read, Consider

- What assumptions are being made?
- How might this scale or evolve?
- What would you do differently?

## The Problem We're Solving

Modern dev environments are messy:

- Scripts break when paths change
- Tools get lost in the filesystem
- Configs are duplicated or hardcoded
- Environment variables become unmanageable

## What We Want

A system that:

| Goal | Description |
|------|-------------|
| **Discoverable** | Can be found from anywhere in the filesystem |
| **Self-aware** | Knows what kind of environment it's in |
| **Automatable** | Easy to scaffold, inspect, and script |
| **Maintainable** | Simple enough to understand and modify |

## Target Audience

- DevOps engineers managing multiple environments
- Developers who want consistent tooling across machines
- Teams standardizing on shared devtools configurations
- Anyone tired of "it works on my machine" problems

## Platform Support

| Platform | Status |
|----------|--------|
| Windows | Primary target |
| WSL | Supported |
| Linux | Planned |
| macOS | Planned |

## Next Steps

- Read [Core Concepts](Core-Concepts.md) to understand the two-marker system
- See [Directory Structure](Directory-Structure.md) for the standard layout
- Check [Integration](Integration.md) for RapidEE compatibility
