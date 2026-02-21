# Contributing to nano-aider

Thank you for your interest in contributing to nano-aider!

## Project Overview

nano-aider is an Ada 2022 TUI application for discovering and managing nano/micro editor configuration options.

## Development Requirements

- **GNAT** (Ada compiler) 12.0 or later
- **Alire** package manager
- **ncurses** development libraries
- **GNATprove** (optional, for SPARK verification)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/hyperpolymath/nano-aider.git
cd nano-aider

# Build with Alire
alr build

# Run tests
./ci-scripts/test.sh

# Run the application
./bin/nano-aider
```

## Code Style

- Follow GNAT Ada coding conventions
- 80 character line limit
- 3-space indentation
- Add SPARK annotations for new critical sections
- Include SPDX license headers on all source files

## Contribution Guidelines

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/my-feature`)
3. **Write** tests for new functionality
4. **Ensure** all tests pass
5. **Submit** a pull request

## Licensing

This project is dual-licensed:
- **MIT License** - Permissive, minimal restrictions
- **AGPL-3.0-or-later** - Copyleft, network service protection

All contributions must be licensed under both licenses.

## Contributor Rituals

- Forks must preserve changelogs and audit trails
- All commits should be narratable: describe what changed and why
- Keep the README and ROADMAP updated when adding features

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include your OS, Ada compiler version, and steps to reproduce
- For security issues, see SECURITY.md
