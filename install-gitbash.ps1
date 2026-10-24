# --- BROOKE: THE QUARTERMASTER (Intune / Windows Edition) ---
# "I don't route the code, and I don't mix the audio. I just make sure everyone
#  else has the exact tools they need to do their jobs before they ask for them."

Write-Output "BROOKE: Grabbing the clipboard. Provisioning your Windows workstation..."
Write-Output ""

# ---------------------------------------------------------------------------
# 1. DEFINE THE GEAR LIST (WinGet Package IDs)
# ---------------------------------------------------------------------------

$wingetPackages = @(
    # Command Line & Scripting
    "Git.Git",
    "PHP.PHP.8.4",
    "jqlang.jq",
    "Gyan.FFmpeg",
    "JohnMacFarlane.Pandoc",

    # Utilities & Packaging
    "7zip.7zip",
    "Rclone.Rclone",
    "JRSoftware.InnoSetup",
    "NSIS.NSIS",

    # Productivity & Development Environment
    "TheDocumentFoundation.LibreOffice",
    "Microsoft.VisualStudioCode",
    "Obsidian.Obsidian",

    # Web Browsers
    "Mozilla.Firefox",
    "Mozilla.Firefox.DeveloperEdition",
    "Google.Chrome",
    "BraveSoftware.BraveBrowser"
)

# ---------------------------------------------------------------------------
# 2. RESOLVE WINGET
# ---------------------------------------------------------------------------

Write-Output "BROOKE: Locating WinGet..."

$wingetPath = $null

# First preference:
# Locate the actual WinGet executable supplied by Desktop App Installer.
# This is preferable for anything that will later execute as SYSTEM.

$wingetCandidates = Get-ChildItem `
    -Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
    -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending

if ($wingetCandidates) {
    $wingetPath = $wingetCandidates[0].FullName
    Write-Output "   [OK] Found Desktop App Installer WinGet:"
    Write-Output "        $wingetPath"
}

# Second preference:
# Ask PowerShell to resolve WinGet in the current user context.

if (-not $wingetPath) {
    $wingetCommand = Get-Command "winget.exe" -ErrorAction SilentlyContinue

    if ($wingetCommand) {
        $wingetPath = $wingetCommand.Source
        Write-Output "   [OK] Found WinGet through current user PATH:"
        Write-Output "        $wingetPath"
    }
}

# Stop rather than continuing with an invalid/null executable.

if (-not $wingetPath) {
    Write-Error "BROOKE: WinGet could not be located. Provisioning cannot continue."
    exit 1
}

# Verify that WinGet actually executes.

Write-Output "   -> Verifying WinGet..."

try {
    $wingetVersion = & $wingetPath --version

    if ($LASTEXITCODE -ne 0) {
        throw "WinGet returned exit code $LASTEXITCODE."
    }

    Write-Output "   [OK] WinGet is operational: $wingetVersion"
}
catch {
    Write-Error "BROOKE: WinGet was located but could not be executed: $_"
    exit 1
}

Write-Output "------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# 3. PROVISION NATIVE PACKAGES
# ---------------------------------------------------------------------------

Write-Output "BROOKE: Auditing and provisioning system gear..."

foreach ($pkg in $wingetPackages) {

    Write-Output "   -> Requesting supply drop: $pkg"

    $arguments = @(
        "install"
        "--id"
        $pkg
        "--exact"
        "--accept-package-agreements"
        "--accept-source-agreements"
        "--silent"
        "--disable-interactivity"
    )

    try {
        $process = Start-Process `
            -FilePath $wingetPath `
            -ArgumentList $arguments `
            -Wait `
            -NoNewWindow `
            -PassThru

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq -1978335189) {
            Write-Output "      [OK] Secured: $pkg"
        }
        else {
            Write-Warning "Package $pkg returned exit code $($process.ExitCode)."
        }
    }
    catch {
        Write-Warning "Package $pkg could not be processed: $_"
    }
}

Write-Output "------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# 4. PROVISION REAL-ESRGAN
# ---------------------------------------------------------------------------

$esrganDir = "C:\Tools\Real-ESRGAN"
$esrganExe = Join-Path $esrganDir "realesrgan-ncnn-vulkan.exe"

$esrganUrl = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip"

$esrganZip = Join-Path $env:TEMP "realesrgan.zip"

if (-not (Test-Path $esrganExe)) {

    Write-Output "BROOKE: Fetching Real-ESRGAN for Harper..."

    try {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $esrganDir |
        Out-Null

        Invoke-WebRequest `
            -Uri $esrganUrl `
            -OutFile $esrganZip

        Expand-Archive `
            -Path $esrganZip `
            -DestinationPath $esrganDir `
            -Force

        Remove-Item $esrganZip -Force -ErrorAction SilentlyContinue

        if (Test-Path $esrganExe) {
            Write-Output "   [OK] Secured: Real-ESRGAN"
        }
        else {
            Write-Warning "Real-ESRGAN extraction completed, but the expected executable was not found."
        }
    }
    catch {
        Write-Warning "Real-ESRGAN provisioning failed: $_"

        Remove-Item $esrganZip `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output "   [OK] Secured: Real-ESRGAN (already present)"
}

Write-Output "------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# 5. REGISTER AUTO-UPDATE TASK
# ---------------------------------------------------------------------------

Write-Output "BROOKE: Registering the morning maintenance route..."

$taskName = "Brooke_Quartermaster_AutoUpdate"

# The scheduled task runs as SYSTEM. Do not blindly register a user-specific
# WindowsApps alias for a SYSTEM task.

if ($wingetPath -like "C:\Program Files\WindowsApps\*") {

    try {
        $action = New-ScheduledTaskAction `
            -Execute $wingetPath `
            -Argument "upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"

        $trigger = New-ScheduledTaskTrigger -AtStartup

        Register-ScheduledTask `
            -Action $action `
            -Trigger $trigger `
            -TaskName $taskName `
            -Description "Silently updates all WinGet packages at system boot." `
            -User "NT AUTHORITY\SYSTEM" `
            -RunLevel Highest `
            -Force |
        Out-Null

        Write-Output "   [OK] Secured: Auto-Update Scheduled Task"
        Write-Output "        Task: $taskName"
        Write-Output "        Executable: $wingetPath"
    }
    catch {
        Write-Warning "BROOKE: Could not register the WinGet auto-update task: $_"
    }
}
else {
    Write-Warning "BROOKE: WinGet resolved to a user-specific path:"
    Write-Warning "        $wingetPath"
    Write-Warning "        The SYSTEM auto-update task will NOT be created."
    Write-Warning "        Package provisioning itself can still complete normally."
}

Write-Output "------------------------------------------------------------------"
Write-Output "BROOKE: Audit complete. The armory is locked and loaded."