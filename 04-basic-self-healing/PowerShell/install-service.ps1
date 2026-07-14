# ============================================================
# INSTALL IIS SELF-HEALING AS WINDOWS SERVICE
# ============================================================

param(
    [string]$NSSMPath = ".\nssm.exe",
    [string]$ScriptPath = ".\iis-selfhealing.ps1",
    [string]$ServiceName = "IISSelfHealing",
    [string]$DisplayName = "IIS Self-Healing Service",
    [string]$Description = "Automatically monitors and restarts IIS applications when they fail"
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Check if NSSM exists
if (-not (Test-Path $NSSMPath)) {
    Write-Host "NSSM not found at $NSSMPath" -ForegroundColor Red
    Write-Host "Download from: https://nssm.cc/download" -ForegroundColor Yellow
    exit 1
}

# Check if service already exists
$ServiceExists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($ServiceExists) {
    Write-Host "Service '$ServiceName' already exists." -ForegroundColor Yellow
    $Response = Read-Host "Do you want to uninstall and reinstall? (y/n)"
    if ($Response -eq 'y') {
        & $NSSMPath stop $ServiceName
        & $NSSMPath remove $ServiceName confirm
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "Installation cancelled." -ForegroundColor Red
        exit 1
    }
}

# Get full paths
$NSSMPath = Resolve-Path $NSSMPath
$ScriptPath = Resolve-Path $ScriptPath
$ScriptDir = Split-Path $ScriptPath -Parent

# Install the service
Write-Host "Installing service '$ServiceName'..." -ForegroundColor Green

# Install using NSSM
& $NSSMPath install $ServiceName "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Set service parameters
& $NSSMPath set $ServiceName DisplayName $DisplayName
& $NSSMPath set $ServiceName Description $Description
& $NSSMPath set $ServiceName Start SERVICE_AUTO_START
& $NSSMPath set $ServiceName AppDirectory $ScriptDir

# Set failure recovery
& $NSSMPath set $ServiceName Failure ResetPeriod 86400
& $NSSMPath set $ServiceName Failure RestartDelay 5000
& $NSSMPath set $ServiceName Failure Action Restart 1000
& $NSSMPath set $ServiceName Failure Action Restart 1000
& $NSSMPath set $ServiceName Failure Action Restart 1000

# Set dependencies
& $NSSMPath set $ServiceName DependOnService W3SVC

# Start the service
Write-Host "Starting service..." -ForegroundColor Green
& $NSSMPath start $ServiceName

# Check service status
$Service = Get-Service -Name $ServiceName
if ($Service.Status -eq 'Running') {
    Write-Host "✓ Service '$ServiceName' installed and running successfully!" -ForegroundColor Green
    Write-Host "  Service will start automatically on system boot." -ForegroundColor Cyan
    Write-Host "  Logs are available in: $LogPath" -ForegroundColor Cyan
}
else {
    Write-Host "✗ Service installed but failed to start." -ForegroundColor Red
    Write-Host "  Check the event logs for errors." -ForegroundColor Yellow
}

Write-Host "`nService Management Commands:" -ForegroundColor Cyan
Write-Host "  nssm start $ServiceName" -ForegroundColor White
Write-Host "  nssm stop $ServiceName" -ForegroundColor White
Write-Host "  nssm restart $ServiceName" -ForegroundColor White
Write-Host "  nssm status $ServiceName" -ForegroundColor White
Write-Host "  nssm edit $ServiceName" -ForegroundColor White