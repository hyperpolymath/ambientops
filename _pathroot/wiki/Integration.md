# Integration Guide

This guide covers how _pathroot integrates with external tools and projects.

## RapidEE Integration

[RapidEE](https://www.rapidee.com/) is a Windows environment variables editor that provides visual management of PATH and other environment variables.

### Recommended Setup

1. **Add devtools bin to PATH**
   - Open RapidEE as Administrator
   - Navigate to System Variables → Path
   - Add `C:\devtools\bin`

2. **Create DEVTOOLS_ROOT variable**
   ```
   Variable: DEVTOOLS_ROOT
   Value: C:\devtools
   ```

3. **Create PATHROOT variable** (optional)
   ```
   Variable: PATHROOT
   Value: C:\_pathroot
   ```

### Benefits

| Feature | Benefit |
|---------|---------|
| Visual PATH management | Easily reorder, add, remove entries |
| Variable expansion | See resolved values |
| Color coding | Identify invalid paths |
| Backup/restore | Save environment configurations |

### Automation with RapidEE

RapidEE supports command-line operations:

```batch
:: Export current environment
rapidee.exe /export "C:\devtools\config\env-backup.reg"

:: Import environment configuration
rapidee.exe /import "C:\devtools\config\env-backup.reg"
```

---

## modshells Integration

[modshells](https://gitlab.com/hyperpolymath/modshells) provides modular shell configurations.

### Configuration

Add to your modshells profile:

```powershell
# ~/.config/modshells/profile.ps1

# Load _pathroot environment
$PathrootFile = "C:\_pathroot"
if (Test-Path $PathrootFile) {
    $env:DEVTOOLS_ROOT = (Get-Content $PathrootFile).Trim()
    $env:PATH = "$env:DEVTOOLS_ROOT\bin;$env:PATH"

    # Load _envbase
    $EnvbaseFile = Join-Path $env:DEVTOOLS_ROOT "_envbase"
    if (Test-Path $EnvbaseFile) {
        $envbase = Get-Content $EnvbaseFile | ConvertFrom-Json
        $env:DEVTOOLS_PROFILE = $envbase.profile
        $env:DEVTOOLS_PLATFORM = $envbase.platform
    }
}
```

### Shell-Specific Configurations

**Bash/Zsh (Linux/WSL):**

```bash
# ~/.bashrc or ~/.zshrc

# Load _pathroot environment
if [ -f "/_pathroot" ]; then
    export DEVTOOLS_ROOT=$(cat /_pathroot)
    export PATH="$DEVTOOLS_ROOT/bin:$PATH"

    if [ -f "$DEVTOOLS_ROOT/_envbase" ]; then
        export DEVTOOLS_PROFILE=$(jq -r '.profile' "$DEVTOOLS_ROOT/_envbase")
    fi
fi
```

**Fish:**

```fish
# ~/.config/fish/config.fish

if test -f /_pathroot
    set -gx DEVTOOLS_ROOT (cat /_pathroot)
    fish_add_path $DEVTOOLS_ROOT/bin
end
```

---

## nano-aider Integration

[nano-aider](https://gitlab.com/hyperpolymath/nano-aider) is a lightweight AI-assisted development tool.

### Configuration

Create a nano-aider configuration that uses _pathroot:

```json
{
  "project_root": "${DEVTOOLS_ROOT}",
  "log_path": "${DEVTOOLS_ROOT}/logs/nano-aider.log",
  "config_path": "${DEVTOOLS_ROOT}/config/nano-aider.json"
}
```

### Auto-Discovery

nano-aider can auto-discover the _pathroot environment:

```typescript
// Deno-based discovery
async function discoverPathroot(): Promise<string | null> {
  const pathrootPaths = [
    "C:\\_pathroot",           // Windows
    "/mnt/c/_pathroot",        // WSL
    "/_pathroot",              // Linux/macOS
  ];

  for (const path of pathrootPaths) {
    try {
      const content = await Deno.readTextFile(path);
      return content.trim();
    } catch {
      continue;
    }
  }
  return null;
}
```

---

## TUI Integration

The Ada-based TUI (see [TUI Guide](TUI-Guide.md)) provides interactive management of _pathroot environments.

### Features

| Feature | Description |
|---------|-------------|
| Environment browser | View and switch profiles |
| Path editor | Modify PATH entries interactively |
| Link manager | Create/audit symbolic links |
| Log viewer | Browse devtools logs |

### Transaction Protocol

The TUI supports a transaction protocol for automation:

```
PATHROOT:QUERY:ENV
PATHROOT:SET:PROFILE:test
PATHROOT:LINK:src:dst
PATHROOT:AUDIT:links
```

---

## API Reference

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DEVTOOLS_ROOT` | Path to devtools directory |
| `DEVTOOLS_PROFILE` | Current profile name |
| `DEVTOOLS_PLATFORM` | Platform identifier |
| `PATHROOT` | Path to _pathroot marker file |

### JSON Schema for `_envbase`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "env": {
      "type": "string",
      "description": "Environment name"
    },
    "profile": {
      "type": "string",
      "description": "Active profile name"
    },
    "platform": {
      "type": "string",
      "enum": ["windows", "linux", "darwin", "wsl"],
      "description": "Platform identifier"
    }
  },
  "required": ["env", "profile", "platform"]
}
```

---

## Cross-Tool Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                     Development Workflow                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  RapidEE ──────► Sets PATH/Variables                         │
│       │                                                       │
│       ▼                                                       │
│  _pathroot ────► Discovered by all tools                     │
│       │                                                       │
│       ▼                                                       │
│  modshells ────► Loads environment in shells                 │
│       │                                                       │
│       ▼                                                       │
│  nano-aider ───► Uses devtools for AI assistance             │
│       │                                                       │
│       ▼                                                       │
│  TUI ──────────► Interactive management                      │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```
