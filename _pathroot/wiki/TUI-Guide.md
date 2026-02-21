# TUI Guide

The _pathroot Terminal User Interface (TUI) provides interactive management of devtools environments. Built in Ada/SPARK for reliability and safety.

## Overview

The TUI allows you to:

- Browse and switch environment profiles
- Manage PATH entries interactively
- Create and audit symbolic links
- View devtools logs
- Execute common operations safely

## Installation

```bash
# Build from source (requires GNAT)
cd ada/tui
gprbuild -P pathroot_tui.gpr

# Or install via devtools
pathroot install tui
```

## Usage

```bash
# Launch interactive TUI
pathroot-tui

# Launch with specific profile
pathroot-tui --profile test

# Transaction mode (for scripting)
pathroot-tui --transaction
```

## Interface

```
┌─────────────────────────────────────────────────────────────┐
│  _pathroot TUI v0.1.0                              [?] Help │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Environment: devtools                                       │
│  Profile:     default                                        │
│  Platform:    windows                                        │
│  Root:        C:\devtools                                    │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│  [E] Environment  [P] PATH  [L] Links  [G] Logs  [Q] Quit   │
└─────────────────────────────────────────────────────────────┘
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `E` | Environment browser |
| `P` | PATH editor |
| `L` | Link manager |
| `G` | Log viewer |
| `Q` | Quit |
| `?` | Help |
| `Tab` | Next panel |
| `Enter` | Select/Confirm |
| `Esc` | Cancel/Back |

## Panels

### Environment Browser

View and switch between environment profiles.

```
┌─ Profiles ──────────────────────────────────────────────────┐
│  ● default     Active profile                                │
│  ○ test        Testing environment                           │
│  ○ wsl         WSL compatibility mode                        │
│                                                              │
│  [Enter] Switch  [N] New  [D] Delete  [R] Rename            │
└─────────────────────────────────────────────────────────────┘
```

### PATH Editor

Manage PATH entries with visual feedback.

```
┌─ PATH Entries ──────────────────────────────────────────────┐
│  1. C:\devtools\bin                              [✓] Valid   │
│  2. C:\Windows\System32                          [✓] Valid   │
│  3. C:\oldtools\bin                              [✗] Missing │
│                                                              │
│  [A] Add  [E] Edit  [D] Delete  [↑↓] Move  [V] Validate     │
└─────────────────────────────────────────────────────────────┘
```

### Link Manager

Create and audit symbolic links.

```
┌─ Symbolic Links ────────────────────────────────────────────┐
│  Source                    Target                  Status    │
│  ────────────────────────────────────────────────────────── │
│  C:\devtools\bin\git.exe → C:\Git\bin\git.exe    [✓] OK     │
│  C:\devtools\bin\node.exe → C:\nodejs\node.exe   [✓] OK     │
│                                                              │
│  [N] New Link  [A] Audit All  [R] Repair  [X] Remove        │
└─────────────────────────────────────────────────────────────┘
```

### Log Viewer

Browse devtools logs with filtering.

```
┌─ Logs ──────────────────────────────────────────────────────┐
│  2025-01-15 10:23:45 [INFO] Profile switched to 'test'       │
│  2025-01-15 10:24:01 [WARN] PATH entry not found: C:\old     │
│  2025-01-15 10:24:15 [INFO] Link created: git.exe            │
│                                                              │
│  [F] Filter  [C] Clear  [E] Export  [/] Search              │
└─────────────────────────────────────────────────────────────┘
```

## Transaction Protocol

The TUI supports a transaction protocol for automation and integration with other tools.

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `QUERY:ENV` | Get environment info | `PATHROOT:QUERY:ENV` |
| `SET:PROFILE` | Switch profile | `PATHROOT:SET:PROFILE:test` |
| `LINK` | Create symbolic link | `PATHROOT:LINK:src:dst` |
| `AUDIT` | Run audit | `PATHROOT:AUDIT:links` |
| `PATH:ADD` | Add PATH entry | `PATHROOT:PATH:ADD:C:\bin` |
| `PATH:REMOVE` | Remove PATH entry | `PATHROOT:PATH:REMOVE:C:\old` |

### Usage

```bash
# Query environment
echo "PATHROOT:QUERY:ENV" | pathroot-tui --transaction

# Switch profile
echo "PATHROOT:SET:PROFILE:test" | pathroot-tui --transaction

# Batch operations
cat << EOF | pathroot-tui --transaction
PATHROOT:SET:PROFILE:production
PATHROOT:PATH:ADD:C:\production\bin
PATHROOT:AUDIT:links
EOF
```

### Response Format

```json
{
  "status": "ok",
  "command": "SET:PROFILE",
  "result": {
    "previous": "default",
    "current": "production"
  }
}
```

## Configuration

The TUI reads configuration from `_envbase` and can be customized:

```json
{
  "env": "devtools",
  "profile": "default",
  "platform": "windows",
  "tui": {
    "theme": "dark",
    "log_lines": 100,
    "auto_validate": true
  }
}
```

## Building from Source

### Requirements

- GNAT (Ada compiler)
- gprbuild
- ncurses (Linux) or Windows Console API

### Build Steps

```bash
cd ada/tui
gprbuild -P pathroot_tui.gpr -XBUILD_MODE=release
```

### Project Structure

```
ada/tui/
├── src/
│   ├── pathroot_tui.adb        # Main entry point
│   ├── pathroot_tui.ads        # Package spec
│   ├── ui/
│   │   ├── panels.adb          # Panel implementations
│   │   ├── widgets.adb         # UI widgets
│   │   └── themes.adb          # Color themes
│   ├── core/
│   │   ├── discovery.adb       # _pathroot discovery
│   │   ├── envbase.adb         # _envbase parsing
│   │   └── transactions.adb    # Transaction protocol
│   └── platform/
│       ├── windows.adb         # Windows-specific
│       └── posix.adb           # POSIX-specific
├── pathroot_tui.gpr            # GNAT project file
└── tests/
    └── test_pathroot_tui.adb   # Unit tests
```

## See Also

- [Integration](Integration.md) - Tool integration guide
- [Scripts Reference](Scripts-Reference.md) - Automation scripts
