<#
.SYNOPSIS
    _pathroot Environment Introspection Script

.DESCRIPTION
    Reads _pathroot and _envbase markers to display environment information.
    Useful for debugging, profile switching, and tooling integration.

.PARAMETER PathrootPath
    Path to the _pathroot marker file. Default: C:\_pathroot

.PARAMETER Format
    Output format: text, json, or env. Default: text

.PARAMETER Validate
    Run validation checks on the environment.

.EXAMPLE
    .\envbase.ps1
    Displays environment information in text format.

.EXAMPLE
    .\envbase.ps1 -Format json
    Outputs environment information as JSON.

.EXAMPLE
    .\envbase.ps1 -Validate
    Validates the _pathroot environment configuration.

.NOTES
    Version: 0.1.0
    Part of the _pathroot devtools system.
#>

[CmdletBinding()]
param(
    [string]$PathrootPath = "C:\_pathroot",
    [ValidateSet("text", "json", "env")]
    [string]$Format = "text",
    [switch]$Validate
)

$Version = "0.1.0"

function Get-PathrootInfo {
    param([string]$PathrootPath)

    $info = @{
        pathroot_file = $PathrootPath
        pathroot_exists = $false
        devtools_root = $null
        envbase_exists = $false
        envbase = $null
        tools = @()
        validation = @()
    }

    # Read _pathroot
    if (Test-Path $PathrootPath) {
        $info.pathroot_exists = $true
        $info.devtools_root = (Get-Content $PathrootPath -ErrorAction SilentlyContinue).Trim()
    }

    # Read _envbase
    if ($info.devtools_root) {
        $envbasePath = Join-Path $info.devtools_root "_envbase"
        if (Test-Path $envbasePath) {
            $info.envbase_exists = $true
            try {
                $info.envbase = Get-Content $envbasePath -Raw | ConvertFrom-Json
            } catch {
                $info.validation += "ERROR: _envbase contains invalid JSON"
            }
        }

        # List tools
        $binPath = Join-Path $info.devtools_root "bin"
        if (Test-Path $binPath) {
            $info.tools = Get-ChildItem $binPath -Filter "*.exe" -ErrorAction SilentlyContinue |
                          Select-Object -ExpandProperty Name
        }
    }

    return $info
}

function Test-PathrootEnvironment {
    param($info)

    $results = @()

    # Check _pathroot exists
    if (-not $info.pathroot_exists) {
        $results += @{ check = "_pathroot exists"; status = "FAIL"; message = "File not found: $($info.pathroot_file)" }
    } else {
        $results += @{ check = "_pathroot exists"; status = "PASS"; message = $info.pathroot_file }
    }

    # Check devtools root exists
    if ($info.devtools_root -and (Test-Path $info.devtools_root)) {
        $results += @{ check = "devtools root exists"; status = "PASS"; message = $info.devtools_root }
    } else {
        $results += @{ check = "devtools root exists"; status = "FAIL"; message = "Directory not found" }
    }

    # Check _envbase exists
    if ($info.envbase_exists) {
        $results += @{ check = "_envbase exists"; status = "PASS"; message = "Valid JSON" }
    } else {
        $results += @{ check = "_envbase exists"; status = "WARN"; message = "File not found or invalid" }
    }

    # Check required directories
    $requiredDirs = @("bin", "scripts", "config", "logs", "temp", "tools")
    foreach ($dir in $requiredDirs) {
        $dirPath = Join-Path $info.devtools_root $dir
        if (Test-Path $dirPath) {
            $results += @{ check = "$dir/ exists"; status = "PASS"; message = $dirPath }
        } else {
            $results += @{ check = "$dir/ exists"; status = "WARN"; message = "Not found" }
        }
    }

    # Check bin in PATH
    $binPath = Join-Path $info.devtools_root "bin"
    if ($env:PATH -split ";" | Where-Object { $_ -eq $binPath }) {
        $results += @{ check = "bin in PATH"; status = "PASS"; message = "Found in PATH" }
    } else {
        $results += @{ check = "bin in PATH"; status = "WARN"; message = "Not in PATH" }
    }

    return $results
}

function Format-TextOutput {
    param($info, $validation)

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host " _pathroot Environment Inspector v$Version" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""

    if ($info.pathroot_exists) {
        Write-Host "Pathroot:     " -NoNewline
        Write-Host $info.pathroot_file -ForegroundColor Green
        Write-Host "Devtools Root:" -NoNewline
        Write-Host " $($info.devtools_root)" -ForegroundColor Green
    } else {
        Write-Host "Pathroot:     " -NoNewline
        Write-Host "NOT FOUND" -ForegroundColor Red
    }

    Write-Host ""

    if ($info.envbase) {
        Write-Host "Environment Metadata:" -ForegroundColor Yellow
        Write-Host "  env:      $($info.envbase.env)"
        Write-Host "  profile:  $($info.envbase.profile)"
        Write-Host "  platform: $($info.envbase.platform)"
        if ($info.envbase.version) {
            Write-Host "  version:  $($info.envbase.version)"
        }
    } else {
        Write-Host "Environment Metadata: " -NoNewline
        Write-Host "NOT FOUND" -ForegroundColor Yellow
    }

    if ($info.tools.Count -gt 0) {
        Write-Host ""
        Write-Host "Available Tools:" -ForegroundColor Yellow
        $info.tools | ForEach-Object { Write-Host "  - $_" }
    }

    if ($validation) {
        Write-Host ""
        Write-Host "Validation Results:" -ForegroundColor Yellow
        foreach ($result in $validation) {
            $color = switch ($result.status) {
                "PASS" { "Green" }
                "WARN" { "Yellow" }
                "FAIL" { "Red" }
                default { "White" }
            }
            Write-Host "  [$($result.status)] " -ForegroundColor $color -NoNewline
            Write-Host "$($result.check): $($result.message)"
        }
    }

    Write-Host ""
}

function Format-JsonOutput {
    param($info, $validation)

    $output = @{
        version = $Version
        pathroot = @{
            file = $info.pathroot_file
            exists = $info.pathroot_exists
        }
        devtools = @{
            root = $info.devtools_root
            envbase = $info.envbase
        }
        tools = $info.tools
    }

    if ($validation) {
        $output.validation = $validation
    }

    $output | ConvertTo-Json -Depth 5
}

function Format-EnvOutput {
    param($info)

    if ($info.devtools_root) {
        Write-Output "DEVTOOLS_ROOT=$($info.devtools_root)"
    }
    if ($info.envbase) {
        Write-Output "DEVTOOLS_PROFILE=$($info.envbase.profile)"
        Write-Output "DEVTOOLS_PLATFORM=$($info.envbase.platform)"
        Write-Output "DEVTOOLS_ENV=$($info.envbase.env)"
    }
}

# Main execution
$info = Get-PathrootInfo -PathrootPath $PathrootPath
$validation = if ($Validate) { Test-PathrootEnvironment -info $info } else { $null }

switch ($Format) {
    "json" { Format-JsonOutput -info $info -validation $validation }
    "env"  { Format-EnvOutput -info $info }
    default { Format-TextOutput -info $info -validation $validation }
}
