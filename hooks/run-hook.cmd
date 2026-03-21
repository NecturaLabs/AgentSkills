: ; # Polyglot bash/cmd wrapper -- runs on both Windows and Unix
: ; exec bash "${0%/*}/$1" "$@" 2>/dev/null; exit $?
@echo off
setlocal enabledelayedexpansion

set "HOOK_NAME=%~1"
set "SCRIPT_DIR=%~dp0"

:: Find bash (Git Bash, WSL, or MSYS2)
set "BASH_CMD="
where bash >nul 2>&1 && set "BASH_CMD=bash"
if not defined BASH_CMD (
    for %%G in (
        "%ProgramFiles%\Git\bin\bash.exe"
        "%ProgramFiles(x86)%\Git\bin\bash.exe"
        "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    ) do (
        if exist %%G (
            set "BASH_CMD=%%G"
            goto :found
        )
    )
)
:found
if not defined BASH_CMD exit /b 0

%BASH_CMD% "%SCRIPT_DIR%%HOOK_NAME%" %*
