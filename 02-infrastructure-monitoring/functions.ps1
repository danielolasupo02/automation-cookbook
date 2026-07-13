# ============================================================
# INFRASTRUCTURE MONITOR - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for monitoring, alerting,
# and notification delivery.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-MonitorLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "MONITOR"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $LogMessage = "[$Timestamp] [$Level] [$Component] $Message"

    # Write to console with color
    $ColorMap = @{
        'DEBUG' = 'Gray'
        'INFO' = 'White'
        'WARNING' = 'Yellow'
        'ERROR' = 'Red'
        'CRITICAL' = 'Magenta'
        'SUCCESS' = 'Green'
    }
    Write-Host $LogMessage -ForegroundColor $ColorMap[$Level]

    # Write to log file if enabled
    if ($EnableLogging) {
        try {
            if (!(Test-Path $LogPath)) {
                New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
            }
            $LogFile = Join-Path $LogPath "InfrastructureMonitor_$(Get-Date -Format 'yyyyMMdd').log"
            Add-Content -Path $LogFile -Value $LogMessage

            # Check log rotation
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
        # Check if credential exists
        $CredCheck = cmdkey /list | Select-String $CredentialName
        if (!$CredCheck) {
            Write-MonitorLog "Credential '$CredentialName' not found. Creating placeholder..." -Level "WARNING" -Component "CREDENTIALS"
            Write-MonitorLog "Run: cmdkey /add:$CredentialName /user:email@domain.com /pass:YourPassword" -Level "INFO" -Component "CREDENTIALS"
            return $null
        }

        # Try to use CredentialManager module
        if (Get-Module -Name CredentialManager -ListAvailable) {
            Import-Module CredentialManager -Force
            $StoredCred = Get-StoredCredential -Target $CredentialName
            return $StoredCred
        }
        else {
            # Fallback method
            Write-MonitorLog "CredentialManager module not available. Using interactive prompt." -Level "WARNING" -Component "CREDENTIALS"
            $Cred = Get-Credential -Message "Enter credentials for $CredentialName"
            return $Cred
        }
    }
    catch {
        Write-MonitorLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

# ---------- SERVER LOADING FUNCTIONS ----------
function Get-ServerList {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-MonitorLog "Server list file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Servers = Get-Content -Path $FilePath | Where-Object {
        $_.Trim() -ne "" -and !$_.StartsWith("#")
    } | ForEach-Object { $_.Trim() }

    Write-MonitorLog "Loaded $($Servers.Count) servers from $FilePath" -Level "INFO" -Component "CONFIG"
    return $Servers
}

function Get-ServerThresholds {
    param([string]$ServerName)

    # Start with global thresholds
    $Thresholds = $GlobalThresholds.Clone()

    # Apply server-specific overrides if they exist
    if ($ServerOverrides.ContainsKey($ServerName)) {
        $Override = $ServerOverrides[$ServerName]
        foreach ($Key in $Override.Keys) {
            $Thresholds[$Key] = $Override[$Key]
        }
        Write-MonitorLog "Applied custom thresholds for $ServerName" -Level "DEBUG" -Component "CONFIG"
    }

    # Get services for this server
    $Services = $GlobalServicesToMonitor.Clone()
    if ($ServerOverrides.ContainsKey($ServerName) -and $ServerOverrides[$ServerName].ContainsKey('CustomServices')) {
        $Services = $ServerOverrides[$ServerName].CustomServices
        Write-MonitorLog "Using custom services for $ServerName" -Level "DEBUG" -Component "CONFIG"
    }

    # Create server configuration object
    $Config = @{
        ServerName = $ServerName
        CPU_Threshold = $Thresholds.CPU_Threshold
        Memory_Threshold = $Thresholds.Memory_Threshold
        Disk_Threshold = $Thresholds.Disk_Threshold
        Network_Threshold = $Thresholds.Network_Threshold
        Services = $Services
    }

    return $Config
}

# ---------- MONITORING FUNCTIONS ----------
function Test-ServerConnection {
    param(
        [string]$ServerName,
        [int]$Timeout = 5
    )

    try {
        $TestParams = @{
            ComputerName = $ServerName
            Count = 2
            TimeoutSeconds = $Timeout
            Quiet = $true
            ErrorAction = 'Stop'
        }
        $Result = Test-Connection @TestParams
        if ($Result) {
            Write-MonitorLog "$ServerName is reachable" -Level "DEBUG" -Component "NETWORK"
            return $true
        }
        else {
            Write-MonitorLog "$ServerName is NOT reachable" -Level "WARNING" -Component "NETWORK"
            return $false
        }
    }
    catch {
        Write-MonitorLog "Connection test failed for $ServerName: $_" -Level "WARNING" -Component "NETWORK"
        return $false
    }
}

function Get-ServerMetrics {
    param(
        [string]$ServerName,
        [hashtable]$ServerConfig
    )

    $Metrics = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        ServerName = $ServerName
        Status = "Unknown"
        CPU = @{Value = 0; Status = "OK"; Percent = 0}
        Memory = @{Value = 0; Status = "OK"; Percent = 0; AvailableMB = 0}
        Disk = @{}
        Network = @{Value = 0; Status = "OK"; Speed = "0 MB/s"}
        Services = @{}
        CustomEndpoints = @{}
        Errors = @()
        Uptime = "Unknown"
    }

    try {
        # Test connection first
        if (Test-ServerConnection -ServerName $ServerName) {
            $Metrics.Status = "Online"

            # Get uptime
            try {
                $OS = Get-CimInstance -ComputerName $ServerName -ClassName Win32_OperatingSystem -ErrorAction Stop
                $Uptime = (Get-Date) - $OS.LastBootUpTime
                $Metrics.Uptime = "$($Uptime.Days)d $($Uptime.Hours)h $($Uptime.Minutes)m"
            }
            catch {
                $Metrics.Uptime = "Unknown"
            }

            # Collect CPU metrics
            if ($EnableCPU) {
                try {
                    $CPUValue = (Get-Counter -ComputerName $ServerName -Counter "\Processor(_Total)\% Processor Time" -ErrorAction Stop).CounterSamples.CookedValue
                    $Metrics.CPU.Value = [Math]::Round($CPUValue, 2)
                    $Metrics.CPU.Percent = $CPUValue

                    # Check threshold
                    $Threshold = $ServerConfig.CPU_Threshold
                    if ($CPUValue -gt $Threshold) {
                        $Metrics.CPU.Status = "Critical"
                    }
                    elseif ($CPUValue -gt ($Threshold * 0.8)) {
                        $Metrics.CPU.Status = "Warning"
                    }
                    else {
                        $Metrics.CPU.Status = "OK"
                    }
                }
                catch {
                    $Metrics.Errors += "CPU: $_"
                    $Metrics.CPU.Status = "Error"
                }
            }

            # Collect Memory metrics
            if ($EnableMemory) {
                try {
                    $MemoryTotal = (Get-Counter -ComputerName $ServerName -Counter "\Memory\Available MBytes" -ErrorAction Stop).CounterSamples.CookedValue
                    $MemoryPercent = (Get-Counter -ComputerName $ServerName -Counter "\Memory\% Committed Bytes In Use" -ErrorAction Stop).CounterSamples.CookedValue
                    $Metrics.Memory.Value = [Math]::Round($MemoryPercent, 2)
                    $Metrics.Memory.Percent = $MemoryPercent
                    $Metrics.Memory.AvailableMB = [Math]::Round($MemoryTotal, 2)

                    $Threshold = $ServerConfig.Memory_Threshold
                    if ($MemoryPercent -gt $Threshold) {
                        $Metrics.Memory.Status = "Critical"
                    }
                    elseif ($MemoryPercent -gt ($Threshold * 0.8)) {
                        $Metrics.Memory.Status = "Warning"
                    }
                    else {
                        $Metrics.Memory.Status = "OK"
                    }
                }
                catch {
                    $Metrics.Errors += "Memory: $_"
                    $Metrics.Memory.Status = "Error"
                }
            }

            # Collect Disk metrics
            if ($EnableDisk) {
                try {
                    $DiskCounters = Get-Counter -ComputerName $ServerName -Counter "\LogicalDisk(*)\% Free Space" -ErrorAction Stop
                    foreach ($Counter in $DiskCounters.CounterSamples) {
                        $Drive = $Counter.InstanceName
                        if ($Drive -match "^[A-Z]:$" -and $Drive -notmatch "_Total") {
                            $FreeSpace = [Math]::Round($Counter.CookedValue, 2)
                            $UsedSpace = 100 - $FreeSpace

                            $Metrics.Disk[$Drive] = @{
                                FreePercent = $FreeSpace
                                UsedPercent = $UsedSpace
                                Status = "OK"
                                TotalSize = "Unknown"
                                FreeSpace = "Unknown"
                            }

                            # Get disk size
                            try {
                                $DiskInfo = Get-CimInstance -ComputerName $ServerName -ClassName Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction SilentlyContinue
                                if ($DiskInfo) {
                                    $Metrics.Disk[$Drive].TotalSize = [Math]::Round($DiskInfo.Size / 1GB, 2)
                                    $Metrics.Disk[$Drive].FreeSpace = [Math]::Round($DiskInfo.FreeSpace / 1GB, 2)
                                }
                            }
                            catch {}

                            $Threshold = $ServerConfig.Disk_Threshold
                            if ($UsedSpace -gt $Threshold) {
                                $Metrics.Disk[$Drive].Status = "Critical"
                            }
                            elseif ($UsedSpace -gt ($Threshold * 0.8)) {
                                $Metrics.Disk[$Drive].Status = "Warning"
                            }
                        }
                    }
                }
                catch {
                    $Metrics.Errors += "Disk: $_"
                }
            }

            # Collect Network metrics
            if ($EnableNetwork) {
                try {
                    $NetworkCounters = Get-Counter -ComputerName $ServerName -Counter "\Network Interface(*)\Bytes Total/sec" -ErrorAction Stop
                    $TotalBytes = ($NetworkCounters.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
                    $Metrics.Network.Value = [Math]::Round($TotalBytes / 1MB, 2)
                    $Metrics.Network.Speed = "$([Math]::Round($TotalBytes / 1MB, 2)) MB/s"

                    $Threshold = $ServerConfig.Network_Threshold
                    if ($Metrics.Network.Value -gt $Threshold) {
                        $Metrics.Network.Status = "Warning"
                    }
                    else {
                        $Metrics.Network.Status = "OK"
                    }
                }
                catch {
                    $Metrics.Errors += "Network: $_"
                    $Metrics.Network.Status = "Error"
                }
            }

            # Collect Service status
            if ($EnableServices -and $ServerConfig.Services) {
                foreach ($ServiceName in $ServerConfig.Services) {
                    try {
                        $Service = Get-Service -ComputerName $ServerName -Name $ServiceName -ErrorAction Stop
                        $Metrics.Services[$ServiceName] = @{
                            Status = $Service.Status
                            StartType = $Service.StartType
                            DisplayName = $Service.DisplayName
                            Alert = ($Service.Status -ne 'Running')
                        }

                        if ($Service.Status -ne 'Running') {
                            $Metrics.Services[$ServiceName].Status = "Stopped"
                        }
                    }
                    catch {
                        $Metrics.Services[$ServiceName] = @{
                            Status = "Unknown"
                            Error = "$_"
                            Alert = $true
                            DisplayName = $ServiceName
                        }
                    }
                }
            }

            # Check custom endpoints
            if ($EnableCustomEndpoints -and $CustomEndpoints) {
                $EndpointServers = $CustomEndpoints | Where-Object { $_.Server -eq $ServerName }
                foreach ($Endpoint in $EndpointServers) {
                    try {
                        $URL = $Endpoint.URL
                        $Response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                        $Metrics.CustomEndpoints[$URL] = @{
                            Status = "OK"
                            Response = $Response.StatusCode
                            Content = $Response.Content.Substring(0, [Math]::Min(100, $Response.Content.Length))
                        }
                    }
                    catch {
                        $Metrics.CustomEndpoints[$Endpoint.URL] = @{
                            Status = "Error"
                            Error = "$_"
                        }
                        $Metrics.Errors += "Endpoint $($Endpoint.URL): $_"
                    }
                }
            }
        }
        else {
            $Metrics.Status = "Offline"
            $Metrics.Errors += "Server is not reachable"
        }
    }
    catch {
        $Metrics.Status = "Error"
        $Metrics.Errors += "General error: $_"
        Write-MonitorLog "Error collecting metrics from $ServerName: $_" -Level "ERROR" -Component "MONITOR"
    }

    return $Metrics
}

# ---------- ALERT FUNCTIONS ----------
function Check-Alerts {
    param(
        [hashtable]$Metrics,
        [hashtable]$ServerConfig,
        [hashtable]$AlertState
    )

    $Alerts = @()
    $ServerName = $Metrics.ServerName

    try {
        # Check CPU alert
        if ($Metrics.CPU.Status -ne "OK" -and $Metrics.CPU.Status -ne "Error") {
            $AlertKey = "$ServerName-CPU"
            $LastAlertTime = $AlertState[$AlertKey]

            if ($null -eq $LastAlertTime -or ((Get-Date) - $LastAlertTime).TotalSeconds -gt $AlertCooldown) {
                $Alert = @{
                    ServerName = $ServerName
                    AlertType = "CPU"
                    Severity = $Metrics.CPU.Status
                    Message = "CPU usage is at $($Metrics.CPU.Value)%"
                    Value = "$($Metrics.CPU.Value)%"
                    Threshold = "$($ServerConfig.CPU_Threshold)%"
                    Timestamp = $Metrics.Timestamp
                    Counter = "\Processor(_Total)\% Processor Time"
                    Summary = "CPU Alert on $ServerName"
                }
                $Alerts += $Alert
                $AlertState[$AlertKey] = Get-Date
                Write-MonitorLog "CPU alert triggered for $ServerName ($($Metrics.CPU.Value)%)" -Level $Metrics.CPU.Status -Component "ALERT"
            }
        }

        # Check Memory alert
        if ($Metrics.Memory.Status -ne "OK" -and $Metrics.Memory.Status -ne "Error") {
            $AlertKey = "$ServerName-Memory"
            $LastAlertTime = $AlertState[$AlertKey]

            if ($null -eq $LastAlertTime -or ((Get-Date) - $LastAlertTime).TotalSeconds -gt $AlertCooldown) {
                $Alert = @{
                    ServerName = $ServerName
                    AlertType = "Memory"
                    Severity = $Metrics.Memory.Status
                    Message = "Memory usage is at $($Metrics.Memory.Value)% (Available: $($Metrics.Memory.AvailableMB) MB)"
                    Value = "$($Metrics.Memory.Value)%"
                    Threshold = "$($ServerConfig.Memory_Threshold)%"
                    Timestamp = $Metrics.Timestamp
                    Counter = "\Memory\% Committed Bytes In Use"
                    Summary = "Memory Alert on $ServerName"
                }
                $Alerts += $Alert
                $AlertState[$AlertKey] = Get-Date
                Write-MonitorLog "Memory alert triggered for $ServerName ($($Metrics.Memory.Value)%)" -Level $Metrics.Memory.Status -Component "ALERT"
            }
        }

        # Check Disk alerts
        foreach ($Drive in $Metrics.Disk.Keys) {
            $DiskStatus = $Metrics.Disk[$Drive].Status
            if ($DiskStatus -ne "OK") {
                $AlertKey = "$ServerName-Disk-$Drive"
                $LastAlertTime = $AlertState[$AlertKey]

                if ($null -eq $LastAlertTime -or ((Get-Date) - $LastAlertTime).TotalSeconds -gt $AlertCooldown) {
                    $Alert = @{
                        ServerName = $ServerName
                        AlertType = "Disk"
                        Severity = $DiskStatus
                        Message = "Disk $Drive is at $($Metrics.Disk[$Drive].UsedPercent)% usage (Free: $($Metrics.Disk[$Drive].FreePercent)%)"
                        Value = "$($Metrics.Disk[$Drive].UsedPercent)%"
                        Threshold = "$($ServerConfig.Disk_Threshold)%"
                        Timestamp = $Metrics.Timestamp
                        Counter = "\LogicalDisk($Drive)\% Free Space"
                        Summary = "Disk Alert on $ServerName - $Drive"
                    }
                    $Alerts += $Alert
                    $AlertState[$AlertKey] = Get-Date
                    Write-MonitorLog "Disk alert triggered for $ServerName $Drive ($($Metrics.Disk[$Drive].UsedPercent)%)" -Level $DiskStatus -Component "ALERT"
                }
            }
        }

        # Check Network alert
        if ($Metrics.Network.Status -ne "OK" -and $Metrics.Network.Status -ne "Error") {
            $AlertKey = "$ServerName-Network"
            $LastAlertTime = $AlertState[$AlertKey]

            if ($null -eq $LastAlertTime -or ((Get-Date) - $LastAlertTime).TotalSeconds -gt $AlertCooldown) {
                $Alert = @{
                    ServerName = $ServerName
                    AlertType = "Network"
                    Severity = $Metrics.Network.Status
                    Message = "Network traffic is at $($Metrics.Network.Speed)"
                    Value = "$($Metrics.Network.Speed)"
                    Threshold = "$($ServerConfig.Network_Threshold) MB/s"
                    Timestamp = $Metrics.Timestamp
                    Counter = "\Network Interface(*)\Bytes Total/sec"
                    Summary = "Network Alert on $ServerName"
                }
                $Alerts += $Alert
                $AlertState[$AlertKey] = Get-Date
                Write-MonitorLog "Network alert triggered for $ServerName ($($Metrics.Network.Speed))" -Level $Metrics.Network.Status -Component "ALERT"
            }
        }

        # Check Service alerts
        foreach ($ServiceName in $Metrics.Services.Keys) {
            $Service = $Metrics.Services[$ServiceName]
            if ($Service.Alert) {
                $AlertKey = "$ServerName-Service-$ServiceName"
                $LastAlertTime = $AlertState[$AlertKey]

                if ($null -eq $LastAlertTime -or ((Get-Date) - $LastAlertTime).TotalSeconds -gt $AlertCooldown) {
                    $Alert = @{
                        ServerName = $ServerName
                        AlertType = "Service"
                        Severity = "Critical"
                        Message = "Service '$ServiceName' is $($Service.Status) (Expected: Running)"
                        Value = $Service.Status
                        Threshold = "Running"
                        Timestamp = $Metrics.Timestamp
                        Counter = "Service:$ServiceName"
                        Summary = "Service Alert on $ServerName - $ServiceName"
                    }
                    $Alerts += $Alert
                    $AlertState[$AlertKey] = Get-Date
                    Write-MonitorLog "Service alert triggered for $ServerName - $ServiceName ($($Service.Status))" -Level "CRITICAL" -Component "ALERT"
                }
            }
        }
    }
    catch {
        Write-MonitorLog "Error checking alerts for $ServerName: $_" -Level "ERROR" -Component "ALERT"
    }

    return $Alerts
}

# ---------- NOTIFICATION FUNCTIONS ----------
function Should-SendAlert {
    param(
        [hashtable]$Alert,
        [string]$Channel
    )

    $SeverityOrder = @{
        'INFO' = 1
        'WARNING' = 2
        'CRITICAL' = 3
        'ERROR' = 4
    }

    $AlertSeverity = $SeverityOrder[$Alert.Severity]
    $MinSeverity = switch ($Channel) {
        'Email' { $SeverityOrder[$EmailConfig.MinSeverity] }
        'Teams' { $SeverityOrder[$TeamsConfig.MinSeverity] }
        'Slack' { $SeverityOrder[$SlackConfig.MinSeverity] }
        default { 1 }
    }

    return $AlertSeverity -ge $MinSeverity
}

function Send-EmailAlert {
    param(
        [hashtable]$Alert,
        [hashtable]$Metrics
    )

    if (-not $EmailConfig.Enabled) {
        return $false
    }

    if (-not (Should-SendAlert -Alert $Alert -Channel "Email")) {
        Write-MonitorLog "Skipping email alert (severity below threshold)" -Level "DEBUG" -Component "EMAIL"
        return $false
    }

    try {
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $AlertTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Build email body
        $Body = $EmailAlertTemplate
        $Body = $Body.Replace('{AlertTime}', $AlertTime)
        $Body = $Body.Replace('{ServerName}', $Alert.ServerName)
        $Body = $Body.Replace('{Severity}', $Alert.Severity)
        $Body = $Body.Replace('{AlertType}', $Alert.AlertType)
        $Body = $Body.Replace('{Message}', $Alert.Message)
        $Body = $Body.Replace('{Value}', $Alert.Value)
        $Body = $Body.Replace('{Threshold}', $Alert.Threshold)
        $Body = $Body.Replace('{Status}', $Metrics.Status)
        $Body = $Body.Replace('{LastCheck}', $Metrics.Timestamp)
        $Body = $Body.Replace('{CPU_Usage}', "$($Metrics.CPU.Value)%")
        $Body = $Body.Replace('{Memory_Usage}', "$($Metrics.Memory.Value)%")

        $DiskSummary = ""
        foreach ($Drive in $Metrics.Disk.Keys) {
            $DiskSummary += "$Drive: $($Metrics.Disk[$Drive].UsedPercent)% used ($($Metrics.Disk[$Drive].FreePercent)% free) "
        }
        $Body = $Body.Replace('{Disk_Usage}', $DiskSummary)

        # Send email
        $MailParams = @{
            To = $EmailConfig.To
            From = $EmailConfig.From
            Subject = "[$($Alert.Severity)] $($Alert.AlertType) Alert on $($Alert.ServerName)"
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
        Write-MonitorLog "Email alert sent for $($Alert.ServerName)" -Level "INFO" -Component "EMAIL"
        return $true
    }
    catch {
        Write-MonitorLog "Failed to send email alert: $_" -Level "ERROR" -Component "EMAIL"
        return $false
    }
}

function Send-TeamsAlert {
    param(
        [hashtable]$Alert
    )

    if (-not $TeamsConfig.Enabled) {
        return $false
    }

    if (-not (Should-SendAlert -Alert $Alert -Channel "Teams")) {
        Write-MonitorLog "Skipping Teams alert (severity below threshold)" -Level "DEBUG" -Component "TEAMS"
        return $false
    }

    try {
        $ThemeColor = @{
            'Critical' = 'FF0000'
            'Warning' = 'FFA500'
            'Info' = '0000FF'
        }

        $AlertTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $WebhookURLs = $TeamsConfig.WebhookURLs

        # Build JSON payload
        $Payload = $TeamsAlertTemplate
        $Payload = $Payload.Replace('{ThemeColor}', $ThemeColor[$Alert.Severity])
        $Payload = $Payload.Replace('{Summary}', $Alert.Summary)
        $Payload = $Payload.Replace('{ActivityTitle}', "**$($Alert.Severity) Alert: $($Alert.AlertType)**")
        $Payload = $Payload.Replace('{ServerName}', $Alert.ServerName)
        $Payload = $Payload.Replace('{Severity}', $Alert.Severity)
        $Payload = $Payload.Replace('{AlertType}', $Alert.AlertType)
        $Payload = $Payload.Replace('{Message}', $Alert.Message)
        $Payload = $Payload.Replace('{Value}', $Alert.Value)
        $Payload = $Payload.Replace('{Threshold}', $Alert.Threshold)
        $Payload = $Payload.Replace('{AlertTime}', $AlertTime)
        $Payload = $Payload.Replace('{DashboardURL}', "http://$($Alert.ServerName):8080/dashboard")

        # Send to each webhook
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
                Write-MonitorLog "Teams alert sent to $URL" -Level "INFO" -Component "TEAMS"
            }
            catch {
                Write-MonitorLog "Failed to send Teams alert to $URL: $_" -Level "ERROR" -Component "TEAMS"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-MonitorLog "Failed to send Teams alert: $_" -Level "ERROR" -Component "TEAMS"
        return $false
    }
}

function Send-SlackAlert {
    param(
        [hashtable]$Alert
    )

    if (-not $SlackConfig.Enabled) {
        return $false
    }

    if (-not (Should-SendAlert -Alert $Alert -Channel "Slack")) {
        Write-MonitorLog "Skipping Slack alert (severity below threshold)" -Level "DEBUG" -Component "SLACK"
        return $false
    }

    try {
        $ColorMap = @{
            'Critical' = 'danger'
            'Warning' = 'warning'
            'Info' = 'good'
        }

        $AlertTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Timestamp = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))
        $WebhookURLs = $SlackConfig.WebhookURLs

        # Build JSON payload
        $Payload = $SlackAlertTemplate
        $Payload = $Payload.Replace('{Channel}', $SlackConfig.Channel)
        $Payload = $Payload.Replace('{Username}', $SlackConfig.Username)
        $Payload = $Payload.Replace('{IconEmoji}', $SlackConfig.IconEmoji)
        $Payload = $Payload.Replace('{Color}', $ColorMap[$Alert.Severity])
        $Payload = $Payload.Replace('{Title}', "$($Alert.Severity): $($Alert.AlertType) Alert")
        $Payload = $Payload.Replace('{DashboardURL}', "http://$($Alert.ServerName):8080/dashboard")
        $Payload = $Payload.Replace('{ServerName}', $Alert.ServerName)
        $Payload = $Payload.Replace('{Severity}', $Alert.Severity)
        $Payload = $Payload.Replace('{AlertType}', $Alert.AlertType)
        $Payload = $Payload.Replace('{Message}', $Alert.Message)
        $Payload = $Payload.Replace('{Value}', $Alert.Value)
        $Payload = $Payload.Replace('{Threshold}', $Alert.Threshold)
        $Payload = $Payload.Replace('{Timestamp}', $Timestamp)

        # Send to each webhook
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
                Write-MonitorLog "Slack alert sent to $URL" -Level "INFO" -Component "SLACK"
            }
            catch {
                Write-MonitorLog "Failed to send Slack alert to $URL: $_" -Level "ERROR" -Component "SLACK"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-MonitorLog "Failed to send Slack alert: $_" -Level "ERROR" -Component "SLACK"
        return $false
    }
}

function Send-AllNotifications {
    param(
        [hashtable]$Alert,
        [hashtable]$Metrics
    )

    $Results = @{
        Email = $false
        Teams = $false
        Slack = $false
    }

    # Send email
    $Results.Email = Send-EmailAlert -Alert $Alert -Metrics $Metrics

    # Send Teams
    $Results.Teams = Send-TeamsAlert -Alert $Alert

    # Send Slack
    $Results.Slack = Send-SlackAlert -Alert $Alert

    return $Results
}

# ---------- DATA STORAGE FUNCTIONS ----------
function Save-Metrics {
    param(
        [hashtable]$Metrics
    )

    if (-not $EnableMetricsStorage) {
        return
    }

    try {
        if (!(Test-Path $MetricsStoragePath)) {
            New-Item -ItemType Directory -Path $MetricsStoragePath -Force | Out-Null
        }

        $Date = Get-Date -Format "yyyyMMdd"
        $FilePath = Join-Path $MetricsStoragePath "Metrics_$Date.csv"

        # Convert metrics to CSV-friendly format
        $MetricObject = [PSCustomObject]@{
            Timestamp = $Metrics.Timestamp
            ServerName = $Metrics.ServerName
            Status = $Metrics.Status
            CPU_Value = $Metrics.CPU.Value
            CPU_Status = $Metrics.CPU.Status
            Memory_Value = $Metrics.Memory.Value
            Memory_Status = $Metrics.Memory.Status
            Memory_AvailableMB = $Metrics.Memory.AvailableMB
            Network_Value = $Metrics.Network.Value
            Network_Status = $Metrics.Network.Status
            Uptime = $Metrics.Uptime
            Errors = ($Metrics.Errors -join "; ")
        }

        # Add disk metrics
        $DiskIndex = 1
        foreach ($Drive in $Metrics.Disk.Keys) {
            $MetricObject | Add-Member -MemberType NoteProperty -Name "Disk_${Drive}_Used" -Value $Metrics.Disk[$Drive].UsedPercent
            $MetricObject | Add-Member -MemberType NoteProperty -Name "Disk_${Drive}_Free" -Value $Metrics.Disk[$Drive].FreePercent
            $MetricObject | Add-Member -MemberType NoteProperty -Name "Disk_${Drive}_Status" -Value $Metrics.Disk[$Drive].Status
            $DiskIndex++
        }

        # Append to CSV
        if (Test-Path $FilePath) {
            $MetricObject | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $MetricObject | Export-Csv -Path $FilePath -NoTypeInformation
        }

        Write-MonitorLog "Metrics saved for $($Metrics.ServerName)" -Level "DEBUG" -Component "STORAGE"

        # Clean up old metrics
        $CutoffDate = (Get-Date).AddDays(-$MetricsRetentionDays)
        Get-ChildItem -Path $MetricsStoragePath -Filter "Metrics_*.csv" | ForEach-Object {
            if ($_.LastWriteTime -lt $CutoffDate) {
                Remove-Item $_.FullName -Force
                Write-MonitorLog "Removed old metrics file: $($_.Name)" -Level "DEBUG" -Component "STORAGE"
            }
        }
    }
    catch {
        Write-MonitorLog "Failed to save metrics: $_" -Level "WARNING" -Component "STORAGE"
    }
}

function Save-Alert {
    param(
        [hashtable]$Alert,
        [hashtable]$NotificationResults
    )

    try {
        if (!(Test-Path $AlertHistoryPath)) {
            New-Item -ItemType Directory -Path $AlertHistoryPath -Force | Out-Null
        }

        $Date = Get-Date -Format "yyyyMMdd"
        $FilePath = Join-Path $AlertHistoryPath "Alerts_$Date.csv"

        $AlertObject = [PSCustomObject]@{
            Timestamp = $Alert.Timestamp
            ServerName = $Alert.ServerName
            AlertType = $Alert.AlertType
            Severity = $Alert.Severity
            Message = $Alert.Message
            Value = $Alert.Value
            Threshold = $Alert.Threshold
            EmailSent = $NotificationResults.Email
            TeamsSent = $NotificationResults.Teams
            SlackSent = $NotificationResults.Slack
        }

        if (Test-Path $FilePath) {
            $AlertObject | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $AlertObject | Export-Csv -Path $FilePath -NoTypeInformation
        }

        # Clean up old alerts
        $CutoffDate = (Get-Date).AddDays(-$AlertHistoryRetentionDays)
        Get-ChildItem -Path $AlertHistoryPath -Filter "Alerts_*.csv" | ForEach-Object {
            if ($_.LastWriteTime -lt $CutoffDate) {
                Remove-Item $_.FullName -Force
            }
        }
    }
    catch {
        Write-MonitorLog "Failed to save alert: $_" -Level "WARNING" -Component "STORAGE"
    }
}

# ---------- CIRCUIT BREAKER FUNCTIONS ----------
$CircuitBreakerState = @{}

function Check-CircuitBreaker {
    param([string]$ServerName)

    if (-not $EnableCircuitBreaker) {
        return $true
    }

    $State = $CircuitBreakerState[$ServerName]
    if ($null -eq $State) {
        return $true
    }

    if ($State.Failures -ge $CircuitBreakerFailureThreshold) {
        $TimeSinceLastFailure = (Get-Date) - $State.LastFailure
        if ($TimeSinceLastFailure.TotalSeconds -gt $CircuitBreakerTimeout) {
            # Reset circuit breaker
            $CircuitBreakerState[$ServerName] = $null
            Write-MonitorLog "Circuit breaker reset for $ServerName" -Level "INFO" -Component "CIRCUIT"
            return $true
        }
        else {
            Write-MonitorLog "Circuit breaker open for $ServerName (failures: $($State.Failures))" -Level "WARNING" -Component "CIRCUIT"
            return $false
        }
    }

    return $true
}

function Update-CircuitBreaker {
    param(
        [string]$ServerName,
        [bool]$Success
    )

    if (-not $EnableCircuitBreaker) {
        return
    }

    if (-not $CircuitBreakerState.ContainsKey($ServerName)) {
        $CircuitBreakerState[$ServerName] = @{
            Failures = 0
            LastFailure = Get-Date
        }
    }

    if ($Success) {
        $CircuitBreakerState[$ServerName].Failures = 0
    }
    else {
        $CircuitBreakerState[$ServerName].Failures++
        $CircuitBreakerState[$ServerName].LastFailure = Get-Date
    }
}