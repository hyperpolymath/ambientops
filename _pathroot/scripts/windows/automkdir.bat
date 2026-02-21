@echo off
:: _pathroot Scaffold Generator
:: Version: 0.1.0
:: Creates the complete devtools directory structure with markers
setlocal enabledelayedexpansion

:: Configuration
set "DEVTOOLS_ROOT=C:\devtools"
set "PATHROOT_FILE=C:\_pathroot"
set "VERSION=0.1.0"

:: Parse arguments
set "DRY_RUN=0"
set "CUSTOM_ROOT="

:parse_args
if "%~1"=="" goto :main
if /i "%~1"=="--dry-run" set "DRY_RUN=1" & shift & goto :parse_args
if /i "%~1"=="--root" set "CUSTOM_ROOT=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--help" goto :show_help
shift
goto :parse_args

:show_help
echo _pathroot Scaffold Generator v%VERSION%
echo.
echo Usage: automkdir.bat [options]
echo.
echo Options:
echo   --dry-run    Show what would be created without making changes
echo   --root PATH  Use custom devtools root (default: C:\devtools)
echo   --help       Show this help message
echo.
exit /b 0

:main
:: Apply custom root if specified
if not "%CUSTOM_ROOT%"=="" set "DEVTOOLS_ROOT=%CUSTOM_ROOT%"

echo.
echo ============================================
echo  _pathroot Scaffold Generator v%VERSION%
echo ============================================
echo.
echo Configuration:
echo   Devtools Root: %DEVTOOLS_ROOT%
echo   Pathroot File: %PATHROOT_FILE%
echo   Dry Run:       %DRY_RUN%
echo.

if "%DRY_RUN%"=="1" (
    echo [DRY RUN MODE - No changes will be made]
    echo.
)

:: Create directory structure
echo Creating directory structure...
call :create_dir "%DEVTOOLS_ROOT%\bin"
call :create_dir "%DEVTOOLS_ROOT%\scripts"
call :create_dir "%DEVTOOLS_ROOT%\config"
call :create_dir "%DEVTOOLS_ROOT%\logs"
call :create_dir "%DEVTOOLS_ROOT%\temp"
call :create_dir "%DEVTOOLS_ROOT%\tools"

:: Create _pathroot marker
echo.
echo Creating _pathroot marker...
if "%DRY_RUN%"=="1" (
    echo   [DRY] Would create: %PATHROOT_FILE%
    echo   [DRY] Contents: %DEVTOOLS_ROOT%
) else (
    echo %DEVTOOLS_ROOT%> "%PATHROOT_FILE%"
    if exist "%PATHROOT_FILE%" (
        echo   Created: %PATHROOT_FILE%
    ) else (
        echo   ERROR: Failed to create %PATHROOT_FILE%
        echo   (Try running as Administrator)
    )
)

:: Create _envbase metadata
echo.
echo Creating _envbase metadata...
if "%DRY_RUN%"=="1" (
    echo   [DRY] Would create: %DEVTOOLS_ROOT%\_envbase
) else (
    (
        echo {
        echo   "env": "devtools",
        echo   "profile": "default",
        echo   "platform": "windows",
        echo   "version": "%VERSION%",
        echo   "created": "%date%"
        echo }
    ) > "%DEVTOOLS_ROOT%\_envbase"
    if exist "%DEVTOOLS_ROOT%\_envbase" (
        echo   Created: %DEVTOOLS_ROOT%\_envbase
    ) else (
        echo   ERROR: Failed to create _envbase
    )
)

echo.
echo ============================================
if "%DRY_RUN%"=="1" (
    echo  Dry run complete. No changes made.
) else (
    echo  Scaffold complete!
)
echo ============================================
echo.
echo Next steps:
echo   1. Add %DEVTOOLS_ROOT%\bin to your PATH
echo   2. Run envbase.ps1 to verify installation
echo.

endlocal
exit /b 0

:create_dir
if "%DRY_RUN%"=="1" (
    echo   [DRY] Would create: %~1
) else (
    if not exist "%~1" (
        mkdir "%~1" 2>nul
        if exist "%~1" (
            echo   Created: %~1
        ) else (
            echo   ERROR: Failed to create %~1
        )
    ) else (
        echo   Exists:  %~1
    )
)
exit /b 0
