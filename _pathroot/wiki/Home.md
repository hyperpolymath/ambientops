# _pathroot Wiki

**An Open Guide to Modular Devtools Environments**

Welcome to the _pathroot documentation. This system provides a standardized approach to managing development tool environments with clarity, introspection, and automation.

## Quick Navigation

| Page | Description |
|------|-------------|
| [Introduction](Introduction.md) | Why _pathroot exists and what problems it solves |
| [Core Concepts](Core-Concepts.md) | The two-marker system: `_pathroot` and `_envbase` |
| [Directory Structure](Directory-Structure.md) | Standard layout for devtools environments |
| [Scripts Reference](Scripts-Reference.md) | Automation scripts and scaffolding tools |
| [FAQ](FAQ.md) | Frequently Asked Questions |
| [Integration](Integration.md) | RapidEE, modshells, nano-aider interoperability |
| [TUI Guide](TUI-Guide.md) | Ada-based Terminal User Interface |

## Design Principles

- **Discoverable**: Any tool can find the devtools root from anywhere
- **Introspectable**: Environments describe themselves via metadata
- **Automatable**: Scaffolding and configuration are scriptable
- **Cross-platform**: Windows-first, with WSL/Linux/macOS extensibility

## Getting Started

```bash
# Clone the scaffold
git clone https://gitlab.com/hyperpolymath/_pathroot

# Windows: Run the scaffolder
automkdir.bat

# Inspect your environment
powershell -File envbase.ps1
```

## Related Projects

- [modshells](https://gitlab.com/hyperpolymath/modshells) - Modular shell configurations
- [nano-aider](https://gitlab.com/hyperpolymath/nano-aider) - Lightweight AI-assisted development
- [RapidEE](https://www.rapidee.com/) - Windows environment variables editor

## License

PMPL-1.0-or-later
