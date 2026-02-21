# Contributing to displace

Thank you for your interest in contributing to `displace`! We welcome contributions from everyone. To ensure a smooth and effective collaboration, please review these guidelines.

## Code of Conduct

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project, you agree to abide by its terms.

## How to Contribute

### Reporting Bugs

*   **Before reporting**: Please check the existing issues to see if your bug has already been reported.
*   **Create a new issue**: If not, open a new issue with a clear and concise title.
*   **Provide details**: Include as much detail as possible:
    *   Steps to reproduce the behavior.
    *   Expected outcome.
    *   Actual outcome.
    *   Your operating system, `displace` version, and Rust toolchain version.
    *   Any relevant logs or screenshots.

### Suggesting Enhancements

*   **Before suggesting**: Check existing issues and the [ROADMAP](ROADMAP.adoc) to see if your enhancement is already planned or discussed.
*   **Create a new issue**: Open a new issue with a clear and concise title.
*   **Describe your idea**: Explain the problem your suggestion solves, how it might be implemented, and its potential benefits.

### Pull Requests

1.  **Fork the repository** and clone it to your local machine.
2.  **Create a new branch** for your feature or bug fix: `git checkout -b feature/your-feature-name` or `bugfix/issue-number`.
3.  **Make your changes**: Write clean, well-documented code that adheres to the existing coding style.
4.  **Write tests**: Ensure your changes are covered by appropriate unit and integration tests.
5.  **Run tests**: Make sure all tests pass before submitting your pull request.
6.  **Update documentation**: If your changes affect `README.adoc`, `ROADMAP.adoc`, or any other documentation, please update them.
7.  **Commit your changes**: Write clear, concise commit messages. Follow conventional commits if applicable.
8.  **Push your branch** to your fork.
9.  **Open a Pull Request**: Submit a pull request to the `main` branch of the upstream repository.
    *   Provide a clear title and description for your changes.
    *   Reference any related issues.

## Development Setup

*   **Rust Toolchain**: Install Rust using `rustup`.
*   **Dependencies**: `cargo build` will fetch all necessary Rust dependencies.
*   **Container Tools**: For container-related development, ensure you have `buildah` or `docker` installed.

## AI Gatekeeper Protocol

This project adheres to the [AI Gatekeeper Protocol](0-AI-MANIFEST.a2ml). All AI agents interacting with this repository MUST follow the guidelines specified in `0-AI-MANIFEST.a2ml`. Ensure you read and understand it before making any automated changes.

---

We look forward to your contributions!
