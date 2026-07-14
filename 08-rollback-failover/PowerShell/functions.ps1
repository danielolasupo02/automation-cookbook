# ============================================================
# ROLLBACK & FAILOVER - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for deployment monitoring,
# rollbacks, and failover procedures.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-RollbackLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "ROLLBACK-FAILOVER"
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
            $LogFile = Join-Path $LogPath "RollbackFailover_$(Get-Date -Format 'yyyyMMdd').log"
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
            Write-RollbackLog "Credential '$CredentialName' not found" -Level "WARNING" -Component "CREDENTIALS"
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
        Write-RollbackLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

# ---------- POLICY LOADING FUNCTIONS ----------
function Load-DeploymentPolicies {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-RollbackLog "Deployment policies file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Policies = Import-Csv -Path $FilePath | Where-Object {
        $_.PolicyName -and $_.PolicyName -notmatch '^#'
    }

    Write-RollbackLog "Loaded $($Policies.Count) deployment policies from $FilePath" -Level "INFO" -Component "CONFIG"

    $EnabledPolicies = $Policies | Where-Object { $_.Enabled -eq 'true' -or $_.Enabled -eq 'TRUE' }
    Write-RollbackLog "$($EnabledPolicies.Count) policies are enabled" -Level "INFO" -Component "CONFIG"

    return $EnabledPolicies
}

# ---------- HEALTH CHECK FUNCTIONS ----------
function Test-DeploymentHealth {
    param(
        [string]$HealthCheckURL,
        [string]$ExpectedResponse,
        [int]$Timeout = 30
    )

    if (-not $HealthCheckURL -or $HealthCheckURL -eq "") {
        Write-RollbackLog "No health check URL provided" -Level "DEBUG" -Component "HEALTH"
        return $true
    }

    try {
        Write-RollbackLog "Checking health at: $HealthCheckURL" -Level "DEBUG" -Component "HEALTH"

        $WebRequestParams = @{
            Uri = $HealthCheckURL
            UseBasicParsing = $true
            TimeoutSec = $Timeout
            ErrorAction = 'Stop'
        }

        $Response = Invoke-WebRequest @WebRequestParams

        # Check expected response
        if ($ExpectedResponse -and $ExpectedResponse -ne "") {
            if ($ExpectedResponse -match '^\d+$') {
                # It's a status code
                $StatusCode = [int]$ExpectedResponse
                $Result = $Response.StatusCode -eq $StatusCode
                Write-RollbackLog "Health check: Expected $StatusCode, Got $($Response.StatusCode) - $(if ($Result) { 'PASS' } else { 'FAIL' })" -Level "DEBUG" -Component "HEALTH"
                return $Result
            }
            else {
                # It's text to match
                $Result = $Response.Content -match $ExpectedResponse
                Write-RollbackLog "Health check: $(if ($Result) { 'PASS' } else { 'FAIL' })" -Level "DEBUG" -Component "HEALTH"
                return $Result
            }
        }
        else {
            # Just check if status code is 200
            $Result = $Response.StatusCode -eq 200
            Write-RollbackLog "Health check: HTTP $($Response.StatusCode) - $(if ($Result) { 'PASS' } else { 'FAIL' })" -Level "DEBUG" -Component "HEALTH"
            return $Result
        }
    }
    catch {
        Write-RollbackLog "Health check failed: $_" -Level "WARNING" -Component "HEALTH"
        return $false
    }
}

function Get-DeploymentStatus {
    param(
        [string]$PolicyName,
        [string]$DeploymentPath
    )

    $StatusFile = Join-Path $DeploymentStatusPath "$PolicyName-status.json"

    if (Test-Path $StatusFile) {
        try {
            $Status = Get-Content $StatusFile | ConvertFrom-Json
            return $Status
        }
        catch {
            Write-RollbackLog "Failed to read status file for $PolicyName: $_" -Level "WARNING" -Component "STATUS"
        }
    }

    return $null
}

function Save-DeploymentStatus {
    param(
        [string]$PolicyName,
        [hashtable]$Status
    )

    if (-not $EnableStatePersistence) {
        return
    }

    try {
        if (!(Test-Path $DeploymentStatusPath)) {
            New-Item -ItemType Directory -Path $DeploymentStatusPath -Force | Out-Null
        }

        $StatusFile = Join-Path $DeploymentStatusPath "$PolicyName-status.json"
        $Status | ConvertTo-Json | Set-Content -Path $StatusFile
        Write-RollbackLog "Saved status for $PolicyName" -Level "DEBUG" -Component "STATUS"
    }
    catch {
        Write-RollbackLog "Failed to save status for $PolicyName: $_" -Level "WARNING" -Component "STATUS"
    }
}

# ---------- DEPLOYMENT VALIDATION ----------
function Validate-Deployment {
    param(
        [hashtable]$Policy,
        [string]$DeploymentVersion = "Latest"
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
        ValidationResults = @()
    }

    try {
        Write-RollbackLog "Validating deployment for $($Policy.PolicyName)" -Level "INFO" -Component "VALIDATE"

        # Check if deployment path exists
        if (-not (Test-Path $Policy.DeploymentPath)) {
            throw "Deployment path not found: $($Policy.DeploymentPath)"
        }

        # Check for deployment marker file
        $DeploymentMarker = Join-Path $Policy.DeploymentPath "deployment.info"
        if (Test-Path $DeploymentMarker) {
            $MarkerContent = Get-Content $DeploymentMarker -Raw
            $Result.Details.DeploymentInfo = $MarkerContent
        }

        # Check for required files
        $RequiredFiles = @("web.config", "appsettings.json", "package.json")
        $MissingFiles = @()
        foreach ($File in $RequiredFiles) {
            if (Test-Path (Join-Path $Policy.DeploymentPath $File)) {
                $Result.ValidationResults += "Found: $File"
            }
            else {
                $MissingFiles += $File
            }
        }

        if ($MissingFiles.Count -gt 0) {
            Write-RollbackLog "Missing required files: $($MissingFiles -join ', ')" -Level "WARNING" -Component "VALIDATE"
            $Result.ValidationResults += "Missing: $($MissingFiles -join ', ')"
        }

        # Check directory structure
        $SubDirectories = Get-ChildItem -Path $Policy.DeploymentPath -Directory
        $Result.ValidationResults += "Found $($SubDirectories.Count) subdirectories"

        # Check file count
        $Files = Get-ChildItem -Path $Policy.DeploymentPath -File -Recurse
        $Result.ValidationResults += "Total files: $($Files.Count)"

        # Check total size
        $TotalSize = ($Files | Measure-Object -Property Length -Sum).Sum
        $Result.ValidationResults += "Total size: $(Format-FileSize $TotalSize)"

        $Result.Success = $true
        $Result.Message = "Deployment validation completed"

        Write-RollbackLog "Deployment validation successful for $($Policy.PolicyName)" -Level "SUCCESS" -Component "VALIDATE"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-RollbackLog "Deployment validation failed for $($Policy.PolicyName): $_" -Level "ERROR" -Component "VALIDATE"
    }

    return $Result
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }
    elseif ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

# ---------- ROLLBACK FUNCTIONS ----------
function Execute-Rollback {
    param(
        [hashtable]$Policy,
        [string]$RollbackScript,
        [hashtable]$DeploymentStatus
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Output = ""
    }

    try {
        Write-RollbackLog "========================================" -Level "INFO" -Component "ROLLBACK"
        Write-RollbackLog "Executing rollback for $($Policy.PolicyName)" -Level "INFO" -Component "ROLLBACK"
        Write-RollbackLog "Rollback script: $RollbackScript" -Level "INFO" -Component "ROLLBACK"

        if (-not (Test-Path $RollbackScript)) {
            throw "Rollback script not found: $RollbackScript"
        }

        # Build command to execute rollback script
        $Command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$RollbackScript`" -PolicyName `"$($Policy.PolicyName)`" -DeploymentPath `"$($Policy.DeploymentPath)`""

        if ($DeploymentStatus) {
            $Command += " -DeploymentStatus `"$($DeploymentStatus | ConvertTo-Json -Compress)`""
        }

        Write-RollbackLog "Executing: $Command" -Level "DEBUG" -Component "ROLLBACK"

        # Execute with timeout
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
        $Process.WaitForExit($RollbackTimeout * 1000)

        $Result.Output = $Output

        if ($Process.ExitCode -eq 0) {
            $Result.Success = $true
            $Result.Message = "Rollback completed successfully"
            Write-RollbackLog "Rollback completed successfully" -Level "SUCCESS" -Component "ROLLBACK"
        }
        else {
            $Result.Message = "Rollback failed with exit code: $($Process.ExitCode)"
            Write-RollbackLog "Rollback failed with exit code: $($Process.ExitCode)" -Level "ERROR" -Component "ROLLBACK"
            if ($Error) {
                $Result.Details.Error = $Error
                Write-RollbackLog "Error output: $Error" -Level "ERROR" -Component "ROLLBACK"
            }
        }

        if (-not $Process.HasExited) {
            $Process.Kill()
            $Result.Message = "Rollback timed out after $RollbackTimeout seconds"
            Write-RollbackLog "Rollback timed out" -Level "ERROR" -Component "ROLLBACK"
        }
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-RollbackLog "Rollback failed: $_" -Level "ERROR" -Component "ROLLBACK"
    }
    finally {
        $Result.EndTime = Get-Date
        $Result.Duration = ($Result.EndTime - $Result.StartTime).TotalSeconds
        Write-RollbackLog "Rollback completed in $($Result.Duration) seconds" -Level "INFO" -Component "ROLLBACK"
        Write-RollbackLog "========================================" -Level "INFO" -Component "ROLLBACK"
    }

    return $Result
}

# ---------- FAILOVER FUNCTIONS ----------
function Execute-Failover {
    param(
        [hashtable]$Policy,
        [string]$FailoverScript,
        [hashtable]$DeploymentStatus
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Output = ""
    }

    try {
        Write-RollbackLog "========================================" -Level "INFO" -Component "FAILOVER"
        Write-RollbackLog "Executing failover for $($Policy.PolicyName)" -Level "INFO" -Component "FAILOVER"
        Write-RollbackLog "Failover script: $FailoverScript" -Level "INFO" -Component "FAILOVER"

        if (-not (Test-Path $FailoverScript)) {
            throw "Failover script not found: $FailoverScript"
        }

        # Build command to execute failover script
        $Command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$FailoverScript`" -PolicyName `"$($Policy.PolicyName)`" -DeploymentPath `"$($Policy.DeploymentPath)`""

        if ($DeploymentStatus) {
            $Command += " -DeploymentStatus `"$($DeploymentStatus | ConvertTo-Json -Compress)`""
        }

        Write-RollbackLog "Executing: $Command" -Level "DEBUG" -Component "FAILOVER"

        # Execute with timeout
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
        $Process.WaitForExit($FailoverTimeout * 1000)

        $Result.Output = $Output

        if ($Process.ExitCode -eq 0) {
            $Result.Success = $true
            $Result.Message = "Failover completed successfully"
            Write-RollbackLog "Failover completed successfully" -Level "SUCCESS" -Component "FAILOVER"
        }
        else {
            $Result.Message = "Failover failed with exit code: $($Process.ExitCode)"
            Write-RollbackLog "Failover failed with exit code: $($Process.ExitCode)" -Level "ERROR" -Component "FAILOVER"
            if ($Error) {
                $Result.Details.Error = $Error
                Write-RollbackLog "Error output: $Error" -Level "ERROR" -Component "FAILOVER"
            }
        }

        if (-not $Process.HasExited) {
            $Process.Kill()
            $Result.Message = "Failover timed out after $FailoverTimeout seconds"
            Write-RollbackLog "Failover timed out" -Level "ERROR" -Component "FAILOVER"
        }

        # Validate failover if enabled
        if ($EnableFailoverValidation -and $Result.Success) {
            Write-RollbackLog "Validating failover..." -Level "INFO" -Component "FAILOVER"

            $ValidationPassed = $false
            for ($i = 1; $i -le $FailoverValidationRetries; $i++) {
                if ($i -gt 1) {
                    Start-Sleep -Seconds $FailoverValidationInterval
                }

                $HealthResult = Test-DeploymentHealth -HealthCheckURL $Policy.HealthCheckURL -ExpectedResponse $Policy.ExpectedResponse -Timeout 30
                if ($HealthResult) {
                    $ValidationPassed = $true
                    Write-RollbackLog "Failover validation passed (attempt $i)" -Level "SUCCESS" -Component "FAILOVER"
                    break
                }
                else {
                    Write-RollbackLog "Failover validation failed (attempt $i of $FailoverValidationRetries)" -Level "WARNING" -Component "FAILOVER"
                }
            }

            if (-not $ValidationPassed) {
                $Result.Success = $false
                $Result.Message = "Failover validation failed after $FailoverValidationRetries attempts"
                Write-RollbackLog "Failover validation failed" -Level "ERROR" -Component "FAILOVER"
            }
        }
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-RollbackLog "Failover failed: $_" -Level "ERROR" -Component "FAILOVER"
    }
    finally {
        $Result.EndTime = Get-Date
        $Result.Duration = ($Result.EndTime - $Result.StartTime).TotalSeconds
        Write-RollbackLog "Failover completed in $($Result.Duration) seconds" -Level "INFO" -Component "FAILOVER"
        Write-RollbackLog "========================================" -Level "INFO" -Component "FAILOVER"
    }

    return $Result
}

# ---------- DEPLOYMENT MONITORING ----------
function Monitor-Deployment {
    param(
        [hashtable]$Policy
    )

    $Result = @{
        PolicyName = $Policy.PolicyName
        Success = $false
        Status = "Unknown"
        Action = "None"
        Attempts = 0
        DeploymentStatus = $null
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        Output = @()
        HealthCheckPassed = $false
    }

    try {
        Write-RollbackLog "========================================" -Level "INFO" -Component "MONITOR"
        Write-RollbackLog "Monitoring deployment for $($Policy.PolicyName)" -Level "INFO" -Component "MONITOR"

        # Get current deployment status
        $DeploymentStatus = Get-DeploymentStatus -PolicyName $Policy.PolicyName -DeploymentPath $Policy.DeploymentPath
        $Result.DeploymentStatus = $DeploymentStatus

        # Check if deployment is in progress
        if ($DeploymentStatus -and $DeploymentStatus.Status -eq "InProgress") {
            Write-RollbackLog "Deployment already in progress" -Level "INFO" -Component "MONITOR"
            $Result.Status = "InProgress"
            return $Result
        }

        # Check deployment health
        $Attempt = 0
        $HealthPassed = $false
        $MaxRetries = [int]$Policy.MaxRetries

        while ($Attempt -lt $MaxRetries -and -not $HealthPassed) {
            $Attempt++
            $Result.Attempts = $Attempt
            Write-RollbackLog "Health check attempt $Attempt of $MaxRetries" -Level "INFO" -Component "MONITOR"

            $HealthResult = Test-DeploymentHealth -HealthCheckURL $Policy.HealthCheckURL -ExpectedResponse $Policy.ExpectedResponse -Timeout 30

            if ($HealthResult) {
                $HealthPassed = $true
                $Result.HealthCheckPassed = $true
                $Result.Success = $true
                $Result.Status = "Healthy"
                Write-RollbackLog "Deployment is healthy" -Level "SUCCESS" -Component "MONITOR"
                break
            }
            else {
                Write-RollbackLog "Health check failed (attempt $Attempt)" -Level "WARNING" -Component "MONITOR"

                if ($Attempt -lt $MaxRetries) {
                    $RetryInterval = [int]$Policy.RetryInterval
                    Write-RollbackLog "Waiting $RetryInterval seconds before retry..." -Level "INFO" -Component "MONITOR"
                    Start-Sleep -Seconds $RetryInterval
                }
            }
        }

        # If health checks failed, take action
        if (-not $HealthPassed) {
            $Result.Status = "Failed"
            $Result.Output += "Health check failed after $MaxRetries attempts"

            Write-RollbackLog "Deployment failed health checks" -Level "ERROR" -Component "MONITOR"

            # Check if automatic rollback is enabled
            if ($EnableAutoRollback -and $Policy.RollbackScript -and $Policy.RollbackScript -ne "") {
                Write-RollbackLog "Initiating rollback..." -Level "WARNING" -Component "MONITOR"
                $Result.Action = "Rollback"

                # Execute rollback with retries
                $RollbackSuccess = $false
                for ($i = 1; $i -le $RollbackRetries; $i++) {
                    $RollbackResult = Execute-Rollback -Policy $Policy -RollbackScript $Policy.RollbackScript -DeploymentStatus $DeploymentStatus

                    if ($RollbackResult.Success) {
                        $RollbackSuccess = $true
                        $Result.Output += "Rollback successful"
                        break
                    }
                    else {
                        Write-RollbackLog "Rollback attempt $i of $RollbackRetries failed" -Level "ERROR" -Component "MONITOR"

                        if ($i -lt $RollbackRetries) {
                            Start-Sleep -Seconds $RollbackRetryInterval
                        }
                    }
                }

                if ($RollbackSuccess) {
                    $Result.Success = $true
                    $Result.Status = "RolledBack"
                    Write-RollbackLog "Rollback completed successfully" -Level "SUCCESS" -Component "MONITOR"
                }
                else {
                    $Result.Output += "Rollback failed after $RollbackRetries attempts"
                    Write-RollbackLog "Rollback failed" -Level "CRITICAL" -Component "MONITOR"

                    # Check if automatic failover is enabled
                    if ($EnableAutoFailover -and $Policy.FailoverScript -and $Policy.FailoverScript -ne "") {
                        Write-RollbackLog "Initiating failover..." -Level "CRITICAL" -Component "MONITOR"
                        $Result.Action = "Failover"

                        $FailoverResult = Execute-Failover -Policy $Policy -FailoverScript $Policy.FailoverScript -DeploymentStatus $DeploymentStatus

                        if ($FailoverResult.Success) {
                            $Result.Success = $true
                            $Result.Status = "FailedOver"
                            $Result.Output += "Failover successful"
                            Write-RollbackLog "Failover completed successfully" -Level "SUCCESS" -Component "MONITOR"
                        }
                        else {
                            $Result.Status = "Failed"
                            $Result.Output += "Failover failed"
                            Write-RollbackLog "Failover failed" -Level "CRITICAL" -Component "MONITOR"
                        }
                    }
                }
            }
            else {
                Write-RollbackLog "Automatic rollback/failover not enabled" -Level "WARNING" -Component "MONITOR"
                $Result.Status = "Failed"
                $Result.Output += "No automatic recovery configured"
            }
        }

        # Update deployment status
        if ($Result.Success) {
            $StatusUpdate = @{
                Status = $Result.Status
                LastCheck = Get-Date
                LastResult = $Result
                DeploymentPath = $Policy.DeploymentPath
            }
            Save-DeploymentStatus -PolicyName $Policy.PolicyName -Status $StatusUpdate
        }

        # Send notification
        if ($Result.Status -ne "Healthy") {
            $Severity = if ($Result.Status -eq "RolledBack") { "WARNING" }
                        elseif ($Result.Status -eq "FailedOver") { "WARNING" }
                        else { "ERROR" }

            Send-Notification -Policy $Policy -Result $Result -Severity $Severity
        }
        else {
            # Send success notification if health check passed
            Send-Notification -Policy $Policy -Result $Result -Severity "SUCCESS"
        }
    }
    catch {
        $Result.Success = $false
        $Result.Status = "Error"
        $Result.Output += $_.Exception.Message
        Write-RollbackLog "Error monitoring deployment $($Policy.PolicyName): $_" -Level "ERROR" -Component "MONITOR"

        # Send error notification
        Send-Notification -Policy $Policy -Result $Result -Severity "CRITICAL"
    }
    finally {
        $Result.EndTime = Get-Date
        $Result.Duration = ($Result.EndTime - $Result.StartTime).TotalSeconds
        Write-RollbackLog "Monitoring completed in $($Result.Duration) seconds" -Level "INFO" -Component "MONITOR"
        Write-RollbackLog "========================================" -Level "INFO" -Component "MONITOR"
    }

    # Save performance data
    if ($EnablePerformanceTracking) {
        Save-DeploymentHistory -Policy $Policy -Result $Result
    }

    return $Result
}

# ---------- NOTIFICATION FUNCTIONS ----------
function Send-Notification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity
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
    if ($EmailConfig.Enabled) {
        $Results.Email = Send-EmailNotification -Policy $Policy -Result $Result -Severity $Severity
    }

    # Send Teams notification
    if ($TeamsConfig.Enabled) {
        $Results.Teams = Send-TeamsNotification -Policy $Policy -Result $Result -Severity $Severity
    }

    # Send Slack notification
    if ($SlackConfig.Enabled) {
        $Results.Slack = Send-SlackNotification -Policy $Policy -Result $Result -Severity $Severity
    }

    return $Results
}

function Send-EmailNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity
    )

    if (-not $EmailConfig.Enabled) {
        return $false
    }

    try {
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $SeverityClass = switch ($Severity) {
            "SUCCESS" { "success" }
            "WARNING" { "warning" }
            "ERROR" { "error" }
            "CRITICAL" { "critical" }
            default { "info" }
        }

        $SeverityBadge = switch ($Severity) {
            "SUCCESS" { "success" }
            "WARNING" { "warning" }
            "ERROR" { "error" }
            "CRITICAL" { "critical" }
            default { "info" }
        }

        $StatusBadge = switch ($Result.Status) {
            "Healthy" { "success" }
            "RolledBack" { "warning" }
            "FailedOver" { "info" }
            "Failed" { "error" }
            "Error" { "critical" }
            default { "info" }
        }

        $Body = $EmailNotificationTemplate
        $Body = $Body.Replace('{Timestamp}', $Timestamp)
        $Body = $Body.Replace('{PolicyName}', $Policy.PolicyName)
        $Body = $Body.Replace('{DeploymentType}', $Policy.DeploymentType)
        $Body = $Body.Replace('{DeploymentPath}', $Policy.DeploymentPath)
        $Body = $Body.Replace('{Severity}', $Severity)
        $Body = $Body.Replace('{SeverityClass}', $SeverityClass)
        $Body = $Body.Replace('{SeverityBadge}', $SeverityBadge)
        $Body = $Body.Replace('{Status}', $Result.Status)
        $Body = $Body.Replace('{StatusBadge}', $StatusBadge)
        $Body = $Body.Replace('{EventType}', $Result.Action)
        $Body = $Body.Replace('{StartTime}', $Result.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Body = $Body.Replace('{EndTime}', $Result.EndTime.ToString("yyyy-MM-dd HH:mm:ss"))
        $Body = $Body.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Body = $Body.Replace('{Attempts}', $Result.Attempts)
        $Body = $Body.Replace('{ActionTaken}', $Result.Action)
        $Body = $Body.Replace('{ActionResult}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Body = $Body.Replace('{LogPath}', $LogPath)

        $DetailedOutput = ""
        if ($Result.Output -and $Result.Output.Count -gt 0) {
            $DetailedOutput = "<div class='info'><h3>Detailed Output</h3><pre>"
            $DetailedOutput += ($Result.Output -join "`n")
            $DetailedOutput += "</pre></div>"
        }
        $Body = $Body.Replace('{DetailedOutput}', $DetailedOutput)

        $Subject = "[$Severity] Rollback/Failover: $($Policy.PolicyName) - $($Result.Status)"

        $MailParams = @{
            To = $EmailConfig.To
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
        Write-RollbackLog "Email notification sent" -Level "INFO" -Component "NOTIFY"
        return $true
    }
    catch {
        Write-RollbackLog "Failed to send email notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-TeamsNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity
    )

    if (-not $TeamsConfig.Enabled) {
        return $false
    }

    try {
        $ThemeColor = @{
            'SUCCESS' = '00FF00'
            'WARNING' = 'FFA500'
            'ERROR' = 'FF0000'
            'CRITICAL' = '8B0000'
            'INFO' = '0000FF'
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $WebhookURLs = $TeamsConfig.WebhookURLs

        $Payload = $TeamsNotificationTemplate
        $Payload = $Payload.Replace('{ThemeColor}', $ThemeColor[$Severity])
        $Payload = $Payload.Replace('{Summary}', "$Severity: $($Policy.PolicyName) - $($Result.Status)")
        $Payload = $Payload.Replace('{ActivityTitle}', "**$Severity: $($Policy.PolicyName)**")
        $Payload = $Payload.Replace('{PolicyName}', $Policy.PolicyName)
        $Payload = $Payload.Replace('{EventType}', $Result.Action)
        $Payload = $Payload.Replace('{Status}', $Result.Status)
        $Payload = $Payload.Replace('{DeploymentType}', $Policy.DeploymentType)
        $Payload = $Payload.Replace('{ActionTaken}', $Result.Action)
        $Payload = $Payload.Replace('{ActionResult}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Payload = $Payload.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Payload = $Payload.Replace('{Attempts}', $Result.Attempts)
        $Payload = $Payload.Replace('{Timestamp}', $Timestamp)
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
                Write-RollbackLog "Teams notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-RollbackLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-RollbackLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-SlackNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity
    )

    if (-not $SlackConfig.Enabled) {
        return $false
    }

    try {
        $ColorMap = @{
            'SUCCESS' = 'good'
            'WARNING' = 'warning'
            'ERROR' = 'danger'
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
        $Payload = $Payload.Replace('{Title}', "$Severity: $($Policy.PolicyName) - $($Result.Status)")
        $Payload = $Payload.Replace('{EventType}', $Result.Action)
        $Payload = $Payload.Replace('{PolicyName}', $Policy.PolicyName)
        $Payload = $Payload.Replace('{Status}', $Result.Status)
        $Payload = $Payload.Replace('{DeploymentType}', $Policy.DeploymentType)
        $Payload = $Payload.Replace('{ActionTaken}', $Result.Action)
        $Payload = $Payload.Replace('{ActionResult}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Payload = $Payload.Replace('{Duration}', [Math]::Round($Result.Duration, 2))
        $Payload = $Payload.Replace('{Attempts}', $Result.Attempts)
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
                Write-RollbackLog "Slack notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-RollbackLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-RollbackLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

# ---------- PERFORMANCE TRACKING ----------
function Save-DeploymentHistory {
    param(
        [hashtable]$Policy,
        [hashtable]$Result
    )

    if (-not $EnablePerformanceTracking) {
        return
    }

    try {
        if (!(Test-Path $PerformanceDataPath)) {
            New-Item -ItemType Directory -Path $PerformanceDataPath -Force | Out-Null
        }

        $Date = Get-Date -Format "yyyyMMdd"
        $FilePath = Join-Path $PerformanceDataPath "Deployments_$Date.csv"

        $Record = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            PolicyName = $Policy.PolicyName
            Status = $Result.Status
            Action = $Result.Action
            Success = $Result.Success
            Attempts = $Result.Attempts
            Duration = $Result.Duration
            HealthCheckPassed = $Result.HealthCheckPassed
            Output = ($Result.Output -join "; ")
        }

        if (Test-Path $FilePath) {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation
        }
    }
    catch {
        Write-RollbackLog "Failed to save deployment history: $_" -Level "WARNING" -Component "PERF"
    }
}