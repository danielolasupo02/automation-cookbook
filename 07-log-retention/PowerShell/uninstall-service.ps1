# ============================================================
# UNINSTALL LOG RETENTION SERVICE
# ============================================================

param(
    [string]$NSSMPath = ".\nssm.exe",
    [string]$ServiceName = "LogRetention"
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Check if NSSM exists
if (-not (Test-Path $NSSMPath)) {
    Write-Host "NSSM not found at $NSSMPath" -ForegroundColor Red
    exit 1
}

# Check if service exists
$ServiceExists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $ServiceExists) {
    Write-Host "Service '$ServiceName' does not exist." -ForegroundColor Yellow
    exit 0
}

# Stop the service
Write-Host "Stopping service '$ServiceName'..." -ForegroundColor Yellow
& $NSSMPath stop $ServiceName

# Remove the service
Write-Host "Removing service '$ServiceName'..." -ForegroundColor Yellow
& $NSSMPath remove $ServiceName confirm

Write-Host "✓ Service '$ServiceName' uninstalled successfully!" -ForegroundColor Green