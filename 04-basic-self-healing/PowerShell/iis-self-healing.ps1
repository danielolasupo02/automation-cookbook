# ============================================================
# IIS SELF-HEALING - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Automatically monitors IIS applications and restarts
#   them when they fail or become unhealthy.
#
# USAGE:
#   As a service: Install using NSSM
#   Manual: .\iis-selfhealing.ps1
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
$global:AppDefinitions = @()
$LastSummaryReport = $null
$TotalRestarts = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-Monitoring {
    Write-IISLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-IISLog "Starting IIS Self-Healing Service" -Level "INFO" -Component "SERVICE"
    Write-IISLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-IISLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-IISLog "Post Restart Wait Time: $PostRestartWaitTime seconds" -Level "INFO" -Component "SERVICE"
    Write-IISLog "Health Check Retries: $HealthCheckRetries" -Level "INFO" -Component "SERVICE"

    # Initialize IIS modules
    if (-not (Initialize-IISModules)) {
        Write-IISLog "Failed to initialize IIS modules. Exiting." -Level "ERROR" -Component "SERVICE"
        return
    }

    # Load application definitions
    $global:AppDefinitions = Load-ApplicationDefinitions -FilePath $ApplicationsCSVPath
    if ($global:AppDefinitions.Count -eq 0) {
        Write-IISLog "No application definitions found in $ApplicationsCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-IISLog "Loaded $($global:AppDefinitions.Count) application definitions" -Level "INFO" -Component "SERVICE"

    # Initialize state for each application
    foreach ($App in $global:AppDefinitions) {
        $AppKey = "$($App.SiteName)$($App.ApplicationPath)"
        $Status = Get-IISApplicationStatus -SiteName $App.SiteName -ApplicationPath $App.ApplicationPath
        Update-AppState -AppKey $AppKey -Status $Status
        Write-IISLog "Initialized monitoring for $($App.SiteName)$($App.ApplicationPath) (AppPool: $($Status.AppPoolName), Status: $($Status.AppPoolStatus))" -Level "INFO" -Component "SERVICE"
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-IISLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-IISLog "Monitoring Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $CycleRestarts = 0

            # Check each application
            if ($EnableParallelChecking) {
                # Parallel checking
                $Jobs = @()
                foreach ($App in $global:AppDefinitions) {
                    $Job = Start-Job -ScriptBlock {
                        param($AppConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1

                        $AppKey = "$($AppConfig.SiteName)$($AppConfig.ApplicationPath)"
                        $Status = Get-IISApplicationStatus -SiteName $AppConfig.SiteName -ApplicationPath $AppConfig.ApplicationPath

                        # Check health
                        $IsHealthy = $true
                        if ($AppConfig.HealthCheckURL -and $AppConfig.HealthCheckURL -ne "") {
                            $IsHealthy = Test-IISApplicationHealth -SiteName $AppConfig.SiteName -ApplicationPath $AppConfig.ApplicationPath -HealthCheckURL $AppConfig.HealthCheckURL -ExpectedResponse $AppConfig.ExpectedResponse
                        }

                        return @{
                            AppKey = $AppKey
                            AppConfig = $AppConfig
                            Status = $Status
                            IsHealthy = $IsHealthy
                        }
                    } -ArgumentList $App

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelChecks) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($Result) {
                                    $Restarted = Process-ApplicationCheck -AppKey $Result.AppKey -AppConfig $Result.AppConfig -Status $Result.Status -IsHealthy $Result.IsHealthy
                                    $CycleRestarts += if ($Restarted) { 1 } else { 0 }
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
                            $Restarted = Process-ApplicationCheck -AppKey $Result.AppKey -AppConfig $Result.AppConfig -Status $Result.Status -IsHealthy $Result.IsHealthy
                            $CycleRestarts += if ($Restarted) { 1 } else { 0 }
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
                foreach ($App in $global:AppDefinitions) {
                    $AppKey = "$($App.SiteName)$($App.ApplicationPath)"
                    $Status = Get-IISApplicationStatus -SiteName $App.SiteName -ApplicationPath $App.ApplicationPath

                    # Check health
                    $IsHealthy = $true
                    if ($App.HealthCheckURL -and $App.HealthCheckURL -ne "") {
                        $IsHealthy = Test-IISApplicationHealth -SiteName $App.SiteName -ApplicationPath $App.ApplicationPath -HealthCheckURL $App.HealthCheckURL -ExpectedResponse $App.ExpectedResponse
                    }

                    $Restarted = Process-ApplicationCheck -AppKey $AppKey -AppConfig $App -Status $Status -IsHealthy $IsHealthy
                    $CycleRestarts += if ($Restarted) { 1 } else { 0 }
                }
            }

            $TotalRestarts += $CycleRestarts

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalMinutes -ge 60) {
                Send-SummaryReport
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-IISLog "Monitoring Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-IISLog "Applications checked: $($global:AppDefinitions.Count), Restarts performed: $CycleRestarts" -Level "INFO" -Component "SERVICE"
            Write-IISLog "Total restarts to date: $TotalRestarts" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-IISLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-IISLog "Monitoring cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-IISLog "Error in monitoring loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- APPLICATION CHECK PROCESSING ----------
function Process-ApplicationCheck {
    param(
        [string]$AppKey,
        [hashtable]$AppConfig,
        [hashtable]$Status,
        [bool]$IsHealthy
    )

    $Restarted = $false

    try {
        # Update state
        Update-AppState -AppKey $AppKey -Status $Status

        # Determine if restart is needed
        $NeedsRestart = $false
        $Reason = ""

        # Check if application pool is not running
        if ($Status.AppPoolStatus -ne "Started") {
            $NeedsRestart = $true
            $Reason = "Application pool status is: $($Status.AppPoolStatus)"
        }
        # Check if site is not running
        elseif ($Status.SiteStatus -ne "Running") {
            $NeedsRestart = $true
            $Reason = "Site status is: $($Status.SiteStatus)"
        }
        # Check health
        elseif (-not $IsHealthy) {
            $NeedsRestart = $true
            $Reason = "Health check failed"
        }

        # Check restart limits
        if ($NeedsRestart) {
            $RestartCountToday = Get-RestartCountToday -AppKey $AppKey
            $MaxRestarts = [int]$AppConfig.MaxRestarts

            if ($RestartCountToday -ge $MaxRestarts) {
                Write-IISLog "WARNING: $AppKey has reached max restarts ($MaxRestarts) for today" -Level "WARNING" -Component "SERVICE"
                $NeedsRestart = $false
                $Reason = "Max restarts exceeded"

                # Send notification
                if ($EnableEmailNotifications) {
                    $Result = @{ Success = $false; Action = "Blocked" }
                    Send-EmailNotification -AppConfig $AppConfig -Status $Status -Result $Result -Severity "ERROR" -Reason $Reason
                }
            }
            else {
                # Perform restart
                Write-IISLog "Restarting $AppKey: $Reason" -Level "WARNING" -Component "SERVICE"

                # Perform restart
                $Result = Restart-IISApplication -SiteName $AppConfig.SiteName -ApplicationPath $AppConfig.ApplicationPath -RestartMethod $AppConfig.RestartMethod -CurrentStatus $Status

                if ($Result.Success) {
                    Update-RestartCount -AppKey $AppKey
                    $Restarted = $true
                    $Severity = "SUCCESS"
                }
                else {
                    Update-FailureCount -AppKey $AppKey -Increment $true
                    $Severity = "ERROR"
                }

                # Send notification
                if ($EnableEmailNotifications) {
                    Send-EmailNotification -AppConfig $AppConfig -Status $Status -Result $Result -Severity $Severity -Reason $Reason
                }

                # Save restart history
                if ($EnablePerformanceTracking) {
                    Save-RestartHistory -AppKey $AppKey -Result $Result
                }
            }
        }
        else {
            # Reset failure count if healthy
            Update-FailureCount -AppKey $AppKey -Increment $false
        }
    }
    catch {
        Write-IISLog "Error processing application check for $AppKey: $_" -Level "ERROR" -Component "SERVICE"
    }

    return $Restarted
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
        .healthy { color: #27ae60; font-weight: bold; }
        .unhealthy { color: #e74c3c; font-weight: bold; }
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
        <h1>📊 IIS Self-Healing Summary Report</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Applications Monitored:</strong> $($global:AppDefinitions.Count)</p>
        <p><strong>Total Restarts (24h):</strong> $TotalRestarts</p>
    </div>
    <h2>Application Status</h2>
    <table>
        <tr>
            <th>Site</th>
            <th>Application</th>
            <th>App Pool</th>
            <th>Status</th>
            <th>Restarts (24h)</th>
            <th>Health</th>
        </tr>
"@

        foreach ($App in $global:AppDefinitions) {
            $AppKey = "$($App.SiteName)$($App.ApplicationPath)"
            $Status = Get-IISApplicationStatus -SiteName $App.SiteName -ApplicationPath $App.ApplicationPath
            $Restarts = Get-RestartCountToday -AppKey $AppKey
            $Health = if ($App.HealthCheckURL) {
                Test-IISApplicationHealth -SiteName $App.SiteName -ApplicationPath $App.ApplicationPath -HealthCheckURL $App.HealthCheckURL -ExpectedResponse $App.ExpectedResponse
            } else { $true }

            $HealthClass = if ($Health) { 'healthy' } else { 'unhealthy' }
            $HealthText = if ($Health) { '✅ Healthy' } else { '❌ Unhealthy' }

            $HtmlBody += @"
        <tr>
            <td><strong>$($App.SiteName)</strong></td>
            <td>$($App.ApplicationPath)</td>
            <td>$($Status.AppPoolName)</td>
            <td>$($Status.AppPoolStatus)</td>
            <td>$Restarts</td>
            <td class="$HealthClass">$HealthText</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the IIS Self-Healing System.</p>
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
            Subject = "IIS Self-Healing Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-IISLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-IISLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-Monitoring
}
catch {
    Write-IISLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}