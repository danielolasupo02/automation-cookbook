# ============================================================
# ROLLBACK & FAILOVER - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Monitors deployments and automatically triggers rollbacks
#   or failover procedures when failures are detected.
#
# USAGE:
#   As a service: Install using NSSM
#   Manual: .\rollback-failover.ps1
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
$global:DeploymentPolicies = @()
$LastSummaryReport = $null
$TotalDeployments = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-RollbackFailover {
    Write-RollbackLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-RollbackLog "Starting Rollback & Failover Service" -Level "INFO" -Component "SERVICE"
    Write-RollbackLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-RollbackLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-RollbackLog "Auto Rollback: $EnableAutoRollback" -Level "INFO" -Component "SERVICE"
    Write-RollbackLog "Auto Failover: $EnableAutoFailover" -Level "INFO" -Component "SERVICE"

    # Load deployment policies
    $global:DeploymentPolicies = Load-DeploymentPolicies -FilePath $PoliciesCSVPath
    if ($global:DeploymentPolicies.Count -eq 0) {
        Write-RollbackLog "No deployment policies found in $PoliciesCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-RollbackLog "Loaded $($global:DeploymentPolicies.Count) deployment policies" -Level "INFO" -Component "SERVICE"

    # Create required directories
    @($LogPath, $DeploymentStatusPath, $PerformanceDataPath, $StatePath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-RollbackLog "Created directory: $_" -Level "INFO" -Component "SERVICE"
        }
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-RollbackLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-RollbackLog "Monitoring Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $CycleDeployments = 0

            # Process each policy
            if ($EnableParallelProcessing) {
                # Parallel processing
                $Jobs = @()
                foreach ($Policy in $global:DeploymentPolicies) {
                    $Job = Start-Job -ScriptBlock {
                        param($PolicyConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1
                        return Monitor-Deployment -Policy $PolicyConfig
                    } -ArgumentList $Policy

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelThreads) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $Result = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($Result) {
                                    $CycleDeployments++
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
                            $CycleDeployments++
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
                # Sequential processing
                foreach ($Policy in $global:DeploymentPolicies) {
                    $Result = Monitor-Deployment -Policy $Policy
                    if ($Result) {
                        $CycleDeployments++
                    }
                }
            }

            $TotalDeployments += $CycleDeployments

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalHours -ge 24) {
                Send-SummaryReport -CycleDeployments $CycleDeployments
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-RollbackLog "Monitoring Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-RollbackLog "Deployments checked: $($global:DeploymentPolicies.Count), Total monitored: $TotalDeployments" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-RollbackLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-RollbackLog "Monitoring cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-RollbackLog "Error in monitoring loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- SUMMARY REPORT FUNCTION ----------
function Send-SummaryReport {
    param([int]$CycleDeployments)

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
        .success { color: #27ae60; font-weight: bold; }
        .warning { color: #f39c12; font-weight: bold; }
        .error { color: #e74c3c; font-weight: bold; }
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
        <h1>📊 Rollback & Failover Summary</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Policies:</strong> $($global:DeploymentPolicies.Count)</p>
        <p><strong>Deployments Monitored:</strong> $CycleDeployments</p>
        <p><strong>Total Monitored (All Time):</strong> $TotalDeployments</p>
        <p><strong>Auto Rollback:</strong> $(if ($EnableAutoRollback) { "Enabled" } else { "Disabled" })</p>
        <p><strong>Auto Failover:</strong> $(if ($EnableAutoFailover) { "Enabled" } else { "Disabled" })</p>
    </div>
    <h2>Policy Status</h2>
    <table>
        <tr>
            <th>Policy Name</th>
            <th>Type</th>
            <th>Status</th>
            <th>Health</th>
            <th>Rollback Script</th>
            <th>Failover Script</th>
        </tr>
"@

        foreach ($Policy in $global:DeploymentPolicies) {
            $Status = Get-DeploymentStatus -PolicyName $Policy.PolicyName -DeploymentPath $Policy.DeploymentPath

            $StatusClass = if ($Status -and $Status.Status -eq "Healthy") { "success" }
                          elseif ($Status -and $Status.Status -eq "RolledBack") { "warning" }
                          elseif ($Status -and $Status.Status -eq "FailedOver") { "info" }
                          else { "error" }

            $HealthStatus = if ($Status -and $Status.Status) { $Status.Status } else { "Unknown" }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Policy.PolicyName)</strong></td>
            <td>$($Policy.DeploymentType)</td>
            <td class="$StatusClass">$HealthStatus</td>
            <td>$(if ($Status -and $Status.LastResult -and $Status.LastResult.HealthCheckPassed) { "✅" } else { "❌" })</td>
            <td>$(Split-Path $Policy.RollbackScript -Leaf)</td>
            <td>$(Split-Path $Policy.FailoverScript -Leaf)</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the Rollback & Failover System.</p>
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
            Subject = "Rollback & Failover Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-RollbackLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-RollbackLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-RollbackFailover
}
catch {
    Write-RollbackLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}