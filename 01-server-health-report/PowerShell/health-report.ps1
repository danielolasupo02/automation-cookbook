# ============================================================
# SERVER HEALTH REPORT - Main Script
# ============================================================
#
# DESCRIPTION:
#   This script collects CPU, memory, and disk utilization
#   from multiple servers and sends a report via email.
#
# USAGE:
#   1. Edit config.ps1 with your settings
#   2. Edit servers.csv with your server list
#   3. Create Windows Credential Manager entry for SMTP (see config.ps1)
#   4. Run the script: .\health-report.ps1
#
# PREREQUISITES:
#   - PowerShell 5.1 or higher
#   - For Excel reports: Install-Module ImportExcel
#   - Network access to target servers (WinRM enabled)
#   - SMTP server access for email delivery
#
# CREDENTIAL MANAGEMENT:
#   This script uses Windows Credential Manager to securely store
#   SMTP credentials. Create the credential using:
#   cmdkey /add:SMTP_CRED /user:your-email@domain.com /pass:YourPassword
#
# ============================================================

# ---------- SCRIPT INITIALIZATION ----------
# Clear any errors
$ErrorActionPreference = "Continue"

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load configuration
. "$ScriptDir\config.ps1"

# Load functions
. "$ScriptDir\functions.ps1"

# ---------- VALIDATE PREREQUISITES ----------
Write-Log "Starting Server Health Report Script" -Level "INFO" -Color "Cyan"
Write-Log "========================================" -Level "INFO" -Color "Cyan"

# Check if servers.csv exists
if (!(Test-Path $ServersCSVPath)) {
    Write-Log "servers.csv not found at $ServersCSVPath" -Level "ERROR" -Color "Red"
    Write-Log "Please create servers.csv with columns: ServerName,IPAddress" -Level "INFO" -Color "Yellow"
    exit 1
}

# Create output directory if it doesn't exist
if (!(Test-Path $ReportOutputPath)) {
    New-Item -ItemType Directory -Path $ReportOutputPath -Force | Out-Null
    Write-Log "Created output directory: $ReportOutputPath" -Level "INFO" -Color "Green"
}

# ---------- LOAD SERVER LIST ----------
Write-Log "Loading server list from $ServersCSVPath" -Level "INFO" -Color "Cyan"
$Servers = Import-Csv -Path $ServersCSVPath
Write-Log "Found $($Servers.Count) servers" -Level "INFO" -Color "Green"

# ---------- GET SERVER PERFORMANCE DATA ----------
$ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"
$AllServerData = @()
$FailedServers = 0

Write-Log "Starting performance data collection..." -Level "INFO" -Color "Cyan"

foreach ($Server in $Servers) {
    Write-Log "Processing server: $($Server.ServerName)" -Level "INFO" -Color "Cyan"

    # Test connection to server
    if (Test-ServerConnection -ServerName $Server.ServerName -IPAddress $Server.IPAddress) {
        # Collect performance data
        $ServerData = Get-ServerPerformance -ServerName $Server.ServerName -IPAddress $Server.IPAddress -Counters $PerformanceCounters

        # Add server metadata
        $ServerData | Add-Member -MemberType NoteProperty -Name "Role" -Value $Server.Role
        $ServerData | Add-Member -MemberType NoteProperty -Name "Description" -Value $Server.Description

        $AllServerData += $ServerData

        if ($ServerData.Status -eq "Failed") {
            $FailedServers++
        }
    } else {
        $FailedServers++
        # Add placeholder data for failed server
        $FailedData = [PSCustomObject]@{
            ServerName = $Server.ServerName
            IPAddress = $Server.IPAddress
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Status = "Failed - Unreachable"
            Role = $Server.Role
            Description = $Server.Description
        }
        # Add placeholder values for all counters
        foreach ($Counter in $PerformanceCounters) {
            $PropertyName = $Counter.Name -replace "[^a-zA-Z0-9_\-]", "_"
            $FailedData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value "N/A"
        }
        $AllServerData += $FailedData
    }
}

Write-Log "Data collection complete. $($AllServerData.Count) servers processed, $FailedServers failed." -Level "INFO" -Color "Cyan"

# ---------- GENERATE REPORT ----------
Write-Log "Generating report in $ReportFormat format..." -Level "INFO" -Color "Cyan"

$ReportFile = $null

if ($ReportFormat -eq "EXCEL") {
    $ReportFile = Generate-ExcelReport -ServerData $AllServerData -OutputPath $ReportOutputPath -ReportDate $ReportDate
} else {
    $ReportFile = Generate-CSVReport -ServerData $AllServerData -OutputPath $ReportOutputPath -ReportDate $ReportDate
}

# If Excel generation failed, fallback to CSV
if (-not $ReportFile -and $ReportFormat -eq "EXCEL") {
    Write-Log "Falling back to CSV format" -Level "WARNING" -Color "Yellow"
    $ReportFile = Generate-CSVReport -ServerData $AllServerData -OutputPath $ReportOutputPath -ReportDate $ReportDate
}

if (-not $ReportFile) {
    Write-Log "Failed to generate report in any format" -Level "ERROR" -Color "Red"
    exit 1
}

# ---------- SEND EMAIL ----------
# Create email body
$EmailBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; }
        .success { color: #27ae60; }
        .warning { color: #f39c12; }
        .error { color: #e74c3c; }
        table { border-collapse: collapse; width: 100%; }
        th { background-color: #3498db; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Server Health Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p><strong>Total Servers:</strong> $($AllServerData.Count)</p>
        <p><strong>Successful:</strong> <span class="success">$($AllServerData.Where({$_.Status -eq 'Success'}).Count)</span></p>
        <p><strong>Failed:</strong> <span class="error">$FailedServers</span></p>
        <p><strong>Report Format:</strong> $ReportFormat</p>
        <p><strong>Report File:</strong> $(Split-Path $ReportFile -Leaf)</p>
    </div>
    <h2>Summary</h2>
    <p>Please find attached the detailed server health report.</p>
    <p><strong>Note:</strong> This report contains CPU, memory, and disk utilization data for all servers.</p>
    <hr>
    <p style="font-size: 12px; color: #7f8c8d;">This is an automated report generated by the Server Health Monitoring System.</p>
</body>
</html>
"@

# Get stored credentials
$Credential = Get-StoredCredential -CredentialName $CredentialName

# Prepare email subject with date
$EmailSubject = "$EmailSubjectPrefix - $(Get-Date -Format 'yyyy-MM-dd')"

# Send email
$EmailSent = Send-EmailReport -Subject $EmailSubject -Body $EmailBody -AttachmentPath $ReportFile -To $EmailTo -From $EmailFrom -SMTPServer $SMTPServer -Port $SMTPPort -UseSSL $SMTPUseSSL -Credential $Credential

# ---------- CLEANUP AND EXIT ----------
if ($EmailSent) {
    Write-Log "Script completed successfully!" -Level "SUCCESS" -Color "Green"
    exit 0
} else {
    Write-Log "Script completed with errors. Check logs for details." -Level "ERROR" -Color "Red"
    exit 1
}