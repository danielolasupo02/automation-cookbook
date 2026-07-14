<#
.SYNOPSIS
    Rollback script for web application deployment
.DESCRIPTION
    This script rolls back a web application deployment
.PARAMETER PolicyName
    Name of the deployment policy
.PARAMETER DeploymentPath
    Path to the deployment directory
.PARAMETER DeploymentStatus
    Deployment status object (JSON)
#>

param(
    [string]$PolicyName,
    [string]$DeploymentPath,
    [string]$DeploymentStatus
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Executing Web Application Rollback" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Policy: $PolicyName" -ForegroundColor Green
Write-Host "Deployment Path: $DeploymentPath" -ForegroundColor Green

# Load deployment status
$Status = $DeploymentStatus | ConvertFrom-Json
if ($Status) {
    Write-Host "Deployment Status:" -ForegroundColor Yellow
    $Status | Format-Table -AutoSize
}

# Check if backup exists
$BackupPath = "$DeploymentPath.backup"
if (Test-Path $BackupPath) {
    Write-Host "Found backup at: $BackupPath" -ForegroundColor Green

    # Remove current deployment
    Write-Host "Removing current deployment..." -ForegroundColor Yellow
    Remove-Item -Path "$DeploymentPath\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Restore backup
    Write-Host "Restoring backup..." -ForegroundColor Yellow
    Copy-Item -Path "$BackupPath\*" -Destination $DeploymentPath -Recurse -Force

    Write-Host "Rollback completed successfully!" -ForegroundColor Green
}
else {
    Write-Host "No backup found at: $BackupPath" -ForegroundColor Red
    Write-Host "Rollback failed!" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
exit 0