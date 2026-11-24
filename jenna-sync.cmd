@echo off
REM ============================================================================
REM FILE: jenna-sync.cmd
REM PURPOSE: Native Windows Command Shim for `jenna-sync.sh` ("Jenna")
REM LICENSE: MIT License (Copyright (c) 2026 Michael P. Ragsdale / RaggieSoft)
REM ============================================================================
REM PLAIN-ENGLISH OVERVIEW FOR 100-LEVEL READERS:
REM   Why does this `.cmd` file exist alongside `jenna-sync.sh`?
REM     1. On Windows 11 Pro, PowerShell and Command Prompt can invoke `.cmd`
REM        files directly (`.\raggiesoft-deployment-tools\jenna-sync.cmd --push`)
REM        without needing PowerShell's `&` call operator or a quoted path to
REM        `C:\Program Files\Git\bin\bash.exe`.
REM     2. Why NOT pass `-m "Commit Message"` when an AI agent calls Jenna?
REM        Modern AI IDE permission prompts (like Google Antigravity's "Always
REM        Allow") fall back to exact command-string matching when quoted
REM        arguments change on every invocation! Instead, AI agents write the
REM        commit message to `ai-staging\jenna-commit-msg.txt` first and run
REM        the 100% constant, quote-free command:
REM          `.\raggiesoft-deployment-tools\jenna-sync.cmd --push`
REM        Jenna reads and immediately deletes `ai-staging\jenna-commit-msg.txt`,
REM        so clicking "Always Allow" ONCE matches every future deploy forever!
REM        (Manual terminal runs still support `-m "Message"` as usual.)
REM
REM   Inputs:
REM     - `%*`: Flags forwarded to `jenna-sync.sh` (`--push`, `--pull`, `--audit`).
REM   Output / Exit Code:
REM     - Propagates Jenna's exact POSIX/MS-DOS `ERRORLEVEL` (`0`..`4`) back to
REM       PowerShell (`$LASTEXITCODE`) and CI runners via `exit /b %ERRORLEVEL%`.
REM ============================================================================

REM `setlocal` isolates environment variables inside this batch script so we
REM never pollute the caller's PowerShell or CMD session.
setlocal

REM Resolve Git for Windows' native `bash.exe` (intentionally skipping
REM `C:\Windows\System32\bash.exe`, which is the WSL Linux VM stub!).
set "GIT_BASH="
if exist "C:\Program Files\Git\bin\bash.exe" (
    set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"
) else if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    set "GIT_BASH=C:\Program Files (x86)\Git\bin\bash.exe"
) else if defined LOCALAPPDATA (
    if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (
        set "GIT_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    )
)

if not defined GIT_BASH (
    echo [JENNA ERROR] Git Bash ^(bash.exe^) not found. Run .\init-windows.ps1 first! 1>&2
    exit /b 1
)

REM `%~dp0` expands to the drive + directory containing `jenna-sync.cmd` (e.g.
REM `Y:\raggiesoft-deployment-tools\`). Converting `\` -> `/` produces a clean
REM forward-slash path (`Y:/raggiesoft-deployment-tools/jenna-sync.sh`) for Git Bash.
set "JENNA_DIR=%~dp0"
set "JENNA_DIR=%JENNA_DIR:\=/%"

REM Execute `jenna-sync.sh` with all original arguments (`%*`) intact,
REM then return its exact integer exit status (`0` = full sync success).
"%GIT_BASH%" "%JENNA_DIR%jenna-sync.sh" %*
set "JENNA_EXIT=%ERRORLEVEL%"

endlocal & exit /b %JENNA_EXIT%
