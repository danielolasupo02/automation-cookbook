# ============================================================
# INFRASTRUCTURE MONITOR - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Continuously monitors server health metrics and sends
#   alerts via Email, Teams, and Slack.
#
# USAGE:
#   As a service: Install using NSSM or .NET Service
#   Manual: .\monitor-service.ps1
#
# ============================================================

# ---------- SCRIPT INITIALIZATION ----------
$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load configuration
. "$ScriptDir\config.ps1"

# Load functions
. "$ScriptDir\functions.ps1"

# ---------- GLOBAL STATE ----------
$AlertState = @{}  # Tracks last alert time per server/type
$ServerConfigs = @{}  # Cached server configurations
$LastSummaryReport = $null

# ---------- MAIN MONITORING LOOP ----------
function Start-Monitoring {
    Write-MonitorLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-MonitorLog "Starting Infrastructure Health Monitor Service" -Level "INFO" -Component "SERVICE"
    Write-MonitorLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-MonitorLog "Monitoring Interval: $MonitoringInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-MonitorLog "Alert Cooldown: $AlertCooldown seconds" -Level "INFO" -Component "SERVICE"
    Write-MonitorLog "Parallel Monitoring: $EnableParallelMonitoring" -Level "INFO" -Component "SERVICE"

    # Load server list
    $Servers = Get-ServerList -FilePath $ServerListPath
    if ($Servers.Count -eq 0) {
        Write-MonitorLog "No servers found in $ServerListPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-MonitorLog "Monitoring $($Servers.Count) servers" -Level "INFO" -Component "SERVICE"

    # Cache server configurations
    foreach ($Server in $Servers) {
        $ServerConfigs[$Server] = Get-ServerThresholds -ServerName $Server
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-MonitorLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-MonitorLog "Monitoring Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            # Collect metrics from all servers
            $AllMetrics = @()
            $FailedServers = @()

            if ($EnableParallelMonitoring) {
                # Parallel collection
                $Jobs = @()
                foreach ($Server in $Servers) {
                    $ServerConfig = $ServerConfigs[$Server]

                    # Check circuit breaker
                    if (-not (Check-CircuitBreaker -ServerName $Server)) {
                        Write-MonitorLog "Skipping $Server (circuit breaker open)" -Level "WARNING" -Component "SERVICE"
                        continue
                    }

                    $Job = Start-Job -ScriptBlock {
                        param($ServerName, $ServerConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1
                        Get-ServerMetrics -ServerName $ServerName -ServerConfig $ServerConfig
                    } -ArgumentList $Server, $ServerConfig

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelThreads) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($Result) {
                                    $AllMetrics += $Result
                                    Update-CircuitBreaker -ServerName $Result.ServerName -Success ($Result.Status -ne 'Error')
                                }
                                Remove-Job -Job $_ -Force
                            }
                            $Jobs = $Jobs | Where-Object { $_.State -eq 'Running' }
                        }
                        else {
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }

                # Wait for remaining jobs
                while ($Jobs.Count -gt 0) {
                    $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                    $Completed | ForEach-Object {
                        $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                        if ($Result) {
                            $AllMetrics += $Result
                            Update-CircuitBreaker -ServerName $Result.ServerName -Success ($Result.Status -ne 'Error')
                        }
                        Remove-Job -Job $_ -Force
                    }
                    $Jobs = $Jobs | Where-Object { $_.State -eq 'Running' }
                    if ($Jobs.Count -gt 0) {
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
            else {
                # Sequential collection
                foreach ($Server in $Servers) {
                    $ServerConfig = $ServerConfigs[$Server]

                    # Check circuit breaker
                    if (-not (Check-CircuitBreaker -ServerName $Server)) {
                        Write-MonitorLog "Skipping $Server (circuit breaker open)" -Level "WARNING" -Component "SERVICE"
                        continue
                    }

                    $Metrics = Get-ServerMetrics -ServerName $Server -ServerConfig $ServerConfig
                    $AllMetrics += $Metrics
                    Update-CircuitBreaker -ServerName $Server -Success ($Metrics.Status -ne 'Error')
                }
            }

            # Process metrics and check alerts
            $TotalAlerts = 0
            foreach ($Metrics in $AllMetrics) {
                # Save metrics
                if ($EnableMetricsStorage) {
                    Save-Metrics -Metrics $Metrics
                }

                # Check for alerts
                if ($EnableAlerts) {
                    $Alerts = Check-Alerts -Metrics $Metrics -ServerConfig $ServerConfigs[$Metrics.ServerName] -AlertState $AlertState

                    foreach ($Alert in $Alerts) {
                        # Send notifications
                        $Results = Send-AllNotifications -Alert $Alert -Metrics $Metrics
                        $TotalAlerts++

                        # Save alert
                        Save-Alert -Alert $Alert -NotificationResults $Results
                    }
                }
            }

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalMinutes -ge $SummaryReportInterval) {
                Send-SummaryReport -AllMetrics $AllMetrics -TotalAlerts $TotalAlerts
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-MonitorLog "Monitoring Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-MonitorLog "Servers monitored: $($AllMetrics.Count), Alerts triggered: $TotalAlerts" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MonitoringInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-MonitorLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-MonitorLog "Monitoring cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-MonitorLog "Error in monitoring loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- SUMMARY REPORT FUNCTION ----------
function Send-SummaryReport {
    param(
        [array]$AllMetrics,
        [int]$TotalAlerts
    )

    if (-not $EmailConfig.Enabled) {
        return
    }

    try {
        $OnlineServers = ($AllMetrics | Where-Object { $_.Status -eq "Online" }).Count
        $OfflineServers = ($AllMetrics | Where-Object { $_.Status -eq "Offline" }).Count
        $ErrorServers = ($AllMetrics | Where-Object { $_.Status -eq "Error" }).Count

        $HtmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .online { color: #27ae60; font-weight: bold; }
        .offline { color: #e74c3c; font-weight: bold; }
        .error { color: #f39c12; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .status-ok { color: #27ae60; }
        .status-warning { color: #f39c12; }
        .status-critical { color: #e74c3c; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Infrastructure Health Summary Report</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Servers:</strong> $($AllMetrics.Count)</p>
        <p><strong>Online:</strong> <span class="online">$OnlineServers</span></p>
        <p><strong>Offline:</strong> <span class="offline">$OfflineServers</span></p>
        <p><strong>With Errors:</strong> <span class="error">$ErrorServers</span></p>
        <p><strong>Alerts Triggered:</strong> $TotalAlerts</p>
    </div>
    <h2>Server Status</h2>
    <table>
        <tr>
            <th>Server</th>
            <th>Status</th>
            <th>CPU</th>
            <th>Memory</th>
            <th>Network</th>
            <th>Uptime</th>
        </tr>
"@

        foreach ($Metrics in $AllMetrics) {
            $StatusClass = switch ($Metrics.Status) {
                'Online' { 'status-ok' }
                'Offline' { 'status-critical' }
                default { 'status-warning' }
            }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Metrics.ServerName)</strong></td>
            <td class="$StatusClass">$($Metrics.Status)</td>
            <td>$($Metrics.CPU.Value)% ($($Metrics.CPU.Status))</td>
            <td>$($Metrics.Memory.Value)% ($($Metrics.Memory.Status))</td>
            <td>$($Metrics.Network.Speed) ($($Metrics.Network.Status))</td>
            <td>$($Metrics.Uptime)</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary report from the Infrastructure Health Monitoring System.</p>
        <p>Check the monitoring dashboard for detailed information.</p>
    </div>
</body>
</html>
"@

        # Send summary email
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $MailParams = @{
            To = $EmailConfig.To
            From = $EmailConfig.From
            Subject = "Infrastructure Health Summary - $(Get-Date -Format 'yyyy-MM-dd')"
            Body = $HtmlBody
            BodyAsHtml = $true
            SmtpServer = $EmailConfig.SMTPServer
            Port = $EmailConfig.Port
            UseSsl = $EmailConfig.UseSSL
            ErrorAction = 'Stop'
        }

        if ($Credential) {
            $MailParams.Credential = $Credential
        }

        Send-MailMessage @MailParams
        Write-MonitorLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-MonitorLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-Monitoring
}
catch {
    Write-MonitorLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}