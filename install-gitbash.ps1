# --- BROOKE: THE QUARTERMASTER (Intune / Windows Edition) ---
# "I don't route the code, and I don't mix the audio. I just make sure everyone
#  else has the exact tools they need to do their jobs before they ask for them."

Write-Output "👱‍♀️ BROOKE: Grabbing the clipboard. Provisioning your Windows workstation..."
Write-Output ""

# 1. DEFINE THE GEAR LIST (Winget Package IDs)
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

# 2. RESOLVE WINGET IN SYSTEM CONTEXT
$wingetPath = Get-ChildItem -Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1

if (-not $wingetPath) {
    Write-Output "   ⚠️  Could not resolve direct Winget path. Falling back to system PATH."
    $wingetPath = "winget.exe"
}

# 3. PROVISION NATIVE PACKAGES
Write-Output "   📋 Auditing and provisioning system gear..."

foreach ($pkg in $wingetPackages) {
    Write-Output "   -> Requesting supply drop: $pkg"
    
    $arguments = "install --id $pkg --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity"
    
    $process = Start-Process -FilePath $wingetPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    
    # Winget exit code 0 means success, -1978335189 means already installed
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq -1978335189) {
        Write-Output "      ✅ Secured: $pkg"
    } else {
        Write-Output "      ⚠️  Warning: $pkg returned exit code $($process.ExitCode)."
    }
}

Write-Output "------------------------------------------------------------------"

# 4. PROVISION REAL-ESRGAN (Manual Binary Extraction)
$esrganDir = "C:\Tools\Real-ESRGAN"
$esrganUrl = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip"
$esrganZip = "$env:TEMP\realesrgan.zip"

if (-not (Test-Path "$esrganDir\realesrgan-ncnn-vulkan.exe")) {
    Write-Output "   -> Fetching Real-ESRGAN for Harper..."
    New-Item -ItemType Directory -Force -Path $esrganDir | Out-Null
    Invoke-WebRequest -Uri $esrganUrl -OutFile $esrganZip
    Expand-Archive -Path $esrganZip -DestinationPath $esrganDir -Force
    Remove-Item $esrganZip -Force
    Write-Output "      ✅ Secured: Real-ESRGAN"
} else {
    Write-Output "      ✅ Secured: Real-ESRGAN (Already present)"
}

Write-Output "------------------------------------------------------------------"

# 5. REGISTER AUTO-UPDATE TASK
Write-Output "   -> Registering Brooke's morning maintenance route..."

$taskName = "Brooke_Quartermaster_AutoUpdate"
$action = New-ScheduledTaskAction -Execute $wingetPath -Argument "upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
$trigger = New-ScheduledTaskTrigger -AtStartup

# Registering to run silently as the SYSTEM account
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Silently updates all WinGet packages at system boot." -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force

Write-Output "      ✅ Secured: Auto-Update Scheduled Task"
Write-Output "------------------------------------------------------------------"
Write-Output "👱‍♀️ BROOKE: Audit complete. The armory is locked and loaded."