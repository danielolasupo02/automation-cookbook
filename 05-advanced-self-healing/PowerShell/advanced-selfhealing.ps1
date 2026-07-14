# ============================================================
# ADVANCED SELF-HEALING - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Monitors database tables for specific conditions and
#   triggers automated actions when thresholds are met.
#
# USAGE:
#   As a service: Install using NSSM
#   Manual: .\advanced-selfhealing.ps1
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
$global:MonitorDefinitions = @()
$LastSummaryReport = $null
$TotalActions = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-Monitoring {
    Write-SelfHealingLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-SelfHealingLog "Starting Advanced Self-Healing Service" -Level "INFO" -Component "SERVICE"
    Write-SelfHealingLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-SelfHealingLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-SelfHealingLog "Database Types Supported: Oracle, SQLServer, MySQL, PostgreSQL, SQLite" -Level "INFO" -Component "SERVICE"

    # Load monitor definitions
    $global:MonitorDefinitions = Load-MonitorDefinitions -FilePath $MonitorsCSVPath
    if ($global:MonitorDefinitions.Count -eq 0) {
        Write-SelfHealingLog "No monitor definitions found in $MonitorsCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-SelfHealingLog "Loaded $($global:MonitorDefinitions.Count) monitor definitions" -Level "INFO" -Component "SERVICE"

    # Test database connections
    $UniqueConnections = $global:MonitorDefinitions | Select-Object DatabaseType, ConnectionString -Unique
    $FailedConnections = 0

    foreach ($Connection in $UniqueConnections) {
        $TestResult = Test-DatabaseConnection -DatabaseType $Connection.DatabaseType -ConnectionString $Connection.ConnectionString
        if (-not $TestResult) {
            $FailedConnections++
            Write-SelfHealingLog "Failed to connect to $($Connection.DatabaseType) database" -Level "ERROR" -Component "SERVICE"
        }
    }

    if ($FailedConnections -eq $UniqueConnections.Count) {
        Write-SelfHealingLog "WARNING: All database connections failed. Check credentials and connectivity." -Level "WARNING" -Component "SERVICE"
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-SelfHealingLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-SelfHealingLog "Monitoring Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $CycleActions = 0

            # Check each monitor
            if ($EnableParallelMonitoring) {
                # Parallel monitoring
                $Jobs = @()
                foreach ($Monitor in $global:MonitorDefinitions) {
                    $Job = Start-Job -ScriptBlock {
                        param($MonitorConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1

                        return Process-MonitorCheck -Monitor $MonitorConfig
                    } -ArgumentList $Monitor

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelMonitors) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($Result) {
                                    $CycleActions += if ($Result.ActionTaken) { 1 } else { 0 }
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
                            $CycleActions += if ($Result.ActionTaken) { 1 } else { 0 }
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
                # Sequential monitoring
                foreach ($Monitor in $global:MonitorDefinitions) {
                    $Result = Process-MonitorCheck -Monitor $Monitor
                    if ($Result.ActionTaken) {
                        $CycleActions++
                    }
                }
            }

            $TotalActions += $CycleActions

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalMinutes -ge 60) {
                Send-SummaryReport
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-SelfHealingLog "Monitoring Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-SelfHealingLog "Monitors checked: $($global:MonitorDefinitions.Count), Actions performed: $CycleActions" -Level "INFO" -Component "SERVICE"
            Write-SelfHealingLog "Total actions to date: $TotalActions" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-SelfHealingLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-SelfHealingLog "Monitoring cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-SelfHealingLog "Error in monitoring loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- MONITOR CHECK PROCESSING ----------
function Process-MonitorCheck {
    param([hashtable]$Monitor)

    $Result = @{
        MonitorName = $Monitor.MonitorName
        ActionTaken = $false
        CurrentCount = 0
        ConditionMet = $false
        ActionResult = $null
    }

    try {
        $MonitorName = $Monitor.MonitorName

        # Check circuit breaker
        if (-not (Check-CircuitBreaker -MonitorName $MonitorName)) {
            Write-SelfHealingLog "Skipping $MonitorName due to circuit breaker" -Level "WARNING" -Component "MONITOR"
            return $Result
        }

        # Build query
        $Query = "SELECT COUNT(*) FROM $($Monitor.TableName) WHERE $($Monitor.QueryCondition)"
        Write-SelfHealingLog "Executing query for $MonitorName: $Query" -Level "DEBUG" -Component "MONITOR"

        # Execute query
        $QueryResult = Invoke-DatabaseQuery -DatabaseType $Monitor.DatabaseType -ConnectionString $Monitor.ConnectionString -Query $Query -Timeout $DBQueryTimeout

        if (-not $QueryResult.Success) {
            Update-CircuitBreaker -MonitorName $MonitorName -Success $false
            Write-SelfHealingLog "Query failed for $MonitorName: $($QueryResult.Error)" -Level "ERROR" -Component "MONITOR"
            return $Result
        }

        $CurrentCount = $QueryResult.Count
        $Result.CurrentCount = $CurrentCount
        $Threshold = [int]$Monitor.ThresholdCount

        Write-SelfHealingLog "$MonitorName: Current count = $CurrentCount, Threshold = $Threshold" -Level "INFO" -Component "MONITOR"

        # Evaluate condition
        $ConditionMet = Evaluate-Condition -CurrentCount $CurrentCount -Threshold $Threshold -Operator $Monitor.ConditionOperator
        $Result.ConditionMet = $ConditionMet

        if ($ConditionMet) {
            Write-SelfHealingLog "Condition met for $MonitorName!" -Level "WARNING" -Component "MONITOR"

            # Generate alert key
            $AlertKey = "$($Monitor.MonitorName)-$($Monitor.ConditionOperator)-$($Monitor.ThresholdCount)"

            # Check alert cooldown
            if ($EnableAlertCooldown) {
                if ($AlertState.ContainsKey($AlertKey)) {
                    $LastAlertTime = $AlertState[$AlertKey]
                    $TimeSinceLastAlert = ((Get-Date) - $LastAlertTime).TotalSeconds
                    if ($TimeSinceLastAlert -lt $AlertCooldownSeconds) {
                        Write-SelfHealingLog "Alert cooldown active for $MonitorName ($([Math]::Round($TimeSinceLastAlert))s < $AlertCooldownSeconds s)" -Level "WARNING" -Component "MONITOR"
                        return $Result
                    }
                }
            }

            # Execute action
            Write-SelfHealingLog "Executing action for $MonitorName..." -Level "INFO" -Component "MONITOR"
            $ActionResult = Execute-Action -Monitor $Monitor -CurrentCount $CurrentCount -AlertKey $AlertKey
            $Result.ActionResult = $ActionResult
            $Result.ActionTaken = $ActionResult.Success

            # Update alert state
            if ($EnableAlertCooldown) {
                $AlertState[$AlertKey] = Get-Date
            }

            # Update circuit breaker
            Update-CircuitBreaker -MonitorName $MonitorName -Success $ActionResult.Success

            # Update state
            Update-MonitorState -MonitorName $MonitorName -CurrentCount $CurrentCount -IsAlerting $true

            Write-SelfHealingLog "Action completed for $MonitorName: $($ActionResult.Success)" -Level "INFO" -Component "MONITOR"
        }
        else {
            # Reset state if condition not met
            Update-MonitorState -MonitorName $MonitorName -CurrentCount $CurrentCount -IsAlerting $false
            Update-CircuitBreaker -MonitorName $MonitorName -Success $true
        }
    }
    catch {
        Write-SelfHealingLog "Error processing monitor check for $($Monitor.MonitorName): $_" -Level "ERROR" -Component "MONITOR"
        Update-CircuitBreaker -MonitorName $Monitor.MonitorName -Success $false
    }

    return $Result
}

# ---------- SUMMARY REPORT FUNCTION ----------
function Send-SummaryReport {
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
        .critical { color: #e74c3c; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        .info { color: #3498db; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Advanced Self-Healing Summary Report</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Monitors:</strong> $($global:MonitorDefinitions.Count)</p>
        <p><strong>Total Actions (24h):</strong> $TotalActions</p>
    </div>
    <h2>Monitor Status</h2>
    <table>
        <tr>
            <th>Monitor</th>
            <th>Database</th>
            <th>Table</th>
            <th>Last Count</th>
            <th>Threshold</th>
            <th>Status</th>
            <th>Actions</th>
        </tr>
"@

        foreach ($Monitor in $global:MonitorDefinitions) {
            $MonitorName = $Monitor.MonitorName
            $State = $MonitorState[$MonitorName]
            $LastCount = if ($State) { $State.CurrentCount } else { 0 }
            $IsAlerting = if ($State) { $State.IsAlerting } else { $false }
            $ActionCount = if ($ActionHistory.ContainsKey($MonitorName)) { $ActionHistory[$MonitorName].Count } else { 0 }

            $StatusClass = if ($IsAlerting) { 'critical' } else { 'info' }
            $StatusText = if ($IsAlerting) { '⚠️ Alerting' } else { '✅ Healthy' }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Monitor.MonitorName)</strong></td>
            <td>$($Monitor.DatabaseType)</td>
            <td>$($Monitor.TableName)</td>
            <td>$LastCount</td>
            <td>$($Monitor.ThresholdCount)</td>
            <td class="$StatusClass">$StatusText</td>
            <td>$ActionCount</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the Advanced Self-Healing System.</p>
        <p>Logs are available at: $LogPath</p>
    </div>
</body>
</html>
"@

        # Send summary email
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $MailParams = @{
            To = $EmailConfig.DefaultTo
            From = $EmailConfig.From
            Subject = "Advanced Self-Healing Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-SelfHealingLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-SelfHealingLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-Monitoring
}
catch {
    Write-SelfHealingLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}