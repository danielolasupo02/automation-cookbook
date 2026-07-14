# ============================================================
# LOG RETENTION - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Automatically deletes or archives log files based on
#   configurable retention policies.
#
# USAGE:
#   As a service: Install using NSSM
#   Manual: .\log-retention.ps1
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
$global:RetentionPolicies = @()
$LastSummaryReport = $null
$TotalFilesProcessed = 0
$TotalSpaceFreed = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-LogRetention {
    Write-RetentionLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-RetentionLog "Starting Log Retention Service" -Level "INFO" -Component "SERVICE"
    Write-RetentionLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-RetentionLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-RetentionLog "Dry Run Mode: $DryRunMode" -Level "INFO" -Component "SERVICE"
    Write-RetentionLog "Max Files Per Scan: $MaxFilesPerScan" -Level "INFO" -Component "SERVICE"

    # Load retention policies
    $global:RetentionPolicies = Load-RetentionPolicies -FilePath $PoliciesCSVPath
    if ($global:RetentionPolicies.Count -eq 0) {
        Write-RetentionLog "No retention policies found in $PoliciesCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-RetentionLog "Loaded $($global:RetentionPolicies.Count) retention policies" -Level "INFO" -Component "SERVICE"

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-RetentionLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-RetentionLog "Retention Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $CycleFilesProcessed = 0
            $CycleSpaceFreed = 0
            $PolicyResults = @()

            # Process policies
            if ($EnableParallelProcessing) {
                # Parallel processing
                $Jobs = @()
                foreach ($Policy in $global:RetentionPolicies) {
                    $Job = Start-Job -ScriptBlock {
                        param($PolicyConfig)
                        . $using:ScriptDir\functions.ps1
                        . $using:ScriptDir\config.ps1

                        $TotalFilesProcessed = 0
                        $TotalSpaceFreed = 0
                        $Result = Process-RetentionPolicy -Policy $PolicyConfig -TotalFilesProcessed ([ref]$TotalFilesProcessed) -TotalSpaceFreed ([ref]$TotalSpaceFreed)
                        return @{
                            Result = $Result
                            FilesProcessed = $TotalFilesProcessed
                            SpaceFreed = $TotalSpaceFreed
                        }
                    } -ArgumentList $Policy

                    $Jobs += $Job

                    # Limit parallel jobs
                    while ($Jobs.Count -ge $MaxParallelThreads) {
                        $Completed = $Jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                        if ($Completed) {
                            $Completed | ForEach-Object {
                                $JobResult = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                                if ($JobResult) {
                                    $PolicyResults += $JobResult.Result
                                    $CycleFilesProcessed += $JobResult.FilesProcessed
                                    $CycleSpaceFreed += $JobResult.SpaceFreed
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
                        $JobResult = Receive-Job -Job $_ -ErrorAction SilentlyContinue
                        if ($JobResult) {
                            $PolicyResults += $JobResult.Result
                            $CycleFilesProcessed += $JobResult.FilesProcessed
                            $CycleSpaceFreed += $JobResult.SpaceFreed
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
                foreach ($Policy in $global:RetentionPolicies) {
                    $TotalFilesProcessed = 0
                    $TotalSpaceFreed = 0
                    $Result = Process-RetentionPolicy -Policy $Policy -TotalFilesProcessed ([ref]$TotalFilesProcessed) -TotalSpaceFreed ([ref]$TotalSpaceFreed)
                    $PolicyResults += $Result
                    $CycleFilesProcessed += $TotalFilesProcessed
                    $CycleSpaceFreed += $TotalSpaceFreed
                }
            }

            $TotalFilesProcessed += $CycleFilesProcessed
            $TotalSpaceFreed += $CycleSpaceFreed

            # Update policy states
            foreach ($Result in $PolicyResults) {
                Update-PolicyState -PolicyName $Result.PolicyName -Result $Result
                Save-RetentionHistory -Policy @{ PolicyName = $Result.PolicyName } -Result $Result
            }

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalHours -ge 24) {
                Send-SummaryReport -PolicyResults $PolicyResults -CycleFilesProcessed $CycleFilesProcessed -CycleSpaceFreed $CycleSpaceFreed
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-RetentionLog "Retention Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-RetentionLog "Files processed: $CycleFilesProcessed, Space freed: $(Format-FileSize $CycleSpaceFreed)" -Level "INFO" -Component "SERVICE"
            Write-RetentionLog "Total to date: $TotalFilesProcessed files, $(Format-FileSize $TotalSpaceFreed)" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-RetentionLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-RetentionLog "Retention cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-RetentionLog "Error in retention loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
}

# ---------- SUMMARY REPORT FUNCTION ----------
function Send-SummaryReport {
    param(
        [array]$PolicyResults,
        [int]$CycleFilesProcessed,
        [long]$CycleSpaceFreed
    )

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
        .failed { color: #e74c3c; font-weight: bold; }
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
        <h1>📊 Log Retention Daily Summary</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Policies:</strong> $($global:RetentionPolicies.Count)</p>
        <p><strong>Policies Processed:</strong> $($PolicyResults.Count)</p>
        <p><strong>Files Processed:</strong> $CycleFilesProcessed</p>
        <p><strong>Space Freed:</strong> $(Format-FileSize $CycleSpaceFreed)</p>
        <p><strong>Total Files Processed (All Time):</strong> $TotalFilesProcessed</p>
        <p><strong>Total Space Freed (All Time):</strong> $(Format-FileSize $TotalSpaceFreed)</p>
        <p><strong>Dry Run Mode:</strong> $DryRunMode</p>
    </div>
    <h2>Policy Results</h2>
    <table>
        <tr>
            <th>Policy Name</th>
            <th>Path</th>
            <th>Action</th>
            <th>Files Processed</th>
            <th>Space Freed</th>
            <th>Status</th>
        </tr>
"@

        foreach ($Result in $PolicyResults) {
            $StatusClass = if ($Result.Success) { "success" } else { "failed" }
            $StatusText = if ($Result.Success) { "✅ Success" } else { "❌ Failed" }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Result.PolicyName)</strong></td>
            <td>$($Result.Path)</td>
            <td>$($Result.Action)</td>
            <td>$($Result.FilesProcessed)</td>
            <td>$(Format-FileSize $Result.SpaceFreed)</td>
            <td class="$StatusClass">$StatusText</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the Log Retention System.</p>
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
            Subject = "Log Retention Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-RetentionLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-RetentionLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-LogRetention
}
catch {
    Write-RetentionLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}