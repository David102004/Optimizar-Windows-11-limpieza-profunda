<# 
Win11 25H2 Pro - "LTSC-like" cleanup (SAFE)
- Removes common preinstalled consumer apps (current user + provisioned)
- Disables Consumer Experiences, Copilot, Widgets, Chat icon
- Optionally uninstalls OneDrive
- Creates a restore point + logs

Run as Administrator.
#>

# -----------------------------
# SETTINGS
# -----------------------------
$RemoveOneDrive = $true    # set to $false if you want to keep OneDrive
$LogPath = "$env:SystemDrive\Win11_Cleanup_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

Start-Transcript -Path $LogPath -Force

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run PowerShell as Administrator." -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
  }
}

function New-RestorePointSafe {
  try {
    Write-Host "Creating restore point..." -ForegroundColor Cyan
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue | Out-Null
    Checkpoint-Computer -Description "Before Win11 cleanup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
    Write-Host "Restore point created." -ForegroundColor Green
  } catch {
    Write-Host "Restore point could not be created (not fatal): $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

function Set-RegDword {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][int]$Value
  )
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Remove-AppxForAllUsersSafe {
  param([string]$AppxNameLike)

  $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $AppxNameLike }
  foreach ($p in $pkgs) {
    try {
      Write-Host "Removing (AllUsers Appx): $($p.Name)" -ForegroundColor Cyan
      Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
    } catch {
      Write-Host "  Could not remove $($p.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }

  $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $AppxNameLike }
  foreach ($q in $prov) {
    try {
      Write-Host "Deprovisioning: $($q.DisplayName)" -ForegroundColor Cyan
      Remove-AppxProvisionedPackage -Online -PackageName $q.PackageName -ErrorAction Stop | Out-Null
    } catch {
      Write-Host "  Could not deprovision $($q.DisplayName): $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
}

function Uninstall-OneDriveSafe {
  if (-not $RemoveOneDrive) { return }
  Write-Host "Uninstalling OneDrive..." -ForegroundColor Cyan

  try { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } catch {}

  $od1 = "$env:SystemRoot\System32\OneDriveSetup.exe"
  $od2 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"

  $exe = $null
  if (Test-Path $od1) { $exe = $od1 }
  elseif (Test-Path $od2) { $exe = $od2 }

  if ($exe) {
    try {
      Start-Process -FilePath $exe -ArgumentList "/uninstall" -Wait -ErrorAction Stop
      Write-Host "OneDrive uninstall launched." -ForegroundColor Green
    } catch {
      Write-Host "Could not uninstall OneDrive: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  } else {
    Write-Host "OneDriveSetup.exe not found (skipping)." -ForegroundColor Yellow
  }

  # Optional: disable OneDrive file storage usage (policy)
  Set-RegDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1
}

# -----------------------------
# MAIN
# -----------------------------
Assert-Admin
New-RestorePointSafe

Write-Host "Exporting current Appx packages list..." -ForegroundColor Cyan
Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | Sort-Object Name | Out-File "$env:SystemDrive\Appx_AllUsers_Before.txt" -Encoding utf8
Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName | Sort-Object DisplayName | Out-File "$env:SystemDrive\Appx_Provisioned_Before.txt" -Encoding utf8

# -----------------------------
# DISABLE "CONSUMER" SURFACE / UI NOISE
# -----------------------------
Write-Host "Applying policies (consumer experiences / copilot / widgets / chat)..." -ForegroundColor Cyan

# Turn off Microsoft consumer experiences
Set-RegDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

# Disable Copilot (policy) + hide button
Set-RegDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-RegDword -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0

# Disable Widgets (policy)
Set-RegDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowWidgets" -Value 0

# Hide Chat icon
Set-RegDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -Value 3

# -----------------------------
# REMOVE COMMON PREINSTALLED APPS (SAFE LIST)
# (keeps Store, App Installer, WebView, Edge, etc.)
# -----------------------------
Write-Host "Removing common consumer apps..." -ForegroundColor Cyan

$removeList = @(
  "Clipchamp.Clipchamp",
  "Microsoft.549981C3F5F10",              # Cortana (if present)
  "Microsoft.BingNews",
  "Microsoft.BingWeather",
  "Microsoft.BingSports",
  "Microsoft.BingFinance",
  "Microsoft.GetHelp",
  "Microsoft.Getstarted",
  "Microsoft.MicrosoftSolitaireCollection",
  "Microsoft.People",
  "Microsoft.PowerAutomateDesktop",
  "Microsoft.Todos",
  "Microsoft.WindowsAlarms",
  "Microsoft.WindowsFeedbackHub",
  "Microsoft.WindowsMaps",
  "Microsoft.WindowsSoundRecorder",
  "Microsoft.ZuneMusic",
  "Microsoft.ZuneVideo",
  "Microsoft.GamingApp",
  "Microsoft.XboxApp",
  "Microsoft.XboxGameOverlay",
  "Microsoft.XboxGamingOverlay",
  "Microsoft.XboxIdentityProvider",
  "Microsoft.XboxSpeechToTextOverlay",
  "Microsoft.YourPhone",                  # Phone Link
  "Microsoft.MicrosoftOfficeHub",         # "Get Office" hub (you install Office anyway)
  "MicrosoftTeams",                       # old Teams consumer
  "MSTeams"                               # new Teams consumer name on some builds
)

foreach ($name in $removeList) {
  Remove-AppxForAllUsersSafe -AppxNameLike $name
}

# Optional OneDrive uninstall
Uninstall-OneDriveSafe

# -----------------------------
# FINAL: restart Explorer and inform restart
# -----------------------------
Write-Host "Restarting Explorer..." -ForegroundColor Cyan
try {
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Process explorer.exe
} catch {}

Write-Host ""
Write-Host "DONE. Recommended: RESTART Windows to apply everything." -ForegroundColor Green
Write-Host "Log saved to: $LogPath" -ForegroundColor Green
Write-Host "Backups: $env:SystemDrive\Appx_AllUsers_Before.txt and Appx_Provisioned_Before.txt" -ForegroundColor Green

Stop-Transcript | Out-Null