# Scripts Reference

This appendix contains all the automation scripts for managing _pathroot environments.

## Windows Scripts

### Create `_pathroot` File (CMD)

```batch
:: Create _pathroot file pointing to devtools root
echo C:\devtools > C:\_pathroot
```

### Read `_pathroot` (PowerShell)

```powershell
# Read _pathroot and store in variable
$Pathroot = Get-Content -Path "C:\_pathroot"
Write-Host "Devtools root is at: $Pathroot"
```

### Create `_envbase` File (PowerShell)

```powershell
# Create _envbase file with basic metadata
$envbase = @{
    env      = "devtools"
    profile  = "default"
    platform = "windows"
}
$envbase | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\devtools\_envbase"
```

### Read and Parse `_envbase` (PowerShell)

```powershell
# Read and parse _envbase metadata
$envbase = Get-Content -Path "C:\devtools\_envbase" | ConvertFrom-Json
Write-Host "Environment: $($envbase.env)"
Write-Host "Profile: $($envbase.profile)"
Write-Host "Platform: $($envbase.platform)"
```

### Safe Link Creation with Audit Log (PowerShell)

```powershell
# Create symbolic link and log action
$src = "C:\devtools\bin\tool.exe"
$dst = "C:\tools\tool.exe"
New-Item -ItemType SymbolicLink -Path $dst -Target $src
Add-Content -Path "C:\devtools\logs\link-audit.txt" -Value "$dst -> $src"
```

---

## Cross-Platform Scripts

### Dry-Run Link Creation (LFE/Erlang)

```lisp
(defun dry-run-link (src dst)
  (io:format "~s would link to ~s~n" (list src dst)))
```

### Registry Discovery (Guile Scheme)

```scheme
(define (read-pathroot)
  (call-with-input-file "C:/_pathroot"
    (lambda (port) (read-line port))))

(display (string-append "Devtools root: " (read-pathroot)))
```

---

## Automation Script: `automkdir.bat`

Full scaffolding script that creates the entire structure:

```batch
@echo off
setlocal

:: Configuration
set DEVTOOLS_ROOT=C:\devtools
set PATHROOT_FILE=C:\_pathroot

:: Create directory structure
echo Creating directory structure...
mkdir "%DEVTOOLS_ROOT%\bin" 2>nul
mkdir "%DEVTOOLS_ROOT%\scripts" 2>nul
mkdir "%DEVTOOLS_ROOT%\config" 2>nul
mkdir "%DEVTOOLS_ROOT%\logs" 2>nul
mkdir "%DEVTOOLS_ROOT%\temp" 2>nul
mkdir "%DEVTOOLS_ROOT%\tools" 2>nul

:: Create _pathroot marker
echo Creating _pathroot marker...
echo %DEVTOOLS_ROOT% > "%PATHROOT_FILE%"

:: Create _envbase metadata
echo Creating _envbase metadata...
(
echo {
echo   "env": "devtools",
echo   "profile": "default",
echo   "platform": "windows"
echo }
) > "%DEVTOOLS_ROOT%\_envbase"

echo.
echo Scaffold complete!
echo   Pathroot: %PATHROOT_FILE%
echo   Devtools: %DEVTOOLS_ROOT%

endlocal
```

---

## Introspection Script: `envbase.ps1`

Reads both markers and displays environment information:

```powershell
# envbase.ps1 - Environment introspection script

param(
    [string]$PathrootPath = "C:\_pathroot"
)

# Read _pathroot
if (Test-Path $PathrootPath) {
    $DevtoolsRoot = (Get-Content $PathrootPath).Trim()
    Write-Host "Devtools Root: $DevtoolsRoot" -ForegroundColor Green
} else {
    Write-Host "ERROR: _pathroot not found at $PathrootPath" -ForegroundColor Red
    exit 1
}

# Read _envbase
$EnvbasePath = Join-Path $DevtoolsRoot "_envbase"
if (Test-Path $EnvbasePath) {
    $Envbase = Get-Content $EnvbasePath | ConvertFrom-Json
    Write-Host "`nEnvironment Metadata:" -ForegroundColor Cyan
    Write-Host "  Environment: $($Envbase.env)"
    Write-Host "  Profile:     $($Envbase.profile)"
    Write-Host "  Platform:    $($Envbase.platform)"
} else {
    Write-Host "WARNING: _envbase not found at $EnvbasePath" -ForegroundColor Yellow
}

# List available tools
$BinPath = Join-Path $DevtoolsRoot "bin"
if (Test-Path $BinPath) {
    $Tools = Get-ChildItem $BinPath -Filter "*.exe" | Select-Object -ExpandProperty Name
    if ($Tools) {
        Write-Host "`nAvailable Tools:" -ForegroundColor Cyan
        $Tools | ForEach-Object { Write-Host "  - $_" }
    }
}
```

---

## Usage Examples

### Quick Setup

```batch
:: One-liner setup
automkdir.bat && powershell -File envbase.ps1
```

### Profile Switching

```powershell
# Switch to test profile
$envbase = Get-Content "C:\devtools\_envbase" | ConvertFrom-Json
$envbase.profile = "test"
$envbase | ConvertTo-Json | Set-Content "C:\devtools\_envbase"
```

### Validate Installation

```powershell
# Check if _pathroot system is properly configured
if ((Test-Path "C:\_pathroot") -and (Test-Path "C:\devtools\_envbase")) {
    Write-Host "SUCCESS: _pathroot system is configured" -ForegroundColor Green
} else {
    Write-Host "ERROR: _pathroot system is not configured" -ForegroundColor Red
}
```
