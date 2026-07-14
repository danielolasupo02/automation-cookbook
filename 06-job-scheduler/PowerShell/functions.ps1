# ============================================================
# SCHEDULED JOB RUNNER - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for job scheduling,
# execution, and notifications.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-JobLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "JOB-RUNNER"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $LogMessage = "[$Timestamp] [$Level] [$Component] $Message"

    # Write to console
    $ColorMap = @{
        'DEBUG' = 'Gray'
        'INFO' = 'White'
        'WARNING' = 'Yellow'
        'ERROR' = 'Red'
        'CRITICAL' = 'Magenta'
        'SUCCESS' = 'Green'
    }
    Write-Host $LogMessage -ForegroundColor $ColorMap[$Level]

    # Write to log file
    if ($EnableLogging) {
        try {
            if (!(Test-Path $LogPath)) {
                New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
            }
            $LogFile = Join-Path $LogPath "JobRunner_$(Get-Date -Format 'yyyyMMdd').log"
            Add-Content -Path $LogFile -Value $LogMessage

            # Log rotation
            if ((Get-Item $LogFile).Length -gt ($LogRotationSizeMB * 1MB)) {
                $ArchiveFile = "$LogFile.$(Get-Date -Format 'HHmmss').archive"
                Move-Item -Path $LogFile -Destination $ArchiveFile -Force
            }
        }
        catch {
            # Silently fail if logging fails
        }
    }
}

# ---------- CREDENTIAL FUNCTIONS ----------
function Get-StoredCredential {
    param([string]$CredentialName)

    try {
        $CredCheck = cmdkey /list | Select-String $CredentialName
        if (!$CredCheck) {
            Write-JobLog "Credential '$CredentialName' not found" -Level "WARNING" -Component "CREDENTIALS"
            return $null
        }

        if (Get-Module -Name CredentialManager -ListAvailable) {
            Import-Module CredentialManager -Force
            return Get-StoredCredential -Target $CredentialName
        }
        else {
            return Get-Credential -Message "Enter credentials for $CredentialName"
        }
    }
    catch {
        Write-JobLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

# ---------- JOB LOADING FUNCTIONS ----------
function Load-JobDefinitions {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-JobLog "Job definitions file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Jobs = Import-Csv -Path $FilePath | Where-Object {
        $_.JobName -and $_.JobName -notmatch '^#'
    }

    Write-JobLog "Loaded $($Jobs.Count) job definitions from $FilePath" -Level "INFO" -Component "CONFIG"

    # Validate jobs
    $EnabledJobs = $Jobs | Where-Object { $_.Enabled -eq 'true' -or $_.Enabled -eq 'TRUE' }
    Write-JobLog "$($EnabledJobs.Count) jobs are enabled" -Level "INFO" -Component "CONFIG"

    return $EnabledJobs
}

function Get-JobConfig {
    param(
        [string]$JobName,
        [array]$JobDefinitions
    )

    return $JobDefinitions | Where-Object { $_.JobName -eq $JobName } | Select-Object -First 1
}

# ---------- SCHEDULING FUNCTIONS ----------
function Get-NextRunTime {
    param(
        [string]$Schedule,
        [string]$ScheduleDetails,
        [datetime]$ReferenceTime = (Get-Date)
    )

    $NextRun = $null

    switch ($Schedule) {
        "Daily" {
            # ScheduleDetails: HH:mm (e.g., 08:00)
            $TimeParts = $ScheduleDetails -split ':'
            $Hour = [int]$TimeParts[0]
            $Minute = [int]$TimeParts[1]

            $Candidate = [datetime]::new($ReferenceTime.Year, $ReferenceTime.Month, $ReferenceTime.Day, $Hour, $Minute, 0)
            if ($Candidate -le $ReferenceTime) {
                $Candidate = $Candidate.AddDays(1)
            }
            $NextRun = $Candidate
        }
        "Weekly" {
            # ScheduleDetails: Day,HH:mm (e.g., Monday,08:00)
            $Parts = $ScheduleDetails -split ','
            $DayOfWeek = $Parts[0]
            $TimeParts = $Parts[1] -split ':'
            $Hour = [int]$TimeParts[0]
            $Minute = [int]$TimeParts[1]

            $TargetDay = [System.DayOfWeek]::$DayOfWeek
            $Candidate = [datetime]::new($ReferenceTime.Year, $ReferenceTime.Month, $ReferenceTime.Day, $Hour, $Minute, 0)

            while ($Candidate.DayOfWeek -ne $TargetDay) {
                $Candidate = $Candidate.AddDays(1)
            }
            if ($Candidate -le $ReferenceTime) {
                $Candidate = $Candidate.AddDays(7)
            }
            $NextRun = $Candidate
        }
        "Monthly" {
            # ScheduleDetails: Day,HH:mm (e.g., 15,08:00)
            $Parts = $ScheduleDetails -split ','
            $Day = [int]$Parts[0]
            $TimeParts = $Parts[1] -split ':'
            $Hour = [int]$TimeParts[0]
            $Minute = [int]$TimeParts[1]

            $Candidate = [datetime]::new($ReferenceTime.Year, $ReferenceTime.Month, $Day, $Hour, $Minute, 0)
            if ($Candidate -le $ReferenceTime) {
                if ($ReferenceTime.Month -eq 12) {
                    $Candidate = [datetime]::new($ReferenceTime.Year + 1, 1, $Day, $Hour, $Minute, 0)
                }
                else {
                    $Candidate = [datetime]::new($ReferenceTime.Year, $ReferenceTime.Month + 1, $Day, $Hour, $Minute, 0)
                }
            }
            $NextRun = $Candidate
        }
        "Yearly" {
            # ScheduleDetails: MM,DD,HH:mm (e.g., 01,01,00:00)
            $Parts = $ScheduleDetails -split ','
            $Month = [int]$Parts[0]
            $Day = [int]$Parts[1]
            $TimeParts = $Parts[2] -split ':'
            $Hour = [int]$TimeParts[0]
            $Minute = [int]$TimeParts[1]

            $Candidate = [datetime]::new($ReferenceTime.Year, $Month, $Day, $Hour, $Minute, 0)
            if ($Candidate -le $ReferenceTime) {
                $Candidate = [datetime]::new($ReferenceTime.Year + 1, $Month, $Day, $Hour, $Minute, 0)
            }
            $NextRun = $Candidate
        }
        "Hourly" {
            # ScheduleDetails: Minutes (e.g., 30)
            $MinuteOffset = [int]$ScheduleDetails
            $Candidate = [datetime]::new($ReferenceTime.Year, $ReferenceTime.Month, $ReferenceTime.Day, $ReferenceTime.Hour, $MinuteOffset, 0)
            if ($Candidate -le $ReferenceTime) {
                $Candidate = $Candidate.AddHours(1)
            }
            $NextRun = $Candidate
        }
        "Custom" {
            # ScheduleDetails: Cron expression (e.g., 0 8 * * 1-5)
            $NextRun = Get-NextCronRun -CronExpression $ScheduleDetails -ReferenceTime $ReferenceTime
        }
        default {
            Write-JobLog "Unknown schedule type: $Schedule" -Level "ERROR" -Component "SCHEDULE"
            $NextRun = $null
        }
    }

    return $NextRun
}

function Get-NextCronRun {
    param(
        [string]$CronExpression,
        [datetime]$ReferenceTime
    )

    # Parse cron expression: minute hour day month dayofweek
    $Parts = $CronExpression -split ' '
    if ($Parts.Count -ne 5) {
        Write-JobLog "Invalid cron expression: $CronExpression" -Level "ERROR" -Component "SCHEDULE"
        return $null
    }

    $Minute = $Parts[0]
    $Hour = $Parts[1]
    $Day = $Parts[2]
    $Month = $Parts[3]
    $DayOfWeek = $Parts[4]

    # Start checking from the next minute
    $CheckTime = $ReferenceTime.AddMinutes(1)
    $MaxChecks = 525600 # 1 year of minutes

    for ($i = 0; $i -lt $MaxChecks; $i++) {
        if (Matches-CronPart -Value $CheckTime.Minute -Pattern $Minute -Range 0..59) {
            if (Matches-CronPart -Value $CheckTime.Hour -Pattern $Hour -Range 0..23) {
                if (Matches-CronPart -Value $CheckTime.Day -Pattern $Day -Range 1..31) {
                    if (Matches-CronPart -Value $CheckTime.Month -Pattern $Month -Range 1..12) {
                        $DayOfWeekValue = [int]$CheckTime.DayOfWeek
                        if (Matches-CronPart -Value $DayOfWeekValue -Pattern $DayOfWeek -Range 0..6) {
                            return $CheckTime
                        }
                    }
                }
            }
        }
        $CheckTime = $CheckTime.AddMinutes(1)
    }

    return $null
}

function Matches-CronPart {
    param(
        [int]$Value,
        [string]$Pattern,
        [array]$Range
    )

    if ($Pattern -eq '*') {
        return $true
    }

    if ($Pattern -match '^\d+$') {
        return $Value -eq [int]$Pattern
    }

    if ($Pattern -match '^(\d+)-(\d+)$') {
        $Start = [int]$Matches[1]
        $End = [int]$Matches[2]
        return $Value -ge $Start -and $Value -le $End
    }

    if ($Pattern -match '^(\d+)/(\d+)$') {
        $Start = [int]$Matches[1]
        $Step = [int]$Matches[2]
        return ($Value -ge $Start -and ($Value - $Start) % $Step -eq 0)
    }

    if ($Pattern -match ',') {
        $Parts = $Pattern -split ','
        return $Parts -contains "$Value"
    }

    return $false
}

# ---------- JOB EXECUTION FUNCTIONS ----------
function Execute-Job {
    param(
        [hashtable]$Job,
        [datetime]$ScheduledTime
    )

    $Result = @{
        JobName = $Job.JobName
        Success = $false
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Output = ""
        Error = ""
        Attempts = 0
    }

    try {
        Write-JobLog "========================================" -Level "INFO" -Component "EXECUTE"
        Write-JobLog "Executing job: $($Job.JobName)" -Level "INFO" -Component "EXECUTE"
        Write-JobLog "Scheduled time: $ScheduledTime" -Level "INFO" -Component "EXECUTE"

        # Check if job is already running (locking)
        $LockFile = Join-Path $LogPath "$($Job.JobName).lock"
        if ($EnableJobLocking -and (Test-Path $LockFile)) {
            $LockContent = Get-Content $LockFile
            $LockTime = [datetime]$LockContent
            if ((Get-Date) - $LockTime -lt (New-TimeSpan -Hours 1)) {
                Write-JobLog "Job $($Job.JobName) is already running (locked)" -Level "WARNING" -Component "EXECUTE"
                $Result.Error = "Job is already running"
                return $Result
            }
            else {
                # Remove stale lock
                Remove-Item $LockFile -Force
            }
        }

        # Create lock file
        if ($EnableJobLocking) {
            Set-Content -Path $LockFile -Value (Get-Date).ToString()
            Write-JobLog "Lock file created for $($Job.JobName)" -Level "DEBUG" -Component "EXECUTE"
        }

        # Prepare script execution
        $ScriptPath = $Job.ScriptPath
        $Parameters = $Job.Parameters
        $Timeout = if ($Job.Timeout) { [int]$Job.Timeout } else { $DefaultTimeout }
        $RetryCount = if ($Job.RetryCount) { [int]$Job.RetryCount } else { $DefaultRetryCount }
        $RetryDelay = if ($Job.RetryDelay) { [int]$Job.RetryDelay } else { $DefaultRetryDelay }

        # Check if script exists
        if (-not (Test-Path $ScriptPath)) {
            throw "Script not found: $ScriptPath"
        }

        # Execute script
        $Attempt = 0
        $Success = $false

        while ($Attempt -lt $RetryCount -and -not $Success) {
            $Attempt++
            $Result.Attempts = $Attempt
            Write-JobLog "Attempt $Attempt of $RetryCount for $($Job.JobName)" -Level "INFO" -Component "EXECUTE"

            try {
                # Create job to run script with timeout
                $JobScript = {
                    param($ScriptPath, $Parameters)

                    $Arguments = if ($Parameters) { $Parameters } else { "" }

                    # Determine job type
                    $JobType = $Job.JobType
                    switch ($JobType) {
                        "PowerShell" {
                            $Command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
                        }
                        "Cmd" {
                            $Command = "cmd.exe /c `"$ScriptPath`" $Arguments"
                        }
                        "Bash" {
                            $Command = "bash `"$ScriptPath`" $Arguments"
                        }
                        "Python" {
                            $Command = "python `"$ScriptPath`" $Arguments"
                        }
                        default {
                            throw "Unknown job type: $JobType"
                        }
                    }

                    # Execute and capture output
                    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $ProcessInfo.FileName = "powershell.exe"
                    $ProcessInfo.Arguments = "-NoProfile -Command `"$Command 2>&1`""
                    $ProcessInfo.UseShellExecute = $false
                    $ProcessInfo.RedirectStandardOutput = $true
                    $ProcessInfo.RedirectStandardError = $true
                    $ProcessInfo.CreateNoWindow = $true

                    $Process = New-Object System.Diagnostics.Process
                    $Process.StartInfo = $ProcessInfo
                    $Process.Start() | Out-Null

                    $Output = $Process.StandardOutput.ReadToEnd()
                    $Error = $Process.StandardError.ReadToEnd()
                    $Process.WaitForExit()

                    return @{
                        Success = $Process.ExitCode -eq 0
                        Output = $Output
                        Error = $Error
                        ExitCode = $Process.ExitCode
                    }
                }

                $RunJob = Start-Job -ScriptBlock $JobScript -ArgumentList $ScriptPath, $Parameters

                # Wait for job with timeout
                $JobCompleted = $RunJob | Wait-Job -Timeout $Timeout

                if ($JobCompleted) {
                    $JobResult = Receive-Job -Job $RunJob
                    Remove-Job -Job $RunJob -Force

                    if ($JobResult.Success) {
                        $Success = $true
                        $Result.Output = $JobResult.Output
                        $Result.Success = $true
                        Write-JobLog "Job $($Job.JobName) completed successfully" -Level "SUCCESS" -Component "EXECUTE"
                    }
                    else {
                        $Result.Error = $JobResult.Error
                        Write-JobLog "Job $($Job.JobName) failed with exit code: $($JobResult.ExitCode)" -Level "ERROR" -Component "EXECUTE"
                    }
                }
                else {
                    # Job timed out
                    Stop-Job -Job $RunJob -Force
                    Remove-Job -Job $RunJob -Force
                    throw "Job exceeded timeout of $Timeout seconds"
                }
            }
            catch {
                $Result.Error = $_.Exception.Message
                Write-JobLog "Job $($Job.JobName) failed: $_" -Level "ERROR" -Component "EXECUTE"
            }

            if (-not $Success -and $Attempt -lt $RetryCount) {
                Write-JobLog "Retrying in $RetryDelay seconds..." -Level "WARNING" -Component "EXECUTE"
                Start-Sleep -Seconds $RetryDelay
            }
        }

        $Result.Success = $Success

        if ($Success) {
            # Update circuit breaker on success
            Update-CircuitBreaker -JobName $Job.JobName -Success $true
        }
        else {
            # Update circuit breaker on failure
            Update-CircuitBreaker -JobName $Job.JobName -Success $false

            # Check if circuit breaker is open
            if ($EnableCircuitBreaker) {
                $State = Get-CircuitBreakerState -JobName $Job.JobName
                if ($State -and $State.Failures -ge $CircuitBreakerFailureThreshold) {
                    Write-JobLog "Circuit breaker open for $($Job.JobName)" -Level "CRITICAL" -Component "EXECUTE"
                    # Send critical notification
                    Send-Notification -Job $Job -Result $Result -Severity "CRITICAL" -Schedule $Job.Schedule
                }
            }
        }
    }
    catch {
        $Result.Success = $false
        $Result.Error = $_.Exception.Message
        Write-JobLog "Fatal error executing job $($Job.JobName): $_" -Level "CRITICAL" -Component "EXECUTE"
    }
    finally {
        $Result.EndTime = Get-Date
        $Result.Duration = ($Result.EndTime - $Result.StartTime).TotalSeconds

        # Remove lock file
        if ($EnableJobLocking) {
            $LockFile = Join-Path $LogPath "$($Job.JobName).lock"
            if (Test-Path $LockFile) {
                Remove-Item $LockFile -Force
                Write-JobLog "Lock file removed for $($Job.JobName)" -Level "DEBUG" -Component "EXECUTE"
            }
        }

        # Save history
        if ($EnableHistoryTracking) {
            Save-JobHistory -Job $Job -Result $Result
        }

        # Send notification if enabled and configured
        $NotificationEmail = $Job.NotificationEmail
        if ($NotificationEmail -and $NotificationEmail -ne "") {
            if ($Result.Success -or $Result.Error) {
                $Severity = if ($Result.Success) { "SUCCESS" } else { "ERROR" }
                Send-Notification -Job $Job -Result $Result -Severity $Severity -Schedule $Job.Schedule
            }
        }

        Write-JobLog "Job $($Job.JobName) completed in $($Result.Duration) seconds" -Level "INFO" -Component "EXECUTE"
        Write-JobLog "========================================" -Level "INFO" -Component "EXECUTE"
    }

    return $Result
}

# ---------- STATE TRACKING FUNCTIONS ----------
$JobState = @{}
$CircuitBreakerState = @{}
$JobHistory = @{}

function Update-JobState {
    param(
        [string]$JobName,
        [datetime]$NextRun,
        [hashtable]$LastResult = $null
    )

    $State = @{
        LastCheck = Get-Date
        NextRun = $NextRun
        LastRun = if ($LastResult) { $LastResult.StartTime } else { $null }
        LastResult = $LastResult
        ConsecutiveFailures = 0
    }

    if ($JobState.ContainsKey($JobName)) {
        $State.ConsecutiveFailures = $JobState[$JobName].ConsecutiveFailures
        if ($LastResult -and $LastResult.Success) {
            $State.ConsecutiveFailures = 0
        }
        elseif ($LastResult -and -not $LastResult.Success) {
            $State.ConsecutiveFailures++
        }
    }

    $JobState[$JobName] = $State
}

function Get-CircuitBreakerState {
    param([string]$JobName)

    if (-not $CircuitBreakerState.ContainsKey($JobName)) {
        return $null
    }

    return $CircuitBreakerState[$JobName]
}

function Update-CircuitBreaker {
    param(
        [string]$JobName,
        [bool]$Success
    )

    if (-not $EnableCircuitBreaker) {
        return
    }

    if (-not $CircuitBreakerState.ContainsKey($JobName)) {
        $CircuitBreakerState[$JobName] = @{
            Failures = 0
            LastFailure = Get-Date
            IsOpen = $false
            OpenTime = $null
        }
    }

    $State = $CircuitBreakerState[$JobName]

    if ($Success) {
        $State.Failures = 0
        $State.IsOpen = $false
        $State.OpenTime = $null
    }
    else {
        $State.Failures++
        $State.LastFailure = Get-Date

        if ($State.Failures -ge $CircuitBreakerFailureThreshold) {
            $State.IsOpen = $true
            $State.OpenTime = Get-Date
            Write-JobLog "Circuit breaker opened for $JobName (failures: $($State.Failures))" -Level "CRITICAL" -Component "CIRCUIT"
        }
    }
}

function Is-CircuitBreakerOpen {
    param([string]$JobName)

    if (-not $EnableCircuitBreaker) {
        return $false
    }

    $State = Get-CircuitBreakerState -JobName $JobName
    if (-not $State -or -not $State.IsOpen) {
        return $false
    }

    # Check if circuit breaker should auto-close
    $TimeSinceOpen = (Get-Date) - $State.OpenTime
    if ($TimeSinceOpen.TotalSeconds -gt $CircuitBreakerTimeout) {
        $State.IsOpen = $false
        $State.Failures = 0
        Write-JobLog "Circuit breaker closed for $JobName (timeout reached)" -Level "INFO" -Component "CIRCUIT"
        return $false
    }

    return $true
}

function Save-JobHistory {
    param(
        [hashtable]$Job,
        [hashtable]$Result
    )

    if (-not $EnableHistoryTracking) {
        return
    }

    try {
        if (!(Test-Path $HistoryPath)) {
            New-Item -ItemType Directory -Path $HistoryPath -Force | Out-Null
        }

        $Date = Get-Date -Format "yyyyMMdd"
        $FilePath = Join-Path $HistoryPath "History_$Date.csv"

        $Record = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            JobName = $Job.JobName
            Success = $Result.Success
            StartTime = $Result.StartTime
            EndTime = $Result.EndTime
            Duration = $Result.Duration
            Attempts = $Result.Attempts
            Error = if ($Result.Error) { $Result.Error.Substring(0, [Math]::Min(1000, $Result.Error.Length)) } else { "" }
            Schedule = $Job.Schedule
            ScriptPath = $Job.ScriptPath
        }

        if (Test-Path $FilePath) {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation
        }

        # Add to history cache
        if (-not $JobHistory.ContainsKey($Job.JobName)) {
            $JobHistory[$Job.JobName] = @()
        }
        $JobHistory[$Job.JobName] += $Record

        # Clean up old history
        $CutoffDate = (Get-Date).AddDays(-$HistoryRetentionDays)
        Get-ChildItem -Path $HistoryPath -Filter "History_*.csv" | ForEach-Object {
            if ($_.LastWriteTime -lt $CutoffDate) {
                Remove-Item $_.FullName -Force
            }
        }
    }
    catch {
        Write-JobLog "Failed to save job history: $_" -Level "WARNING" -Component "HISTORY"
    }
}

# ---------- NOTIFICATION FUNCTIONS ----------
function Send-Notification {
    param(
        [hashtable]$Job,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Schedule
    )

    if (-not $EnableNotifications) {
        return
    }

    $Results = @{
        Email = $false
        Teams = $false
        Slack = $false
    }

    # Send email notification
    if ($Job.NotificationEmail -and $Job.NotificationEmail -ne "") {
        $Results.Email = Send-EmailNotification -Job $Job -Result $Result -Severity $Severity -Schedule $Schedule
    }

    # Send Teams notification
    if ($TeamsConfig.Enabled) {
        $Results.Teams = Send-TeamsNotification -Job $Job -Result $Result -Severity $Severity -Schedule $Schedule
    }

    # Send Slack notification
    if ($SlackConfig.Enabled) {
        $Results.Slack = Send-SlackNotification -Job $Job -Result $Result -Severity $Severity -Schedule $Schedule
    }

    return $Results
}

function Send-EmailNotification {
    param(
        [hashtable]$Job,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Schedule
    )

    if (-not $EmailConfig.Enabled) {
        return $false
    }

    try {
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $To = $Job.NotificationEmail
        if (-not $To -or $To -eq "") {
            $To = $EmailConfig.DefaultTo
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $Body = $EmailNotificationTemplate
        $Body = $Body.Replace('{Timestamp}', $Timestamp)
        $Body = $Body.Replace('{JobName}', $Job.JobName)
        $Body = $Body.Replace('{Status}', if ($Result.Success) { "SUCCESS" } else { "FAILED" })
        $Body = $Body.Replace('{Schedule}', $Schedule)
        $Body = $Body.Replace('{StartTime}', $Result.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Body = $Body.Replace('{EndTime}', $Result.EndTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Body = $Body.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Body = $Body.Replace('{Attempts}', $Result.Attempts)
        $Body = $Body.Replace('{ScriptPath}', $Job.ScriptPath)
        $Body = $Body.Replace('{Parameters}', if ($Job.Parameters) { $Job.Parameters } else { "None" })
        $Body = $Body.Replace('{Output}', if ($Result.Output) { $Result.Output } else { "No output" })
        $Body = $Body.Replace('{LogPath}', $LogPath)

        $Subject = "[$Severity] Job: $($Job.JobName) - $(if ($Result.Success) { "SUCCESS" } else { "FAILED" })"

        $MailParams = @{
            To = $To
            From = $EmailConfig.From
            Subject = $Subject
            Body = $Body
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
        Write-JobLog "Email notification sent to: $To" -Level "INFO" -Component "NOTIFY"
        return $true
    }
    catch {
        Write-JobLog "Failed to send email notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-TeamsNotification {
    param(
        [hashtable]$Job,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Schedule
    )

    if (-not $TeamsConfig.Enabled) {
        return $false
    }

    try {
        $ThemeColor = @{
            'SUCCESS' = '00FF00'
            'ERROR' = 'FF0000'
            'WARNING' = 'FFA500'
            'CRITICAL' = '8B0000'
            'INFO' = '0000FF'
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $WebhookURLs = $TeamsConfig.WebhookURLs

        $Payload = $TeamsNotificationTemplate
        $Payload = $Payload.Replace('{ThemeColor}', $ThemeColor[$Severity])
        $Payload = $Payload.Replace('{Summary}', "$Severity: $($Job.JobName)")
        $Payload = $Payload.Replace('{ActivityTitle}', "**$Severity: $($Job.JobName)**")
        $Payload = $Payload.Replace('{JobName}', $Job.JobName)
        $Payload = $Payload.Replace('{Status}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Payload = $Payload.Replace('{Schedule}', $Schedule)
        $Payload = $Payload.Replace('{StartTime}', $Result.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Payload = $Payload.Replace('{EndTime}', $Result.EndTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Payload = $Payload.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Payload = $Payload.Replace('{Attempts}', $Result.Attempts)
        $Payload = $Payload.Replace('{ScriptPath}', $Job.ScriptPath)
        $Payload = $Payload.Replace('{LogPath}', $LogPath)

        $Success = $true
        foreach ($URL in $WebhookURLs) {
            try {
                $Params = @{
                    Uri = $URL
                    Method = 'Post'
                    Body = $Payload
                    ContentType = 'application/json'
                    UseBasicParsing = $true
                    ErrorAction = 'Stop'
                }
                Invoke-RestMethod @Params
                Write-JobLog "Teams notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-JobLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-JobLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-SlackNotification {
    param(
        [hashtable]$Job,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Schedule
    )

    if (-not $SlackConfig.Enabled) {
        return $false
    }

    try {
        $ColorMap = @{
            'SUCCESS' = 'good'
            'ERROR' = 'danger'
            'WARNING' = 'warning'
            'CRITICAL' = 'danger'
            'INFO' = 'good'
        }

        $Timestamp = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))
        $WebhookURLs = $SlackConfig.WebhookURLs

        $Payload = $SlackNotificationTemplate
        $Payload = $Payload.Replace('{Channel}', $SlackConfig.Channel)
        $Payload = $Payload.Replace('{Username}', $SlackConfig.Username)
        $Payload = $Payload.Replace('{IconEmoji}', $SlackConfig.IconEmoji)
        $Payload = $Payload.Replace('{Color}', $ColorMap[$Severity])
        $Payload = $Payload.Replace('{Title}', "$Severity: $($Job.JobName)")
        $Payload = $Payload.Replace('{JobName}', $Job.JobName)
        $Payload = $Payload.Replace('{Status}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Payload = $Payload.Replace('{Schedule}', $Schedule)
        $Payload = $Payload.Replace('{StartTime}', $Result.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Payload = $Payload.Replace('{EndTime}', $Result.EndTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Payload = $Payload.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Payload = $Payload.Replace('{Attempts}', $Result.Attempts)
        $Payload = $Payload.Replace('{ScriptPath}', $Job.ScriptPath)
        $Payload = $Payload.Replace('{Timestamp}', $Timestamp)

        $Success = $true
        foreach ($URL in $WebhookURLs) {
            try {
                $Params = @{
                    Uri = $URL
                    Method = 'Post'
                    Body = $Payload
                    ContentType = 'application/json'
                    UseBasicParsing = $true
                    ErrorAction = 'Stop'
                }
                Invoke-RestMethod @Params
                Write-JobLog "Slack notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-JobLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-JobLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}