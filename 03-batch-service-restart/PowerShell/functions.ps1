# ============================================================
# BATCH SERVICE RESTART - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Continuously monitors batch services/processes and
#   automatically restarts them when they timeout or fail.
#
# USAGE:
#   As a service: Install using NSSM or .NET Service
#   Manual: .\service-restart.ps1
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
$ServiceState = @{}
$LastSummaryReport = $null
$TotalRestarts = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-Monitoring {
    Write-ServiceLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "Starting Batch Service Restart Manager" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "Process Detection Method: $ProcessDetectionMethod" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "Kill Process Tree: $KillProcessTree" -Level "INFO" -Component "SERVICE"
    Write-ServiceLog "Parallel Checking: $EnableParallelChecking" -Level "INFO" -Component "SERVICE"

    # Load service definitions
    $ServiceDefinitions = Load-ServiceDefinitions -FilePath $ServicesCSVPath
    if ($ServiceDefinitions.Count -eq 0) {
        Write-ServiceLog "No service definitions found in $ServicesCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-ServiceLog "Loaded $($ServiceDefinitions.Count) service definitions" -Level "INFO" -Component "SERVICE"

    # Initialize state for each service
    foreach ($Service in $ServiceDefinitions) {
        $Status = Get-ServiceStatus -ServiceName $Service.Name -ServiceConfig $Service
        Update-ServiceState -ServiceName $Service.Name -Status $Status
        Write-ServiceLog "Initialized monitoring for $($Service.Name) (Status: $($Status.Status))" -Level "INFO" -Component "SERVICE"
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-ServiceLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-ServiceLog "Monitoring Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $CycleRestarts = 0

            # Check each service
            if ($EnableParallelChecking) {
                # Parallel checking
                $Jobs = @()
                foreach ($Service in $ServiceDefinitions) {
                    $Job = Start-Job -ScriptBlock {
                        param($ServiceName, $ServiceConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1

                        # Get current status
                        $Status = Get-ServiceStatus -ServiceName $ServiceName -ServiceConfig $ServiceConfig
                        return @{
                            ServiceName = $ServiceName
                            ServiceConfig = $ServiceConfig
                            Status = $Status
                        }
                    } -ArgumentList $Service.Name, $Service

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelChecks) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($Result) {
                                    Process-ServiceCheck -ServiceName $Result.ServiceName -ServiceConfig $Result.ServiceConfig -Status $Result.Status
                                    $CycleRestarts += if ($Result.Restarted) { 1 } else { 0 }
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
                            Process-ServiceCheck -ServiceName $Result.ServiceName -ServiceConfig $Result.ServiceConfig -Status $Result.Status
                            $CycleRestarts += if ($Result.Restarted) { 1 } else { 0 }
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
                # Sequential checking
                foreach ($Service in $ServiceDefinitions) {
                    $Status = Get-ServiceStatus -ServiceName $Service.Name -ServiceConfig $Service
                    Process-ServiceCheck -ServiceName $Service.Name -ServiceConfig $Service -Status $Status
                    $CycleRestarts += if ($Status.Restarted) { 1 } else { 0 }
                }
            }

            $TotalRestarts += $CycleRestarts

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalMinutes -ge $SummaryReportInterval) {
                Send-SummaryReport -ServiceDefinitions $ServiceDefinitions
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-ServiceLog "Monitoring Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-ServiceLog "Services checked: $($ServiceDefinitions.Count), Restarts performed: $CycleRestarts" -Level "INFO" -Component "SERVICE"
            Write-ServiceLog "Total restarts to date: $TotalRestarts" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-ServiceLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-ServiceLog "Monitoring cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-ServiceLog "Error in monitoring loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- SERVICE CHECK PROCESSING ----------
function Process-ServiceCheck {
    param(
        [string]$ServiceName,
        [hashtable]$ServiceConfig,
        [hashtable]$Status
    )

    $Restarted = $false

    try {
        # Update state
        Update-ServiceState -ServiceName $ServiceName -Status $Status

        # Check if service needs restart
        $NeedsRestart = $false
        $Reason = ""

        # Check if service is running
        if (-not $Status.IsRunning) {
            $NeedsRestart = $true
            $Reason = "Service is not running (Status: $($Status.Status))"
        }
        # Check timeout
        elseif (Check-ServiceTimeout -ServiceName $ServiceName -ServiceStatus $Status -ServiceConfig $ServiceConfig) {
            $NeedsRestart = $true
            $Reason = "Service exceeded timeout threshold ($($ServiceConfig.TimeoutThreshold) seconds)"
        }
        # Check health (if defined)
        elseif ($ServiceConfig.HealthCheck -and $ServiceConfig.HealthCheck -ne "") {
            if (-not (Test-ServiceHealth -ServiceName $ServiceName -ServiceConfig $ServiceConfig)) {
                $NeedsRestart = $true
                $Reason = "Health check failed"
            }
        }

        # Check restart limits
        if ($NeedsRestart) {
            $RestartCountToday = Get-RestartCountToday -ServiceName $ServiceName
            $MaxRestarts = [int]$ServiceConfig.MaxRestarts

            if ($RestartCountToday -ge $MaxRestarts) {
                Write-ServiceLog "WARNING: $ServiceName has reached max restarts ($MaxRestarts) for today" -Level "WARNING" -Component "SERVICE"
                $NeedsRestart = $false
                $Reason = "Max restarts exceeded"

                # Send notification for max restarts
                $Result = @{ Success = $false; Action = "Blocked" }
                Send-AllNotifications -ServiceConfig $ServiceConfig -Status $Status -Result $Result -Severity "ERROR" -Reason $Reason -Action "Blocked"

                # Check failure threshold for recovery
                Update-FailureCount -ServiceName $ServiceName -Increment $true
                if ($ServiceState[$ServiceName].ConsecutiveFailures -ge $FailureThreshold -and $EnableAutoRecovery) {
                    Handle-RecoveryAction -ServiceName $ServiceName -ServiceConfig $ServiceConfig
                }
            }
            else {
                # Perform restart
                Write-ServiceLog "Restarting $ServiceName: $Reason" -Level "WARNING" -Component "SERVICE"

                # Check restart cooldown
                $LastRestart = $ServiceState[$ServiceName].LastRestart
                if ($LastRestart) {
                    $TimeSinceLastRestart = ((Get-Date) - $LastRestart).TotalSeconds
                    if ($TimeSinceLastRestart -lt $GlobalRestartCooldown) {
                        Write-ServiceLog "Skipping restart for $ServiceName (cooldown: $([Math]::Round($TimeSinceLastRestart))s < $GlobalRestartCooldown s)" -Level "WARNING" -Component "SERVICE"
                        return
                    }
                }

                # Perform restart
                $Result = Restart-ServiceProcess -ServiceName $ServiceName -ServiceConfig $ServiceConfig -CurrentStatus $Status

                if ($Result.Success) {
                    Update-RestartCount -ServiceName $ServiceName
                    $Restarted = $true
                    $Severity = "SUCCESS"
                }
                else {
                    Update-FailureCount -ServiceName $ServiceName -Increment $true
                    $Severity = "ERROR"
                }

                # Send notification
                Send-AllNotifications -ServiceConfig $ServiceConfig -Status $Status -Result $Result -Severity $Severity -Reason $Reason -Action $Result.Action

                # Check failure threshold
                if (-not $Result.Success -and $EnableAutoRecovery) {
                    if ($ServiceState[$ServiceName].ConsecutiveFailures -ge $FailureThreshold) {
                        Handle-RecoveryAction -ServiceName $ServiceName -ServiceConfig $ServiceConfig
                    }
                }
            }
        }
        else {
            # Reset failure count if service is healthy
            Update-FailureCount -ServiceName $ServiceName -Increment $false
        }
    }
    catch {
        Write-ServiceLog "Error processing service check for $ServiceName: $_" -Level "ERROR" -Component "SERVICE"
    }
}

# ---------- SUMMARY REPORT FUNCTION ----------
function Send-SummaryReport {
    param([array]$ServiceDefinitions)

    if (-not $EmailConfig.Enabled) {
        return
    }

    try {
        $HtmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .running { color: #27ae60; font-weight: bold; }
        .stopped { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Batch Service Restart Summary</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Services Monitored:</strong> $($ServiceDefinitions.Count)</p>
        <p><strong>Total Restarts (24h):</strong> $TotalRestarts</p>
        <p><strong>Most Recent Restart:</strong> $(if ($ServiceDefinitions) { "Yes" } else { "None" })</p>
    </div>
    <h2>Service Status</h2>
    <table>
        <tr>
            <th>Service</th>
            <th>Type</th>
            <th>Status</th>
            <th>Uptime</th>
            <th>Restarts (24h)</th>
            <th>PID</th>
        </tr>
"@

        foreach ($Service in $ServiceDefinitions) {
            $Status = Get-ServiceStatus -ServiceName $Service.Name -ServiceConfig $Service
            $Restarts = Get-RestartCountToday -ServiceName $Service.Name
            $StatusClass = switch ($Status.Status) {
                'Running' { 'running' }
                'Stopped' { 'stopped' }
                default { 'warning' }
            }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Service.Name)</strong></td>
            <td>$($Service.Type)</td>
            <td class="$StatusClass">$($Status.Status)</td>
            <td>$($Status.Uptime)</td>
            <td>$Restarts</td>
            <td>$($Status.PID)</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the Batch Service Restart Manager.</p>
        <p>Logs are available at: $LogPath</p>
    </div>
</body>
</html>
"@

        # Send summary email
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $MailParams = @{
            To = $EmailConfig.To
            From = $EmailConfig.From
            Subject = "Batch Service Restart Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-ServiceLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-ServiceLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-Monitoring
}
catch {
    Write-ServiceLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}