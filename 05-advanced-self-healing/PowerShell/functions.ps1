# ============================================================
# ADVANCED SELF-HEALING - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for database monitoring,
# actions, and notifications.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-SelfHealingLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "SELF-HEALING"
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
            $LogFile = Join-Path $LogPath "SelfHealing_$(Get-Date -Format 'yyyyMMdd').log"
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
            Write-SelfHealingLog "Credential '$CredentialName' not found" -Level "WARNING" -Component "CREDENTIALS"
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
        Write-SelfHealingLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

function Resolve-ConnectionString {
    param(
        [string]$ConnectionString,
        [string]$DatabaseType
    )

    # Get credentials from Credential Manager
    $CredentialName = $CredentialManagerEntries[$DatabaseType]
    if (-not $CredentialName) {
        Write-SelfHealingLog "No credential entry found for database type: $DatabaseType" -Level "ERROR" -Component "CREDENTIALS"
        return $ConnectionString
    }

    $Cred = Get-StoredCredential -CredentialName $CredentialName
    if (-not $Cred) {
        Write-SelfHealingLog "Failed to retrieve credentials for: $CredentialName" -Level "ERROR" -Component "CREDENTIALS"
        return $ConnectionString
    }

    # Replace placeholders
    $ResolvedString = $ConnectionString
    $ResolvedString = $ResolvedString -replace '{USER}', $Cred.UserName
    $ResolvedString = $ResolvedString -replace '{PASSWORD}', $Cred.GetNetworkCredential().Password
    $ResolvedString = $ResolvedString -replace '{PWD}', $Cred.GetNetworkCredential().Password

    return $ResolvedString
}

# ---------- DATABASE CONNECTION FUNCTIONS ----------
function Test-DatabaseConnection {
    param(
        [string]$DatabaseType,
        [string]$ConnectionString
    )

    try {
        Write-SelfHealingLog "Testing connection to $DatabaseType database..." -Level "DEBUG" -Component "DB"

        $ResolvedString = Resolve-ConnectionString -ConnectionString $ConnectionString -DatabaseType $DatabaseType

        switch ($DatabaseType) {
            "Oracle" {
                Add-Type -AssemblyName "System.Data.OracleClient" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.OracleClient.OracleConnection($ResolvedString)
            }
            "SQLServer" {
                Add-Type -AssemblyName "System.Data.SqlClient" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.SqlClient.SqlConnection($ResolvedString)
            }
            "MySQL" {
                Add-Type -AssemblyName "MySql.Data" -ErrorAction SilentlyContinue
                $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection($ResolvedString)
            }
            "PostgreSQL" {
                Add-Type -AssemblyName "Npgsql" -ErrorAction SilentlyContinue
                $Connection = New-Object Npgsql.NpgsqlConnection($ResolvedString)
            }
            "SQLite" {
                Add-Type -AssemblyName "System.Data.SQLite" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.SQLite.SQLiteConnection($ResolvedString)
            }
            default {
                throw "Unsupported database type: $DatabaseType"
            }
        }

        $Connection.Open()
        $Connection.Close()

        Write-SelfHealingLog "Database connection successful" -Level "SUCCESS" -Component "DB"
        return $true
    }
    catch {
        Write-SelfHealingLog "Database connection failed: $_" -Level "ERROR" -Component "DB"
        return $false
    }
}

function Invoke-DatabaseQuery {
    param(
        [string]$DatabaseType,
        [string]$ConnectionString,
        [string]$Query,
        [int]$Timeout = 30
    )

    $Result = @{
        Success = $false
        Count = 0
        Data = $null
        Error = $null
    }

    try {
        $ResolvedString = Resolve-ConnectionString -ConnectionString $ConnectionString -DatabaseType $DatabaseType

        Write-SelfHealingLog "Executing query on $DatabaseType: $Query" -Level "DEBUG" -Component "DB"

        switch ($DatabaseType) {
            "Oracle" {
                Add-Type -AssemblyName "System.Data.OracleClient" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.OracleClient.OracleConnection($ResolvedString)
                $Command = New-Object System.Data.OracleClient.OracleCommand($Query, $Connection)
                $Command.CommandTimeout = $Timeout
            }
            "SQLServer" {
                Add-Type -AssemblyName "System.Data.SqlClient" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.SqlClient.SqlConnection($ResolvedString)
                $Command = New-Object System.Data.SqlClient.SqlCommand($Query, $Connection)
                $Command.CommandTimeout = $Timeout
            }
            "MySQL" {
                Add-Type -AssemblyName "MySql.Data" -ErrorAction SilentlyContinue
                $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection($ResolvedString)
                $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query, $Connection)
                $Command.CommandTimeout = $Timeout
            }
            "PostgreSQL" {
                Add-Type -AssemblyName "Npgsql" -ErrorAction SilentlyContinue
                $Connection = New-Object Npgsql.NpgsqlConnection($ResolvedString)
                $Command = New-Object Npgsql.NpgsqlCommand($Query, $Connection)
                $Command.CommandTimeout = $Timeout
            }
            "SQLite" {
                Add-Type -AssemblyName "System.Data.SQLite" -ErrorAction SilentlyContinue
                $Connection = New-Object System.Data.SQLite.SQLiteConnection($ResolvedString)
                $Command = New-Object System.Data.SQLite.SQLiteCommand($Query, $Connection)
                $Command.CommandTimeout = $Timeout
            }
            default {
                throw "Unsupported database type: $DatabaseType"
            }
        }

        $Connection.Open()
        $Result.Count = $Command.ExecuteScalar()
        $Connection.Close()

        if ($Result.Count -is [DBNull]) {
            $Result.Count = 0
        }

        $Result.Success = $true
        Write-SelfHealingLog "Query returned $($Result.Count) rows" -Level "DEBUG" -Component "DB"
    }
    catch {
        $Result.Success = $false
        $Result.Error = $_.Exception.Message
        Write-SelfHealingLog "Query failed: $_" -Level "ERROR" -Component "DB"
    }

    return $Result
}

# ---------- MONITOR LOADING FUNCTIONS ----------
function Load-MonitorDefinitions {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-SelfHealingLog "Monitor definitions file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Monitors = Import-Csv -Path $FilePath | Where-Object {
        $_.MonitorName -and $_.MonitorName -notmatch '^#'
    }

    Write-SelfHealingLog "Loaded $($Monitors.Count) monitor definitions from $FilePath" -Level "INFO" -Component "CONFIG"

    # Validate monitors
    $EnabledMonitors = $Monitors | Where-Object { $_.Enabled -eq 'true' -or $_.Enabled -eq 'TRUE' }
    Write-SelfHealingLog "$($EnabledMonitors.Count) monitors are enabled" -Level "INFO" -Component "CONFIG"

    return $EnabledMonitors
}

function Get-MonitorConfig {
    param(
        [string]$MonitorName,
        [array]$MonitorDefinitions
    )

    return $MonitorDefinitions | Where-Object { $_.MonitorName -eq $MonitorName } | Select-Object -First 1
}

# ---------- CONDITION EVALUATION FUNCTIONS ----------
function Evaluate-Condition {
    param(
        [int]$CurrentCount,
        [int]$Threshold,
        [string]$Operator
    )

    switch ($Operator) {
        "GreaterThan" { return $CurrentCount -gt $Threshold }
        "GreaterThanOrEqual" { return $CurrentCount -ge $Threshold }
        "LessThan" { return $CurrentCount -lt $Threshold }
        "LessThanOrEqual" { return $CurrentCount -le $Threshold }
        "Equal" { return $CurrentCount -eq $Threshold }
        "NotEqual" { return $CurrentCount -ne $Threshold }
        "Contains" { return $CurrentCount -gt 0 }  # For text contains
        default {
            Write-SelfHealingLog "Unknown operator: $Operator" -Level "ERROR" -Component "CONDITION"
            return $false
        }
    }
}

# ---------- ACTION EXECUTION FUNCTIONS ----------
function Execute-Action {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount,
        [string]$AlertKey
    )

    $Result = @{
        Success = $false
        ActionType = $Monitor.ActionType
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        Write-SelfHealingLog "Executing action: $($Monitor.ActionType) for monitor: $($Monitor.MonitorName)" -Level "INFO" -Component "ACTION"

        # Check action throttling
        if ($EnableActionThrottling) {
            $ActionCount = Get-ActionCountLastHour -MonitorName $Monitor.MonitorName
            if ($ActionCount -ge $MaxActionsPerHour) {
                Write-SelfHealingLog "Action throttling: Max actions per hour reached ($MaxActionsPerHour) for $($Monitor.MonitorName)" -Level "WARNING" -Component "ACTION"
                $Result.Message = "Action throttled: Max actions per hour reached"
                return $Result
            }
        }

        switch ($Monitor.ActionType) {
            "RestartIIS" {
                $Result = Execute-RestartIIS -Monitor $Monitor -CurrentCount $CurrentCount
            }
            "EmailAlert" {
                $Result = Execute-EmailAlert -Monitor $Monitor -CurrentCount $CurrentCount
            }
            "TeamsAlert" {
                $Result = Execute-TeamsAlert -Monitor $Monitor -CurrentCount $CurrentCount
            }
            "SlackAlert" {
                $Result = Execute-SlackAlert -Monitor $Monitor -CurrentCount $CurrentCount
            }
            "ExecuteScript" {
                $Result = Execute-CustomScript -Monitor $Monitor -CurrentCount $CurrentCount
            }
            "ExecuteSQL" {
                $Result = Execute-SQLScript -Monitor $Monitor -CurrentCount $CurrentCount
            }
            default {
                Write-SelfHealingLog "Unknown action type: $($Monitor.ActionType)" -Level "ERROR" -Component "ACTION"
                $Result.Message = "Unknown action type"
            }
        }

        # Record action in performance tracking
        if ($EnablePerformanceTracking) {
            Save-ActionHistory -Monitor $Monitor -CurrentCount $CurrentCount -Result $Result
        }

        Write-SelfHealingLog "Action execution completed with result: $($Result.Success)" -Level "INFO" -Component "ACTION"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "Action execution failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-RestartIIS {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "RestartIIS"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        $Target = $Monitor.ActionTarget
        $Parameters = $Monitor.ActionParameters

        # Parse target: SiteName/ApplicationPath or SiteName
        $Parts = $Target -split '/'
        $SiteName = $Parts[0]
        $ApplicationPath = if ($Parts.Count -gt 1) { "/$($Parts[1])" } else { "/" }

        Write-SelfHealingLog "Restarting IIS: Site=$SiteName, AppPath=$ApplicationPath" -Level "INFO" -Component "ACTION"

        # Import IIS module
        Import-Module WebAdministration -ErrorAction Stop

        # Determine restart method
        $RestartMethod = if ($Parameters -match "Recycle") { "Recycle" } else { $IISRestartMethod }

        switch ($RestartMethod) {
            "Recycle" {
                # Get application pool
                $AppPool = Get-WebApplication -Site $SiteName -Path $ApplicationPath | Select-Object -ExpandProperty ApplicationPool
                if ($AppPool) {
                    Write-SelfHealingLog "Recycling application pool: $AppPool" -Level "INFO" -Component "ACTION"
                    $Pool = Get-IISAppPool -Name $AppPool
                    if ($Pool) {
                        $Pool.Recycle()
                        $Result.Success = $true
                        $Result.Message = "Application pool recycled successfully"
                        $Result.Details.AppPool = $AppPool
                    }
                    else {
                        throw "Application pool not found: $AppPool"
                    }
                }
                else {
                    throw "Application not found: $SiteName$ApplicationPath"
                }
            }
            "StopStart" {
                # Stop and start application pool
                $AppPool = Get-WebApplication -Site $SiteName -Path $ApplicationPath | Select-Object -ExpandProperty ApplicationPool
                if ($AppPool) {
                    Write-SelfHealingLog "Stopping application pool: $AppPool" -Level "INFO" -Component "ACTION"
                    Stop-IISAppPool -Name $AppPool -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    Write-SelfHealingLog "Starting application pool: $AppPool" -Level "INFO" -Component "ACTION"
                    Start-IISAppPool -Name $AppPool -ErrorAction Stop
                    $Result.Success = $true
                    $Result.Message = "Application pool restarted successfully"
                    $Result.Details.AppPool = $AppPool
                }
                else {
                    throw "Application not found: $SiteName$ApplicationPath"
                }
            }
            "SiteRestart" {
                Write-SelfHealingLog "Restarting site: $SiteName" -Level "INFO" -Component "ACTION"
                Stop-IISSite -Name $SiteName -ErrorAction Stop
                Start-Sleep -Seconds 3
                Start-IISSite -Name $SiteName -ErrorAction Stop
                $Result.Success = $true
                $Result.Message = "Site restarted successfully"
                $Result.Details.Site = $SiteName
            }
            default {
                throw "Unknown restart method: $RestartMethod"
            }
        }

        # Wait for stabilization
        Write-SelfHealingLog "Waiting $IISPostRestartWait seconds for stabilization..." -Level "INFO" -Component "ACTION"
        Start-Sleep -Seconds $IISPostRestartWait

        # Perform health check if URL specified
        # (Health check would need to be configured separately)
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "IIS restart failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-EmailAlert {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "EmailAlert"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        if (-not $EmailConfig.Enabled) {
            throw "Email notifications are disabled"
        }

        $To = $Monitor.ActionTarget
        if (-not $To -or $To -eq "") {
            $To = $EmailConfig.DefaultTo
        }

        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName

        # Build email body
        $Body = $EmailAlertTemplate
        $Body = $Body.Replace('{Timestamp}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        $Body = $Body.Replace('{MonitorName}', $Monitor.MonitorName)
        $Body = $Body.Replace('{Severity}', $Monitor.Severity)
        $Body = $Body.Replace('{Condition}', $Monitor.QueryCondition)
        $Body = $Body.Replace('{CurrentCount}', $CurrentCount)
        $Body = $Body.Replace('{ThresholdCount}', $Monitor.ThresholdCount)
        $Body = $Body.Replace('{TimeWindowSeconds}', $Monitor.TimeWindowSeconds)
        $Body = $Body.Replace('{Action}', $Monitor.ActionType)
        $Body = $Body.Replace('{ActionResult}', "Pending")
        $Body = $Body.Replace('{DatabaseType}', $Monitor.DatabaseType)
        $Body = $Body.Replace('{TableName}', $Monitor.TableName)
        $Body = $Body.Replace('{CheckInterval}', $Monitor.CheckInterval)
        $Body = $Body.Replace('{ActionType}', $Monitor.ActionType)
        $Body = $Body.Replace('{ActionTarget}', $Monitor.ActionTarget)
        $Body = $Body.Replace('{QueryCondition}', $Monitor.QueryCondition)
        $Body = $Body.Replace('{LogPath}', $LogPath)

        $Subject = "[$($Monitor.Severity)] Self-Healing Alert: $($Monitor.MonitorName)"

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
        $Result.Success = $true
        $Result.Message = "Email sent successfully"
        $Result.Details.To = $To

        Write-SelfHealingLog "Email alert sent to: $To" -Level "SUCCESS" -Component "ACTION"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "Email alert failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-TeamsAlert {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "TeamsAlert"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        if (-not $TeamsConfig.Enabled) {
            throw "Teams notifications are disabled"
        }

        $WebhookURL = $Monitor.ActionTarget
        if (-not $WebhookURL -or $WebhookURL -eq "") {
            $WebhookURL = $TeamsConfig.DefaultWebhookURL
        }

        $ThemeColor = @{
            'CRITICAL' = 'FF0000'
            'WARNING' = 'FFA500'
            'INFO' = '0000FF'
            'SUCCESS' = '00FF00'
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $Payload = $TeamsAlertTemplate
        $Payload = $Payload.Replace('{ThemeColor}', $ThemeColor[$Monitor.Severity])
        $Payload = $Payload.Replace('{Summary}', "$($Monitor.Severity): $($Monitor.MonitorName)")
        $Payload = $Payload.Replace('{ActivityTitle}', "**$($Monitor.Severity) Alert: $($Monitor.MonitorName)**")
        $Payload = $Payload.Replace('{MonitorName}', $Monitor.MonitorName)
        $Payload = $Payload.Replace('{Severity}', $Monitor.Severity)
        $Payload = $Payload.Replace('{Condition}', $Monitor.QueryCondition)
        $Payload = $Payload.Replace('{CurrentCount}', $CurrentCount)
        $Payload = $Payload.Replace('{ThresholdCount}', $Monitor.ThresholdCount)
        $Payload = $Payload.Replace('{TimeWindowSeconds}', $Monitor.TimeWindowSeconds)
        $Payload = $Payload.Replace('{Action}', $Monitor.ActionType)
        $Payload = $Payload.Replace('{ActionResult}', "Pending")
        $Payload = $Payload.Replace('{DatabaseType}', $Monitor.DatabaseType)
        $Payload = $Payload.Replace('{TableName}', $Monitor.TableName)
        $Payload = $Payload.Replace('{Timestamp}', $Timestamp)
        $Payload = $Payload.Replace('{LogPath}', $LogPath)

        $Params = @{
            Uri = $WebhookURL
            Method = 'Post'
            Body = $Payload
            ContentType = 'application/json'
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        Invoke-RestMethod @Params
        $Result.Success = $true
        $Result.Message = "Teams message sent successfully"
        $Result.Details.WebhookURL = $WebhookURL

        Write-SelfHealingLog "Teams alert sent to: $WebhookURL" -Level "SUCCESS" -Component "ACTION"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "Teams alert failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-SlackAlert {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "SlackAlert"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        if (-not $SlackConfig.Enabled) {
            throw "Slack notifications are disabled"
        }

        $WebhookURL = $Monitor.ActionTarget
        if (-not $WebhookURL -or $WebhookURL -eq "") {
            $WebhookURL = $SlackConfig.DefaultWebhookURL
        }

        $ColorMap = @{
            'CRITICAL' = 'danger'
            'WARNING' = 'warning'
            'INFO' = 'good'
            'SUCCESS' = 'good'
        }

        $Timestamp = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))

        $Payload = $SlackAlertTemplate
        $Payload = $Payload.Replace('{Channel}', $SlackConfig.DefaultChannel)
        $Payload = $Payload.Replace('{Username}', $SlackConfig.Username)
        $Payload = $Payload.Replace('{IconEmoji}', $SlackConfig.IconEmoji)
        $Payload = $Payload.Replace('{Color}', $ColorMap[$Monitor.Severity])
        $Payload = $Payload.Replace('{Title}', "$($Monitor.Severity): $($Monitor.MonitorName)")
        $Payload = $Payload.Replace('{MonitorName}', $Monitor.MonitorName)
        $Payload = $Payload.Replace('{Severity}', $Monitor.Severity)
        $Payload = $Payload.Replace('{Condition}', $Monitor.QueryCondition)
        $Payload = $Payload.Replace('{CurrentCount}', $CurrentCount)
        $Payload = $Payload.Replace('{ThresholdCount}', $Monitor.ThresholdCount)
        $Payload = $Payload.Replace('{TimeWindowSeconds}', $Monitor.TimeWindowSeconds)
        $Payload = $Payload.Replace('{Action}', $Monitor.ActionType)
        $Payload = $Payload.Replace('{ActionResult}', "Pending")
        $Payload = $Payload.Replace('{DatabaseType}', $Monitor.DatabaseType)
        $Payload = $Payload.Replace('{TableName}', $Monitor.TableName)
        $Payload = $Payload.Replace('{Timestamp}', $Timestamp)
        $Payload = $Payload.Replace('{LogPath}', $LogPath)

        $Params = @{
            Uri = $WebhookURL
            Method = 'Post'
            Body = $Payload
            ContentType = 'application/json'
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        Invoke-RestMethod @Params
        $Result.Success = $true
        $Result.Message = "Slack message sent successfully"
        $Result.Details.WebhookURL = $WebhookURL

        Write-SelfHealingLog "Slack alert sent to: $WebhookURL" -Level "SUCCESS" -Component "ACTION"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "Slack alert failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-CustomScript {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "ExecuteScript"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        $ScriptName = $Monitor.ActionTarget
        $Parameters = $Monitor.ActionParameters

        if (-not $CustomActionScripts.ContainsKey($ScriptName)) {
            throw "Custom script not found: $ScriptName"
        }

        Write-SelfHealingLog "Executing custom script: $ScriptName" -Level "INFO" -Component "ACTION"

        $ScriptBlock = $CustomActionScripts[$ScriptName]
        $ScriptResult = & $ScriptBlock -Parameters $Parameters

        $Result.Success = $true
        $Result.Message = "Custom script executed successfully"
        $Result.Details.ScriptName = $ScriptName
        $Result.Details.ScriptResult = $ScriptResult

        Write-SelfHealingLog "Custom script completed: $ScriptName" -Level "SUCCESS" -Component "ACTION"
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "Custom script failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

function Execute-SQLScript {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount
    )

    $Result = @{
        Success = $false
        ActionType = "ExecuteSQL"
        ActionTarget = $Monitor.ActionTarget
        Message = ""
        Details = @{}
    }

    try {
        $SQLScript = $Monitor.ActionTarget

        Write-SelfHealingLog "Executing SQL script: $SQLScript" -Level "INFO" -Component "ACTION"

        # Execute SQL script on the same database
        $QueryResult = Invoke-DatabaseQuery -DatabaseType $Monitor.DatabaseType -ConnectionString $Monitor.ConnectionString -Query $SQLScript -Timeout $DBQueryTimeout

        if ($QueryResult.Success) {
            $Result.Success = $true
            $Result.Message = "SQL script executed successfully"
            $Result.Details.RowsAffected = $QueryResult.Count
            Write-SelfHealingLog "SQL script completed: $SQLScript" -Level "SUCCESS" -Component "ACTION"
        }
        else {
            throw "SQL script failed: $($QueryResult.Error)"
        }
    }
    catch {
        $Result.Success = $false
        $Result.Message = $_.Exception.Message
        Write-SelfHealingLog "SQL script failed: $_" -Level "ERROR" -Component "ACTION"
    }

    return $Result
}

# ---------- STATE TRACKING FUNCTIONS ----------
$MonitorState = @{}
$AlertState = @{}
$ActionHistory = @{}

function Update-MonitorState {
    param(
        [string]$MonitorName,
        [int]$CurrentCount,
        [bool]$IsAlerting = $false
    )

    $State = @{
        LastCheck = Get-Date
        CurrentCount = $CurrentCount
        IsAlerting = $IsAlerting
        ConsecutiveFailures = 0
    }

    if ($MonitorState.ContainsKey($MonitorName)) {
        $State.ConsecutiveFailures = $MonitorState[$MonitorName].ConsecutiveFailures
        if ($IsAlerting) {
            $State.ConsecutiveFailures = 0
        }
        else {
            $State.ConsecutiveFailures = $MonitorState[$MonitorName].ConsecutiveFailures + 1
        }
    }

    $MonitorState[$MonitorName] = $State
}

function Get-ActionCountLastHour {
    param([string]$MonitorName)

    $CutoffTime = (Get-Date).AddHours(-1)
    $Count = 0

    if ($ActionHistory.ContainsKey($MonitorName)) {
        $Count = ($ActionHistory[$MonitorName] | Where-Object {
            [datetime]$_.Timestamp -gt $CutoffTime
        }).Count
    }

    return $Count
}

function Save-ActionHistory {
    param(
        [hashtable]$Monitor,
        [int]$CurrentCount,
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
        $FilePath = Join-Path $PerformanceDataPath "Actions_$Date.csv"

        $Record = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            MonitorName = $Monitor.MonitorName
            ActionType = $Monitor.ActionType
            Success = $Result.Success
            CurrentCount = $CurrentCount
            Threshold = $Monitor.ThresholdCount
            Message = $Result.Message
            ActionTarget = $Monitor.ActionTarget
        }

        if (Test-Path $FilePath) {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation
        }

        # Add to history cache
        if (-not $ActionHistory.ContainsKey($Monitor.MonitorName)) {
            $ActionHistory[$Monitor.MonitorName] = @()
        }
        $ActionHistory[$Monitor.MonitorName] += $Record

        # Clean up old history (keep last 1000 records per monitor)
        if ($ActionHistory[$Monitor.MonitorName].Count -gt 1000) {
            $ActionHistory[$Monitor.MonitorName] = $ActionHistory[$Monitor.MonitorName] | Select-Object -Last 1000
        }
    }
    catch {
        Write-SelfHealingLog "Failed to save action history: $_" -Level "WARNING" -Component "PERF"
    }
}

# ---------- CIRCUIT BREAKER FUNCTIONS ----------
$CircuitBreakerState = @{}

function Check-CircuitBreaker {
    param([string]$MonitorName)

    if (-not $EnableCircuitBreaker) {
        return $true
    }

    $State = $CircuitBreakerState[$MonitorName]
    if ($null -eq $State) {
        return $true
    }

    if ($State.Failures -ge $CircuitBreakerFailureThreshold) {
        $TimeSinceLastFailure = (Get-Date) - $State.LastFailure
        if ($TimeSinceLastFailure.TotalSeconds -gt $CircuitBreakerTimeout) {
            # Reset circuit breaker
            $CircuitBreakerState[$MonitorName] = $null
            Write-SelfHealingLog "Circuit breaker reset for $MonitorName" -Level "INFO" -Component "CIRCUIT"
            return $true
        }
        else {
            Write-SelfHealingLog "Circuit breaker open for $MonitorName (failures: $($State.Failures))" -Level "WARNING" -Component "CIRCUIT"
            return $false
        }
    }

    return $true
}

function Update-CircuitBreaker {
    param(
        [string]$MonitorName,
        [bool]$Success
    )

    if (-not $EnableCircuitBreaker) {
        return
    }

    if (-not $CircuitBreakerState.ContainsKey($MonitorName)) {
        $CircuitBreakerState[$MonitorName] = @{
            Failures = 0
            LastFailure = Get-Date
        }
    }

    if ($Success) {
        $CircuitBreakerState[$MonitorName].Failures = 0
    }
    else {
        $CircuitBreakerState[$MonitorName].Failures++
        $CircuitBreakerState[$MonitorName].LastFailure = Get-Date
    }
}