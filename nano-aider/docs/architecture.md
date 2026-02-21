# nano-aider Architecture

A narratable, audit-grade Ada TUI for nano/micro editor configuration.

## Overview

nano-aider is designed as a modular Ada application using the child package pattern for clean separation of concerns.

## Package Hierarchy

```
Nano_Aider (root)
├── Nano_Aider.TUI         -- Terminal User Interface
├── Nano_Aider.Options     -- Option discovery and management
├── Nano_Aider.Config      -- Configuration file handling
└── Nano_Aider.Profiles    -- Profile management
```

## Core Components

### Nano_Aider (Root Package)
- Application metadata (version, author, license)
- Common type definitions
- Editor type enumeration (Nano, Micro)

### Nano_Aider.TUI
- ncurses-based terminal interface
- Color scheme management
- View state machine (Categories → Options → Detail)
- Keyboard input handling
- Screen refresh and layout

### Nano_Aider.Options
- Static and dynamic option databases
- Category organization
- Hidden option tracking
- Version-specific availability
- Search functionality

### Nano_Aider.Config
- Configuration file parsing
- XDG directory support
- Export to nanorc/JSON formats
- Backup management

### Nano_Aider.Profiles
- Built-in profile definitions
- User profile management
- Profile switching
- Profile persistence

## Design Principles

1. **Ada 2022 Standard**: Modern language features for safety
2. **SPARK Annotations**: Critical sections formally verified
3. **Minimal Dependencies**: Only ncursesada required
4. **No Heap Allocation**: Stack-based where possible
5. **Cross-Platform**: Linux, macOS, BSD, Windows (MSYS2)

## Build Modes

| Mode    | Purpose                          |
|---------|----------------------------------|
| debug   | Development with full checks     |
| release | Production with optimization     |
| spark   | SPARK verification builds        |

## Data Flow

```
User Input
    │
    ▼
┌─────────────┐
│   TUI       │ ◄── Key events, screen refresh
└─────────────┘
    │
    ▼
┌─────────────┐
│  Options    │ ◄── Query options, search
└─────────────┘
    │
    ▼
┌─────────────┐
│  Config     │ ◄── Load/save configuration
└─────────────┘
    │
    ▼
┌─────────────┐
│  Profiles   │ ◄── Apply/manage profiles
└─────────────┘
```

## Future Extensions

- Plugin system via dynamic library loading
- AI-assisted configuration (optional local LLM)
- Multi-user profile synchronization
- Web-based configuration preview
