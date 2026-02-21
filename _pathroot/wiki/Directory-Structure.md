# Directory Structure

The _pathroot system uses a standardized directory layout that separates concerns and provides predictable locations for all devtools components.

## Standard Layout

```
C:\devtools\
├── bin\        # Executables
├── scripts\    # Utility scripts
├── config\     # Configuration files
├── logs\       # Log outputs
├── temp\       # Temporary files
├── tools\      # Installed packages
├── _envbase    # Local environment metadata

C:\_pathroot    # Global root marker (at drive level)
```

## Directory Purposes

| Directory | Purpose | Examples |
|-----------|---------|----------|
| `bin/` | Executable binaries | `tool.exe`, `compiler.exe` |
| `scripts/` | Utility scripts | `build.ps1`, `deploy.bat` |
| `config/` | Configuration files | `settings.json`, `profiles.yaml` |
| `logs/` | Log outputs | `build.log`, `link-audit.txt` |
| `temp/` | Temporary files | Build artifacts, caches |
| `tools/` | Installed packages | Version-managed tools |

## Marker Files

| File | Location | Purpose |
|------|----------|---------|
| `_pathroot` | `C:\` | Points to devtools root |
| `_envbase` | `C:\devtools\` | Environment metadata |

## Creating the Structure

### Using the Scaffolder

```batch
:: Run the automation script
automkdir.bat
```

### Manual Creation

```batch
:: Create directory structure
mkdir C:\devtools\bin
mkdir C:\devtools\scripts
mkdir C:\devtools\config
mkdir C:\devtools\logs
mkdir C:\devtools\temp
mkdir C:\devtools\tools

:: Create markers
echo C:\devtools > C:\_pathroot
```

## Best Practices

### DO

- Keep executables in `bin/` and add to PATH
- Store all logs in `logs/` for centralized debugging
- Use `config/` for shareable configuration
- Clean `temp/` regularly

### DON'T

- Hardcode paths in scripts (use `_pathroot` discovery)
- Store secrets in `config/` (use a secrets manager)
- Mix logs with source files
- Delete `_envbase` or `_pathroot`

## Cross-Platform Considerations

| Platform | Pathroot Location | Devtools Root |
|----------|-------------------|---------------|
| Windows | `C:\_pathroot` | `C:\devtools` |
| WSL | `/mnt/c/_pathroot` | `/opt/devtools` |
| Linux | `/_pathroot` | `/opt/devtools` |
| macOS | `/_pathroot` | `/opt/devtools` |

## Integration with RapidEE

RapidEE can be used to:
- Add `C:\devtools\bin` to PATH
- Set environment variables pointing to devtools
- Visualize the environment variable hierarchy

See [Integration](Integration.md) for details.
