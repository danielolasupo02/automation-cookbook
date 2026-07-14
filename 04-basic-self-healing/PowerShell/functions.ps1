# ============================================================
# IIS SELF-HEALING - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for IIS monitoring,
# restart operations, and notifications.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-IISLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "IIS-HEALING"
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
            $LogFile = Join-Path $LogPath "IISHealing_$(Get-Date -Format 'yyyyMMdd').log"
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
            Write-IISLog "Credential '$CredentialName' not found" -Level "WARNING" -Component "CREDENTIALS"
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
        Write-IISLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

# ---------- IIS APPLICATION LOADING FUNCTIONS ----------
function Load-ApplicationDefinitions {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-IISLog "Application definitions file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Apps = Import-Csv -Path $FilePath | Where-Object {
        $_.SiteName -and $_.SiteName -notmatch '^#'
    }

    Write-IISLog "Loaded $($Apps.Count) application definitions from $FilePath" -Level "INFO" -Component "CONFIG"

    # Validate applications
    foreach ($App in $Apps) {
        if ($App.RestartMethod -notin @('AppPool', 'ApplicationPool', 'Site', 'All')) {
            Write-IISLog "WARNING: Invalid RestartMethod '$($App.RestartMethod)' for $($App.SiteName)$($App.ApplicationPath)" -Level "WARNING" -Component "CONFIG"
        }
    }

    return $Apps
}

function Get-AppConfig {
    param(
        [string]$SiteName,
        [string]$ApplicationPath,
        [array]$AppDefinitions
    )

    return $AppDefinitions | Where-Object {
        $_.SiteName -eq $SiteName -and $_.ApplicationPath -eq $ApplicationPath
    } | Select-Object -First 1
}

# ---------- IIS MODULE LOADING ----------
function Initialize-IISModules {
    Write-IISLog "Initializing IIS modules..." -Level "INFO" -Component "INIT"

    try {
        # Load WebAdministration module
        if ($UseWebAdministration) {
            Import-Module WebAdministration -ErrorAction Stop
            Write-IISLog "WebAdministration module loaded successfully" -Level "SUCCESS" -Component "INIT"
        }

        # Check if IIS is available
        try {
            $IISCheck = Get-IISSite -Name "Default Web Site" -ErrorAction SilentlyContinue
            if ($IISCheck) {
                Write-IISLog "IIS is available and accessible" -Level "SUCCESS" -Component "INIT"
            }
        }
        catch {
            Write-IISLog "Warning: IIS may not be fully accessible: $_" -Level "WARNING" -Component "INIT"
        }
    }
    catch {
        Write-IISLog "Failed to initialize IIS modules: $_" -Level "ERROR" -Component "INIT"
        Write-IISLog "Please ensure IIS Management Console is installed" -Level "ERROR" -Component "INIT"
        return $false
    }

    return $true
}

# ---------- IIS APPLICATION MONITORING FUNCTIONS ----------
function Test-IISApplicationHealth {
    param(
        [string]$SiteName,
        [string]$ApplicationPath,
        [string]$HealthCheckURL,
        [string]$ExpectedResponse
    )

    # Check if custom health check exists
    $CustomKey = "$SiteName$ApplicationPath"
    if ($CustomHealthChecks.ContainsKey($CustomKey)) {
        try {
            Write-IISLog "Using custom health check for $CustomKey" -Level "DEBUG" -Component "HEALTH"
            $Result = & $CustomHealthChecks[$CustomKey]
            return $Result
        }
        catch {
            Write-IISLog "Custom health check failed for $CustomKey: $_" -Level "WARNING" -Component "HEALTH"
            return $false
        }
    }

    # If no health check URL defined, assume healthy
    if (-not $HealthCheckURL -or $HealthCheckURL -eq "") {
        Write-IISLog "No health check URL defined for $SiteName$ApplicationPath" -Level "DEBUG" -Component "HEALTH"
        return $true
    }

    try {
        Write-IISLog "Checking health at: $HealthCheckURL" -Level "DEBUG" -Component "HEALTH"

        $WebRequestParams = @{
            Uri = $HealthCheckURL
            UseBasicParsing = $true
            TimeoutSec = 10
            ErrorAction = 'Stop'
        }

        $Response = Invoke-WebRequest @WebRequestParams

        # Check status code
        if ($ExpectedResponse -and $ExpectedResponse -ne "") {
            # Check if expected response is a status code or text
            if ($ExpectedResponse -match '^\d+$') {
                # It's a status code
                $StatusCode = [int]$ExpectedResponse
                if ($Response.StatusCode -eq $StatusCode) {
                    Write-IISLog "Health check passed (Status: $($Response.StatusCode))" -Level "DEBUG" -Component "HEALTH"
                    return $true
                }
                else {
                    Write-IISLog "Health check failed (Expected: $StatusCode, Got: $($Response.StatusCode))" -Level "WARNING" -Component "HEALTH"
                    return $false
                }
            }
            else {
                # It's text to match
                if ($Response.Content -match $ExpectedResponse) {
                    Write-IISLog "Health check passed (Content matches)" -Level "DEBUG" -Component "HEALTH"
                    return $true
                }
                else {
                    Write-IISLog "Health check failed (Content doesn't match expected)" -Level "WARNING" -Component "HEALTH"
                    return $false
                }
            }
        }
        else {
            # Just check if status code is 200
            if ($Response.StatusCode -eq 200) {
                Write-IISLog "Health check passed (HTTP 200 OK)" -Level "DEBUG" -Component "HEALTH"
                return $true
            }
            else {
                Write-IISLog "Health check failed (HTTP $($Response.StatusCode))" -Level "WARNING" -Component "HEALTH"
                return $false
            }
        }
    }
    catch {
        Write-IISLog "Health check failed: $_" -Level "WARNING" -Component "HEALTH"
        return $false
    }
}

function Get-IISApplicationStatus {
    param(
        [string]$SiteName,
        [string]$ApplicationPath
    )

    $Status = @{
        SiteName = $SiteName
        ApplicationPath = $ApplicationPath
        AppPoolName = $null
        AppPoolStatus = "Unknown"
        SiteStatus = "Unknown"
        ApplicationStatus = "Unknown"
        IsHealthy = $false
        Details = @{}
    }

    try {
        # Get site information
        $Site = Get-IISSite -Name $SiteName -ErrorAction SilentlyContinue
        if ($Site) {
            $Status.SiteStatus = "Running"
            $Status.Details.Site = $Site

            # Find the application
            $App = $Site.Applications | Where-Object { $_.Path -eq $ApplicationPath } | Select-Object -First 1
            if ($App) {
                $Status.ApplicationStatus = "Running"
                $Status.AppPoolName = $App.ApplicationPool

                # Get application pool status
                $AppPool = Get-IISAppPool -Name $App.ApplicationPool -ErrorAction SilentlyContinue
                if ($AppPool) {
                    $Status.AppPoolStatus = $AppPool.State
                    $Status.Details.AppPool = $AppPool

                    if ($AppPool.State -eq "Started") {
                        $Status.IsHealthy = $true
                    }
                    else {
                        $Status.IsHealthy = $false
                    }
                }
                else {
                    $Status.AppPoolStatus = "NotFound"
                    $Status.IsHealthy = $false
                }
            }
            else {
                $Status.ApplicationStatus = "NotFound"
                $Status.IsHealthy = $false
            }
        }
        else {
            $Status.SiteStatus = "NotFound"
            $Status.IsHealthy = $false
        }
    }
    catch {
        $Status.IsHealthy = $false
        $Status.Details.Error = $_.Exception.Message
        Write-IISLog "Error checking status for $SiteName$ApplicationPath: $_" -Level "ERROR" -Component "MONITOR"
    }

    return $Status
}

# ---------- IIS RESTART FUNCTIONS ----------
function Restart-IISApplication {
    param(
        [string]$SiteName,
        [string]$ApplicationPath,
        [string]$RestartMethod,
        [hashtable]$CurrentStatus
    )

    $Result = @{
        Success = $false
        Action = ""
        Details = @{}
        NewStatus = $null
    }

    try {
        Write-IISLog "========================================" -Level "INFO" -Component "RESTART"
        Write-IISLog "Attempting to restart $SiteName$ApplicationPath" -Level "INFO" -Component "RESTART"
        Write-IISLog "Method: $RestartMethod" -Level "INFO" -Component "RESTART"

        $AppPoolName = $CurrentStatus.AppPoolName
        $AppPool = Get-IISAppPool -Name $AppPoolName -ErrorAction SilentlyContinue

        switch ($RestartMethod) {
            "AppPool" {
                # Restart only the application pool
                $Result.Action = "Restart AppPool: $AppPoolName"
                Write-IISLog "Restarting application pool: $AppPoolName" -Level "INFO" -Component "RESTART"

                if ($UseRecycling) {
                    # Use recycling (graceful restart)
                    if ($AppPool) {
                        $AppPool.Recycle()
                        Write-IISLog "Application pool recycled gracefully" -Level "INFO" -Component "RESTART"
                        $Result.Success = $true
                    }
                    else {
                        throw "Application pool not found: $AppPoolName"
                    }
                }
                else {
                    # Stop and start (hard restart)
                    Stop-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool stopped" -Level "INFO" -Component "RESTART"
                    Start-Sleep -Seconds 3
                    Start-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool started" -Level "INFO" -Component "RESTART"
                    $Result.Success = $true
                }
            }
            "ApplicationPool" {
                # Same as AppPool
                $Result.Action = "Restart Application Pool: $AppPoolName"
                Write-IISLog "Restarting application pool: $AppPoolName" -Level "INFO" -Component "RESTART"

                if ($UseRecycling) {
                    if ($AppPool) {
                        $AppPool.Recycle()
                        Write-IISLog "Application pool recycled gracefully" -Level "INFO" -Component "RESTART"
                        $Result.Success = $true
                    }
                    else {
                        throw "Application pool not found: $AppPoolName"
                    }
                }
                else {
                    Stop-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool stopped" -Level "INFO" -Component "RESTART"
                    Start-Sleep -Seconds 3
                    Start-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool started" -Level "INFO" -Component "RESTART"
                    $Result.Success = $true
                }
            }
            "Site" {
                # Restart the entire site
                $Result.Action = "Restart Site: $SiteName"
                Write-IISLog "Restarting site: $SiteName" -Level "INFO" -Component "RESTART"

                Stop-IISSite -Name $SiteName -ErrorAction Stop
                Write-IISLog "Site stopped" -Level "INFO" -Component "RESTART"
                Start-Sleep -Seconds 3
                Start-IISSite -Name $SiteName -ErrorAction Stop
                Write-IISLog "Site started" -Level "INFO" -Component "RESTART"
                $Result.Success = $true
            }
            "All" {
                # Restart everything
                $Result.Action = "Restart All: Site $SiteName, AppPool $AppPoolName"
                Write-IISLog "Restarting all: Site $SiteName, AppPool $AppPoolName" -Level "INFO" -Component "RESTART"

                Stop-IISSite -Name $SiteName -ErrorAction Stop
                Write-IISLog "Site stopped" -Level "INFO" -Component "RESTART"
                Start-Sleep -Seconds 2

                if ($UseRecycling) {
                    if ($AppPool) {
                        $AppPool.Recycle()
                        Write-IISLog "Application pool recycled" -Level "INFO" -Component "RESTART"
                    }
                }
                else {
                    Stop-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool stopped" -Level "INFO" -Component "RESTART"
                    Start-Sleep -Seconds 2
                    Start-IISAppPool -Name $AppPoolName -ErrorAction Stop
                    Write-IISLog "Application pool started" -Level "INFO" -Component "RESTART"
                }

                Start-Sleep -Seconds 2
                Start-IISSite -Name $SiteName -ErrorAction Stop
                Write-IISLog "Site started" -Level "INFO" -Component "RESTART"
                $Result.Success = $true
            }
            default {
                throw "Unknown restart method: $RestartMethod"
            }
        }

        # Verify restart was successful
        if ($Result.Success) {
            Write-IISLog "Waiting $PostRestartWaitTime seconds for stabilization..." -Level "INFO" -Component "RESTART"
            Start-Sleep -Seconds $PostRestartWaitTime

            # Check new status
            $Result.NewStatus = Get-IISApplicationStatus -SiteName $SiteName -ApplicationPath $ApplicationPath

            # Perform health check
            $AppConfig = Get-AppConfig -SiteName $SiteName -ApplicationPath $ApplicationPath -AppDefinitions $global:AppDefinitions
            if ($AppConfig -and $AppConfig.HealthCheckURL) {
                Write-IISLog "Performing health check after restart..." -Level "INFO" -Component "RESTART"
                $HealthCheckPassed = $false

                for ($i = 1; $i -le $HealthCheckRetries; $i++) {
                    if ($i -gt 1) {
                        Start-Sleep -Seconds $HealthCheckRetryInterval
                    }

                    if (Test-IISApplicationHealth -SiteName $SiteName -ApplicationPath $ApplicationPath -HealthCheckURL $AppConfig.HealthCheckURL -ExpectedResponse $AppConfig.ExpectedResponse) {
                        $HealthCheckPassed = $true
                        Write-IISLog "Health check passed after $i attempt(s)" -Level "SUCCESS" -Component "RESTART"
                        break
                    }
                    else {
                        Write-IISLog "Health check attempt $i of $HealthCheckRetries failed" -Level "WARNING" -Component "RESTART"
                    }
                }

                if (-not $HealthCheckPassed) {
                    Write-IISLog "Health check failed after $HealthCheckRetries attempts" -Level "ERROR" -Component "RESTART"
                    $Result.Success = $false
                    $Result.Details.HealthCheckFailed = $true
                }
            }

            if ($Result.Success) {
                Write-IISLog "Successfully restarted $SiteName$ApplicationPath" -Level "SUCCESS" -Component "RESTART"
            }
        }
        else {
            Write-IISLog "Failed to restart $SiteName$ApplicationPath" -Level "ERROR" -Component "RESTART"
        }
    }
    catch {
        $Result.Success = $false
        $Result.Details.Error = $_.Exception.Message
        Write-IISLog "Error restarting $SiteName$ApplicationPath: $_" -Level "ERROR" -Component "RESTART"

        # Try IIS Reset as fallback
        if ($EnableIISResetFallback) {
            Write-IISLog "Attempting IIS Reset as fallback..." -Level "WARNING" -Component "RESTART"
            try {
                iisreset /restart
                Write-IISLog "IIS Reset completed" -Level "INFO" -Component "RESTART"
                Start-Sleep -Seconds 10
                $Result.Success = $true
                $Result.Details.FallbackUsed = $true
            }
            catch {
                Write-IISLog "IIS Reset failed: $_" -Level "ERROR" -Component "RESTART"
            }
        }
    }

    Write-IISLog "========================================" -Level "INFO" -Component "RESTART"
    return $Result
}

# ---------- STATE TRACKING FUNCTIONS ----------
$AppState = @{}
$RestartHistory = @{}

function Update-AppState {
    param(
        [string]$AppKey,
        [hashtable]$Status,
        [bool]$IsRestarting = $false
    )

    $State = @{
        LastCheck = Get-Date
        CurrentStatus = $Status
        IsRestarting = $IsRestarting
        LastRestart = $null
        RestartCount = 0
        ConsecutiveFailures = 0
    }

    if ($AppState.ContainsKey($AppKey)) {
        $State.RestartCount = $AppState[$AppKey].RestartCount
        $State.ConsecutiveFailures = $AppState[$AppKey].ConsecutiveFailures
        $State.LastRestart = $AppState[$AppKey].LastRestart
    }

    $AppState[$AppKey] = $State
}

function Update-RestartCount {
    param([string]$AppKey)

    if (-not $AppState.ContainsKey($AppKey)) {
        return
    }

    $AppState[$AppKey].RestartCount++
    $AppState[$AppKey].LastRestart = Get-Date
    $AppState[$AppKey].ConsecutiveFailures = 0
}

function Update-FailureCount {
    param(
        [string]$AppKey,
        [bool]$Increment = $true
    )

    if (-not $AppState.ContainsKey($AppKey)) {
        return
    }

    if ($Increment) {
        $AppState[$AppKey].ConsecutiveFailures++
    }
    else {
        $AppState[$AppKey].ConsecutiveFailures = 0
    }
}

function Get-RestartCountToday {
    param([string]$AppKey)

    if (-not $AppState.ContainsKey($AppKey)) {
        return 0
    }

    return $AppState[$AppKey].RestartCount
}

function Save-RestartHistory {
    param(
        [string]$AppKey,
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
        $FilePath = Join-Path $PerformanceDataPath "Restarts_$Date.csv"

        $Record = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            AppKey = $AppKey
            Success = $Result.Success
            Action = $Result.Action
            Error = $Result.Details.Error
            HealthCheckFailed = $Result.Details.HealthCheckFailed
            FallbackUsed = $Result.Details.FallbackUsed
        }

        if (Test-Path $FilePath) {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation
        }

        # Add to history cache
        if (-not $RestartHistory.ContainsKey($AppKey)) {
            $RestartHistory[$AppKey] = @()
        }
        $RestartHistory[$AppKey] += $Record

        # Clean up old history (keep last 1000 records per app)
        if ($RestartHistory[$AppKey].Count -gt 1000) {
            $RestartHistory[$AppKey] = $RestartHistory[$AppKey] | Select-Object -Last 1000
        }
    }
    catch {
        Write-IISLog "Failed to save restart history: $_" -Level "WARNING" -Component "PERF"
    }
}

# ---------- NOTIFICATION FUNCTIONS ----------
function Send-EmailNotification {
    param(
        [hashtable]$AppConfig,
        [hashtable]$Status,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Reason
    )

    if (-not $EmailConfig.Enabled) {
        return $false
    }

    try {
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $AppKey = "$($AppConfig.SiteName)$($AppConfig.ApplicationPath)"
        $RestartCount = Get-RestartCountToday -AppKey $AppKey

        $Body = $EmailNotificationTemplate
        $Body = $Body.Replace('{Timestamp}', $Timestamp)
        $Body = $Body.Replace('{SiteName}', $AppConfig.SiteName)
        $Body = $Body.Replace('{ApplicationPath}', $AppConfig.ApplicationPath)
        $Body = $Body.Replace('{Severity}', $Severity)
        $Body = $Body.Replace('{Action}', $Result.Action)
        $Body = $Body.Replace('{Result}', if ($Result.Success) { "✅ SUCCESS" } else { "❌ FAILED" })
        $Body = $Body.Replace('{Reason}', $Reason)
        $Body = $Body.Replace('{RestartCount}', $RestartCount)
        $Body = $Body.Replace('{CheckInterval}', $AppConfig.CheckInterval)
        $Body = $Body.Replace('{HealthCheckURL}', if ($AppConfig.HealthCheckURL) { $AppConfig.HealthCheckURL } else { "Not configured" })
        $Body = $Body.Replace('{ExpectedResponse}', if ($AppConfig.ExpectedResponse) { $AppConfig.ExpectedResponse } else { "Not configured" })
        $Body = $Body.Replace('{MaxRestarts}', $AppConfig.MaxRestarts)
        $Body = $Body.Replace('{LogPath}', $LogPath)

        # Send email
        $MailParams = @{
            To = $EmailConfig.To
            From = $EmailConfig.From
            Subject = "[$Severity] IIS Self-Healing: $($AppConfig.SiteName)$($AppConfig.ApplicationPath)"
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
        Write-IISLog "Email notification sent" -Level "INFO" -Component "NOTIFY"
        return $true
    }
    catch {
        Write-IISLog "Failed to send email notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}