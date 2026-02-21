# nano-aider

**Ada TUI for nano/micro Editor Configuration**

[![Ada 2022](https://img.shields.io/badge/Language-Ada_2022-blue?logo=ada)](https://ada-lang.io)
[![ncurses TUI](https://img.shields.io/badge/TUI-ncurses-green)](https://invisible-island.net/ncurses/)
[![SPARK Ready](https://img.shields.io/badge/SPARK-Ready-purple)](https://www.adacore.com/about-spark)
image:https://img.shields.io/badge/License-MPL_2.0-blue.svg[MPL-2.0-or-later,link="https://opensource.org/licenses/MPL-2.0"]

> Discover and manage the extensive—and often hidden—configuration options in nano and micro text editors.

## The Problem

Both `nano` and `micro` have **hundreds of configuration options**—many undocumented, hidden behind compile-time flags, or scattered across multiple files. nano-aider exposes them all through an interactive TUI.

## Quick Start

```bash
# Install via Alire (recommended)
alr get nano_aider
cd nano_aider*
alr build

# Or build from source
git clone https://github.com/hyperpolymath/nano-aider.git
cd nano-aider
gprbuild -P nano_aider.gpr -XNANO_AIDER_BUILD_MODE=release
./bin/nano-aider
```

### Prerequisites

- **GNAT** (Ada compiler) 12.0+
- **Alire** package manager
- **ncurses** development libraries

## Features

| Feature | Description |
|---------|-------------|
| **Option Discovery** | Detects all nano/micro options, including hidden ones |
| **Interactive TUI** | Browse, search, and modify settings with curses interface |
| **Profile Management** | Switch between Minimal, Developer, Writer, Power User profiles |
| **Configuration Export** | Generate valid `.nanorc` or `settings.json` files |
| **SPARK Verification** | Critical sections formally verified for correctness |

## TUI Preview

```
+-------------- nano-aider - Editor Configuration TUI ---------------+
|                                                                     |
|  Configuration Categories:                                          |
|                                                                     |
|    > Display (15 options)                                           |
|      Editing (12 options)                                           |
|      Hidden/Undocumented (25 options)  <-- The secret sauce         |
|                                                                     |
+---------------------------------------------------------------------+
| [h]elp | [/]search | [q]uit | [Enter]select | [Esc]back             |
+---------------------------------------------------------------------+
```

## Documentation

- **[README.adoc](README.adoc)** - Full documentation with examples
- **[ROADMAP.adoc](ROADMAP.adoc)** - Development roadmap (v0.1.0 → v10.0.0)
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines
- **[docs/architecture.md](docs/architecture.md)** - Technical architecture

## License

Dual-licensed under **MIT** OR **PMPL-1.0-or-later** — choose whichever suits your needs.

## Acknowledgments

- [GNU nano](https://www.nano-editor.org) and [micro](https://micro-editor.github.io) projects
- The Ada community and [Alire](https://alire.ada.dev) ecosystem
- AdaCore for GNAT and SPARK technologies

---

*Made with Ada by [Hyper Polymath](https://github.com/hyperpolymath)*
