@ECHO OFF
REM SPDX-License-Identifier: PMPL-1.0-or-later
REM _pathroot entry point for Windows cmd

SETLOCAL EnableExtensions

REM Detect _pathroot installation
IF DEFINED PATHROOT_HOME (
    SET "PATHROOT_ROOT=%PATHROOT_HOME%"
) ELSE IF EXIST "%USERPROFILE%\.pathroot\env" (
    SET "PATHROOT_ROOT=%USERPROFILE%\.pathroot"
) ELSE (
    IF DEFINED XDG_DATA_HOME (
        SET "PATHROOT_ROOT=%XDG_DATA_HOME%\pathroot"
    ) ELSE (
        SET "PATHROOT_ROOT=%USERPROFILE%\.local\share\pathroot"
    )
)

REM Source environment
IF EXIST "%PATHROOT_ROOT%\env.cmd" (
    CALL "%PATHROOT_ROOT%\env.cmd"
)

REM Run validation
deno run --allow-read --allow-env "%PATHROOT_ROOT%\src\Validate.mjs" %*
