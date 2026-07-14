# ============================================================
# SCHEDULED JOB RUNNER - MAIN SERVICE SCRIPT
# ============================================================
#
# DESCRIPTION:
#   Executes scheduled jobs (PowerShell, Bash, Cmd, Python)
#   on defined schedules (Daily, Weekly, Monthly, etc.)
#
# USAGE:
#   As a service: Install using NSSM
#   Manual: .\job-runner.ps1
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
$global:JobDefinitions = @()
$LastSummaryReport = $null
$TotalJobsRun = 0

# ---------- MAIN MONITORING LOOP ----------
function Start-JobRunner {
    Write-JobLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-JobLog "Starting Scheduled Job Runner Service" -Level "INFO" -Component "SERVICE"
    Write-JobLog "========================================" -Level "INFO" -Component "SERVICE"
    Write-JobLog "Master Check Interval: $MasterCheckInterval seconds" -Level "INFO" -Component "SERVICE"
    Write-JobLog "Max Concurrent Jobs: $MaxConcurrentJobs" -Level "INFO" -Component "SERVICE"
    Write-JobLog "Job Types Supported: PowerShell, Bash, Cmd, Python" -Level "INFO" -Component "SERVICE"

    # Load job definitions
    $global:JobDefinitions = Load-JobDefinitions -FilePath $JobsCSVPath
    if ($global:JobDefinitions.Count -eq 0) {
        Write-JobLog "No job definitions found in $JobsCSVPath" -Level "ERROR" -Component "SERVICE"
        return
    }
    Write-JobLog "Loaded $($global:JobDefinitions.Count) job definitions" -Level "INFO" -Component "SERVICE"

    # Initialize state for each job
    foreach ($Job in $global:JobDefinitions) {
        $NextRun = Get-NextRunTime -Schedule $Job.Schedule -ScheduleDetails $Job.ScheduleDetails
        Update-JobState -JobName $Job.JobName -NextRun $NextRun
        Write-JobLog "Initialized job: $($Job.JobName), Next Run: $NextRun" -Level "INFO" -Component "SERVICE"
    }

    # Main loop
    $LoopCount = 0
    while ($true) {
        try {
            $LoopCount++
            $StartTime = Get-Date

            Write-JobLog "========================================" -Level "INFO" -Component "SERVICE"
            Write-JobLog "Runner Cycle #$LoopCount started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO" -Component "SERVICE"

            $JobsToRun = @()
            $RunningJobs = @()

            # Check each job
            foreach ($Job in $global:JobDefinitions) {
                $JobName = $Job.JobName

                # Check circuit breaker
                if (Is-CircuitBreakerOpen -JobName $JobName) {
                    Write-JobLog "Skipping $JobName due to circuit breaker" -Level "WARNING" -Component "SERVICE"
                    continue
                }

                $State = $JobState[$JobName]
                $NextRun = $State.NextRun
                $Now = Get-Date

                if ($NextRun -and $NextRun -le $Now) {
                    Write-JobLog "Job $JobName is due to run (Scheduled: $NextRun)" -Level "INFO" -Component "SERVICE"
                    $JobsToRun += $Job

                    # Calculate next run time
                    $NewNextRun = Get-NextRunTime -Schedule $Job.Schedule -ScheduleDetails $Job.ScheduleDetails -ReferenceTime $Now
                    Update-JobState -JobName $JobName -NextRun $NewNextRun
                    Write-JobLog "Next run for $JobName scheduled for: $NewNextRun" -Level "DEBUG" -Component "SERVICE"
                }
            }

            # Execute jobs
            if ($JobsToRun.Count -gt 0) {
                Write-JobLog "Found $($JobsToRun.Count) job(s) to run" -Level "INFO" -Component "SERVICE"

                if ($EnableParallelExecution) {
                    # Run jobs in parallel with limit
                    $JobQueue = $JobsToRun
                    $Running = @()

                    while ($JobQueue.Count -gt 0 -or $Running.Count -gt 0) {
                        # Start new jobs
                        while ($JobQueue.Count -gt 0 -and $Running.Count -lt $MaxConcurrentJobs) {
                            $Job = $JobQueue[0]
                            $JobQueue = $JobQueue | Select-Object -Skip 1

                            Write-JobLog "Starting job: $($Job.JobName)" -Level "INFO" -Component "SERVICE"

                            $JobScript = {
                                param($Job, $NextRun)
                                . $using:ScriptDir\functions.ps1
                                . $using:ScriptDir\config.ps1
                                return Execute-Job -Job $Job -ScheduledTime $NextRun
                            }

                            $JobObj = Start-Job -ScriptBlock $JobScript -ArgumentList $Job, $State.NextRun
                            $Running += @{
                                Job = $Job
                                RunJob = $JobObj
                                StartTime = Get-Date
                            }
                        }

                        # Check for completed jobs
                        $Completed = $Running | Where-Object { $_.RunJob.State -eq 'Completed' -or $_.RunJob.State -eq 'Failed' }
                        foreach ($Item in $Completed) {
                            $Result = Receive-Job -Job $Item.RunJob -ErrorAction SilentlyContinue
                            Remove-Job -Job $Item.RunJob -Force

                            if ($Result) {
                                Write-JobLog "Job $($Item.Job.JobName) completed with status: $(if ($Result.Success) { 'SUCCESS' } else { 'FAILED' })" -Level "INFO" -Component "SERVICE"
                                $TotalJobsRun++

                                # Update job state with result
                                $State = $JobState[$Item.Job.JobName]
                                Update-JobState -JobName $Item.Job.JobName -NextRun $State.NextRun -LastResult $Result
                            }

                            $Running = $Running | Where-Object { $_ -ne $Item }
                        }

                        # Wait a bit before checking again
                        if ($Running.Count -gt 0) {
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
                else {
                    # Run jobs sequentially
                    foreach ($Job in $JobsToRun) {
                        Write-JobLog "Starting job: $($Job.JobName)" -Level "INFO" -Component "SERVICE"

                        $State = $JobState[$Job.JobName]
                        $Result = Execute-Job -Job $Job -ScheduledTime $State.NextRun

                        Write-JobLog "Job $($Job.JobName) completed with status: $(if ($Result.Success) { 'SUCCESS' } else { 'FAILED' })" -Level "INFO" -Component "SERVICE"
                        $TotalJobsRun++

                        # Update job state with result
                        Update-JobState -JobName $Job.JobName -NextRun $State.NextRun -LastResult $Result
                    }
                }
            }
            else {
                Write-JobLog "No jobs due to run at this time" -Level "DEBUG" -Component "SERVICE"
            }

            # Send summary report
            $Now = Get-Date
            if ($null -eq $LastSummaryReport -or ($Now - $LastSummaryReport).TotalHours -ge 24) {
                Send-SummaryReport
                $LastSummaryReport = $Now
            }

            # Calculate processing time
            $EndTime = Get-Date
            $Duration = ($EndTime - $StartTime).TotalSeconds
            Write-JobLog "Runner Cycle #$LoopCount completed in $([Math]::Round($Duration, 2)) seconds" -Level "INFO" -Component "SERVICE"
            Write-JobLog "Jobs due: $($JobsToRun.Count), Total run to date: $TotalJobsRun" -Level "INFO" -Component "SERVICE"

            # Wait for next interval
            $SleepTime = $MasterCheckInterval - $Duration
            if ($SleepTime -gt 0) {
                Write-JobLog "Sleeping for $([Math]::Round($SleepTime, 2)) seconds" -Level "DEBUG" -Component "SERVICE"
                Start-Sleep -Seconds $SleepTime
            }
            else {
                Write-JobLog "Runner cycle exceeded interval by $([Math]::Round(-$SleepTime, 2)) seconds" -Level "WARNING" -Component "SERVICE"
            }
        }
        catch {
            Write-JobLog "Error in runner loop: $_" -Level "ERROR" -Component "SERVICE"
            Start-Sleep -Seconds 10
        }
    }
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
        .success { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
        .pending { color: #f39c12; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Scheduled Job Runner Daily Summary</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Jobs:</strong> $($global:JobDefinitions.Count)</p>
        <p><strong>Total Runs Today:</strong> $TotalJobsRun</p>
    </div>
    <h2>Job Status</h2>
    <table>
        <tr>
            <th>Job</th>
            <th>Schedule</th>
            <th>Next Run</th>
            <th>Last Run</th>
            <th>Last Status</th>
            <th>Attempts</th>
        </tr>
"@

        foreach ($Job in $global:JobDefinitions) {
            $State = $JobState[$Job.JobName]
            $LastResult = $State.LastResult

            $StatusClass = if ($LastResult -and $LastResult.Success) { "success" }
                           elseif ($LastResult -and -not $LastResult.Success) { "failed" }
                           else { "pending" }
            $StatusText = if ($LastResult -and $LastResult.Success) { "✅ Success" }
                         elseif ($LastResult -and -not $LastResult.Success) { "❌ Failed" }
                         else { "⏳ Pending" }

            $HtmlBody += @"
        <tr>
            <td><strong>$($Job.JobName)</strong></td>
            <td>$($Job.Schedule) ($($Job.ScheduleDetails))</td>
            <td>$($State.NextRun)</td>
            <td>$(if ($LastResult) { $LastResult.StartTime } else { "Never" })</td>
            <td class="$StatusClass">$StatusText</td>
            <td>$(if ($LastResult) { $LastResult.Attempts } else { 0 })</td>
        </tr>
"@
        }

        $HtmlBody += @"
    </table>
    <div class="footer">
        <p>This is an automated summary from the Scheduled Job Runner.</p>
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
            Subject = "Scheduled Job Runner Summary - $(Get-Date -Format 'yyyy-MM-dd')"
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
        Write-JobLog "Summary report sent" -Level "INFO" -Component "SUMMARY"
    }
    catch {
        Write-JobLog "Failed to send summary report: $_" -Level "ERROR" -Component "SUMMARY"
    }
}

# ---------- START THE SERVICE ----------
try {
    Start-JobRunner
}
catch {
    Write-JobLog "Fatal error: $_" -Level "CRITICAL" -Component "SERVICE"
    throw
}