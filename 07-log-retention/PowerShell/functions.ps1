# ============================================================
# LOG RETENTION - FUNCTIONS FILE
# ============================================================
#
# Contains all helper functions for log retention operations.
# ============================================================

# ---------- LOGGING FUNCTIONS ----------
function Write-RetentionLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "LOG-RETENTION"
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
            $LogFile = Join-Path $LogPath "LogRetention_$(Get-Date -Format 'yyyyMMdd').log"
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
            Write-RetentionLog "Credential '$CredentialName' not found" -Level "WARNING" -Component "CREDENTIALS"
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
        Write-RetentionLog "Error retrieving credential: $_" -Level "ERROR" -Component "CREDENTIALS"
        return $null
    }
}

# ---------- POLICY LOADING FUNCTIONS ----------
function Load-RetentionPolicies {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-RetentionLog "Retention policies file not found: $FilePath" -Level "ERROR" -Component "CONFIG"
        return @()
    }

    $Policies = Import-Csv -Path $FilePath | Where-Object {
        $_.PolicyName -and $_.PolicyName -notmatch '^#'
    }

    Write-RetentionLog "Loaded $($Policies.Count) retention policies from $FilePath" -Level "INFO" -Component "CONFIG"

    # Validate policies
    $EnabledPolicies = $Policies | Where-Object { $_.Enabled -eq 'true' -or $_.Enabled -eq 'TRUE' }
    Write-RetentionLog "$($EnabledPolicies.Count) policies are enabled" -Level "INFO" -Component "CONFIG"

    return $EnabledPolicies
}

# ---------- RETENTION UTILITY FUNCTIONS ----------
function Convert-RetentionPeriod {
    param(
        [int]$Value,
        [string]$Unit
    )

    switch ($Unit.ToLower()) {
        "days" { return $Value }
        "weeks" { return $Value * 7 }
        "months" { return $Value * 30 }
        "years" { return $Value * 365 }
        default {
            Write-RetentionLog "Unknown retention unit: $Unit" -Level "ERROR" -Component "UTILITY"
            return $Value
        }
    }
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

function Is-FileProtected {
    param(
        [string]$FilePath,
        [string]$Pattern
    )

    # Check if file path is in protected folders
    foreach ($ProtectedPath in $ProtectedFolders) {
        if ($FilePath -like "$ProtectedPath*") {
            return $true
        }
    }

    # Check if file matches protected patterns
    $FileName = Split-Path $FilePath -Leaf
    foreach ($ProtectedPattern in $ProtectedPatterns) {
        if ($FileName -like $ProtectedPattern) {
            return $true
        }
    }

    return $false
}

function Get-DiskSpaceStatus {
    param([string]$Path)

    try {
        $Drive = Get-PSDrive -Name (Split-Path $Path -Qualifier).Replace(':', '')
        if ($Drive) {
            $UsedPercent = (($Drive.Used / $Drive.Used) * 100)
            $FreePercent = ($Drive.Free / $Drive.Used) * 100

            $Status = @{
                Used = $Drive.Used
                Free = $Drive.Free
                UsedPercent = [Math]::Round($UsedPercent, 2)
                FreePercent = [Math]::Round($FreePercent, 2)
                Total = $Drive.Used + $Drive.Free
            }

            if ($FreePercent -lt $DiskSpaceCriticalThresholdPercent) {
                $Status.Status = "Critical"
                $Status.Color = "space-critical"
            }
            elseif ($FreePercent -lt $DiskSpaceWarningThresholdPercent) {
                $Status.Status = "Warning"
                $Status.Color = "space-warning"
            }
            else {
                $Status.Status = "OK"
                $Status.Color = "space-ok"
            }

            return $Status
        }
    }
    catch {
        Write-RetentionLog "Failed to get disk space status for $Path: $_" -Level "WARNING" -Component "UTILITY"
    }

    return $null
}

# ---------- FILE PROCESSING FUNCTIONS ----------
function Process-RetentionPolicy {
    param(
        [hashtable]$Policy,
        [ref]$TotalFilesProcessed,
        [ref]$TotalSpaceFreed
    )

    $Result = @{
        PolicyName = $Policy.PolicyName
        Path = $Policy.Path
        Action = $Policy.Action
        FilesProcessed = 0
        SpaceFreed = 0
        Success = $true
        Errors = @()
        Details = @()
    }

    try {
        Write-RetentionLog "========================================" -Level "INFO" -Component "PROCESS"
        Write-RetentionLog "Processing policy: $($Policy.PolicyName)" -Level "INFO" -Component "PROCESS"
        Write-RetentionLog "  Path: $($Policy.Path)" -Level "INFO" -Component "PROCESS"
        Write-RetentionLog "  Pattern: $($Policy.Pattern)" -Level "INFO" -Component "PROCESS"
        Write-RetentionLog "  Retention: $($Policy.RetentionPeriod) $($Policy.RetentionUnit)" -Level "INFO" -Component "PROCESS"
        Write-RetentionLog "  Action: $($Policy.Action)" -Level "INFO" -Component "PROCESS"

        # Check if path exists
        if (-not (Test-Path $Policy.Path)) {
            throw "Path not found: $($Policy.Path)"
        }

        # Check disk space status
        if ($EnableDiskSpaceMonitoring) {
            $DiskStatus = Get-DiskSpaceStatus -Path $Policy.Path
            if ($DiskStatus -and $DiskStatus.Status -eq "Critical") {
                Write-RetentionLog "CRITICAL: Low disk space detected! Free: $($DiskStatus.FreePercent)%" -Level "CRITICAL" -Component "PROCESS"
                # Send critical notification
                Send-Notification -Message "Critical low disk space detected" -Severity "CRITICAL" -Details $DiskStatus
            }
        }

        # Calculate cutoff date
        $RetentionDays = Convert-RetentionPeriod -Value ([int]$Policy.RetentionPeriod) -Unit $Policy.RetentionUnit
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays)

        Write-RetentionLog "  Cutoff date: $CutoffDate" -Level "DEBUG" -Component "PROCESS"

        # Get files
        $Files = Get-ChildItem -Path $Policy.Path -Filter $Policy.Pattern -File -Recurse -ErrorAction SilentlyContinue

        # Apply exclude patterns
        if ($Policy.ExcludePatterns -and $Policy.ExcludePatterns -ne "*" -and $Policy.ExcludePatterns -ne "") {
            $ExcludePatterns = $Policy.ExcludePatterns -split ','
            foreach ($ExcludePattern in $ExcludePatterns) {
                $Files = $Files | Where-Object { $_.Name -notlike $ExcludePattern }
            }
        }

        # Filter files older than cutoff date
        $OldFiles = $Files | Where-Object { $_.LastWriteTime -lt $CutoffDate }

        # Sort by date (oldest first)
        $OldFiles = $OldFiles | Sort-Object LastWriteTime

        # Limit files to process
        if ($OldFiles.Count -gt $MaxFilesPerScan) {
            $OldFiles = $OldFiles | Select-Object -First $MaxFilesPerScan
            Write-RetentionLog "  Limited to $MaxFilesPerScan files (out of $($OldFiles.Count) total)" -Level "WARNING" -Component "PROCESS"
        }

        Write-RetentionLog "  Found $($OldFiles.Count) files older than $($Policy.RetentionPeriod) $($Policy.RetentionUnit)" -Level "INFO" -Component "PROCESS"

        if ($OldFiles.Count -eq 0) {
            Write-RetentionLog "  No files to process" -Level "INFO" -Component "PROCESS"
            return $Result
        }

        # Process files
        $ProcessedCount = 0
        $FreedSpace = 0

        foreach ($File in $OldFiles) {
            # Check if file is protected
            if ($EnableSafetyChecks -and (Is-FileProtected -FilePath $File.FullName -Pattern $Policy.Pattern)) {
                Write-RetentionLog "  Skipping protected file: $($File.Name)" -Level "WARNING" -Component "PROCESS"
                continue
            }

            # Check file size limit
            if ($File.Length -gt ($MaxFileSizeMB * 1MB)) {
                Write-RetentionLog "  Skipping large file: $($File.Name) ($(Format-FileSize $File.Length))" -Level "WARNING" -Component "PROCESS"
                continue
            }

            # Check minimum free space
            if ($EnableSafetyChecks) {
                $Drive = Get-PSDrive -Name (Split-Path $Policy.Path -Qualifier).Replace(':', '')
                if ($Drive -and $Drive.Free -lt ($MinimumFreeSpaceMB * 1MB)) {
                    Write-RetentionLog "  Stopping processing - minimum free space reached" -Level "WARNING" -Component "PROCESS"
                    break
                }
            }

            # Process file based on action
            $ActionResult = $null

            if ($DryRunMode) {
                Write-RetentionLog "  [DRY RUN] Would process: $($File.Name) ($(Format-FileSize $File.Length))" -Level "INFO" -Component "PROCESS"
                $ActionResult = @{ Success = $true; Details = "Dry run - would process" }
            }
            else {
                switch ($Policy.Action) {
                    "Delete" {
                        $ActionResult = Remove-File -FilePath $File.FullName
                    }
                    "Archive" {
                        $ActionResult = Archive-File -FilePath $File.FullName -ArchivePath $Policy.ArchivePath -PolicyName $Policy.PolicyName
                    }
                    "Compress" {
                        $ActionResult = Compress-File -FilePath $File.FullName -ArchivePath $Policy.ArchivePath -PolicyName $Policy.PolicyName
                    }
                    "Move" {
                        $ActionResult = Move-File -FilePath $File.FullName -DestinationPath $Policy.ArchivePath
                    }
                    default {
                        Write-RetentionLog "  Unknown action: $($Policy.Action)" -Level "ERROR" -Component "PROCESS"
                        continue
                    }
                }
            }

            if ($ActionResult -and $ActionResult.Success) {
                $ProcessedCount++
                $FreedSpace += $File.Length
                $Result.Details += "Processed: $($File.Name) ($(Format-FileSize $File.Length))"

                if ($ProcessedCount % 100 -eq 0) {
                    Write-RetentionLog "  Processed $ProcessedCount files..." -Level "INFO" -Component "PROCESS"
                }
            }
            else {
                $Result.Errors += "Failed to process: $($File.Name) - $($ActionResult.Message)"
            }
        }

        $Result.FilesProcessed = $ProcessedCount
        $Result.SpaceFreed = $FreedSpace

        $TotalFilesProcessed.Value += $ProcessedCount
        $TotalSpaceFreed.Value += $FreedSpace

        Write-RetentionLog "  Processed $ProcessedCount files, freed $(Format-FileSize $FreedSpace)" -Level "SUCCESS" -Component "PROCESS"

        # Send notification if configured
        if ($Policy.NotifyOnAction -eq 'true' -or $Policy.NotifyOnAction -eq 'TRUE') {
            if ($ProcessedCount -gt 0) {
                Send-Notification -Policy $Policy -Result $Result -Severity "INFO"
            }
        }
    }
    catch {
        $Result.Success = $false
        $Result.Errors += $_.Exception.Message
        Write-RetentionLog "Error processing policy $($Policy.PolicyName): $_" -Level "ERROR" -Component "PROCESS"
    }

    Write-RetentionLog "========================================" -Level "INFO" -Component "PROCESS"
    return $Result
}

function Remove-File {
    param([string]$FilePath)

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
    }

    try {
        Remove-Item -Path $FilePath -Force -ErrorAction Stop
        $Result.Success = $true
        $Result.Message = "File deleted successfully"
        Write-RetentionLog "  Deleted: $FilePath" -Level "DEBUG" -Component "FILE"
    }
    catch {
        $Result.Message = $_.Exception.Message
        Write-RetentionLog "  Failed to delete $FilePath: $_" -Level "ERROR" -Component "FILE"
    }

    return $Result
}

function Archive-File {
    param(
        [string]$FilePath,
        [string]$ArchivePath,
        [string]$PolicyName
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
    }

    try {
        # Create archive path if it doesn't exist
        if (-not (Test-Path $ArchivePath)) {
            New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
        }

        $FileName = Split-Path $FilePath -Leaf
        $ArchiveFile = Join-Path $ArchivePath $FileName

        # Check if file already exists in archive
        if (Test-Path $ArchiveFile) {
            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
            $Extension = [System.IO.Path]::GetExtension($FileName)
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $ArchiveFile = Join-Path $ArchivePath "$BaseName_$Timestamp$Extension"
        }

        # Move file to archive
        Move-Item -Path $FilePath -Destination $ArchiveFile -Force -ErrorAction Stop
        $Result.Success = $true
        $Result.Message = "File archived successfully"
        $Result.Details.Destination = $ArchiveFile
        Write-RetentionLog "  Archived: $FilePath -> $ArchiveFile" -Level "DEBUG" -Component "FILE"
    }
    catch {
        $Result.Message = $_.Exception.Message
        Write-RetentionLog "  Failed to archive $FilePath: $_" -Level "ERROR" -Component "FILE"
    }

    return $Result
}

function Compress-File {
    param(
        [string]$FilePath,
        [string]$ArchivePath,
        [string]$PolicyName
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
    }

    try {
        # Create archive path if it doesn't exist
        if (-not (Test-Path $ArchivePath)) {
            New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
        }

        $FileName = Split-Path $FilePath -Leaf
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ZipFile = Join-Path $ArchivePath "$BaseName_$Timestamp.zip"

        # Check if using .NET compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

        # Create zip archive
        [System.IO.Compression.ZipFile]::CreateFromDirectory($FilePath, $ZipFile)

        # Delete original file
        Remove-Item -Path $FilePath -Force -ErrorAction Stop

        $Result.Success = $true
        $Result.Message = "File compressed successfully"
        $Result.Details.Archive = $ZipFile
        Write-RetentionLog "  Compressed: $FilePath -> $ZipFile" -Level "DEBUG" -Component "FILE"
    }
    catch {
        # Try using 7-Zip if available
        try {
            $SevenZipPath = Get-Command 7z -ErrorAction SilentlyContinue
            if ($SevenZipPath) {
                $FileName = Split-Path $FilePath -Leaf
                $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
                $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $ZipFile = Join-Path $ArchivePath "$BaseName_$Timestamp.zip"

                $Arguments = "a -tzip `"$ZipFile`" `"$FilePath`" -mx=$ArchiveCompressionLevel"
                Start-Process -FilePath $SevenZipPath.Source -ArgumentList $Arguments -Wait -NoNewWindow

                if (Test-Path $ZipFile) {
                    Remove-Item -Path $FilePath -Force -ErrorAction Stop
                    $Result.Success = $true
                    $Result.Message = "File compressed successfully using 7-Zip"
                    $Result.Details.Archive = $ZipFile
                    Write-RetentionLog "  Compressed with 7-Zip: $FilePath -> $ZipFile" -Level "DEBUG" -Component "FILE"
                }
            }
            else {
                throw "Neither .NET compression nor 7-Zip is available"
            }
        }
        catch {
            $Result.Message = $_.Exception.Message
            Write-RetentionLog "  Failed to compress $FilePath: $_" -Level "ERROR" -Component "FILE"
        }
    }

    return $Result
}

function Move-File {
    param(
        [string]$FilePath,
        [string]$DestinationPath
    )

    $Result = @{
        Success = $false
        Message = ""
        Details = @{}
    }

    try {
        # Create destination path if it doesn't exist
        if (-not (Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }

        $FileName = Split-Path $FilePath -Leaf
        $DestinationFile = Join-Path $DestinationPath $FileName

        # Check if file already exists
        if (Test-Path $DestinationFile) {
            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
            $Extension = [System.IO.Path]::GetExtension($FileName)
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $DestinationFile = Join-Path $DestinationPath "$BaseName_$Timestamp$Extension"
        }

        Move-Item -Path $FilePath -Destination $DestinationFile -Force -ErrorAction Stop
        $Result.Success = $true
        $Result.Message = "File moved successfully"
        $Result.Details.Destination = $DestinationFile
        Write-RetentionLog "  Moved: $FilePath -> $DestinationFile" -Level "DEBUG" -Component "FILE"
    }
    catch {
        $Result.Message = $_.Exception.Message
        Write-RetentionLog "  Failed to move $FilePath: $_" -Level "ERROR" -Component "FILE"
    }

    return $Result
}

# ---------- NOTIFICATION FUNCTIONS ----------
function Send-Notification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity = "INFO",
        [string]$Message = "",
        [hashtable]$Details = $null
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
        $Results.Email = Send-EmailNotification -Policy $Policy -Result $Result -Severity $Severity -Message $Message -Details $Details
    }

    # Send Teams notification
    if ($TeamsConfig.Enabled) {
        $Results.Teams = Send-TeamsNotification -Policy $Policy -Result $Result -Severity $Severity -Message $Message -Details $Details
    }

    # Send Slack notification
    if ($SlackConfig.Enabled) {
        $Results.Slack = Send-SlackNotification -Policy $Policy -Result $Result -Severity $Severity -Message $Message -Details $Details
    }

    return $Results
}

function Send-EmailNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Message,
        [hashtable]$Details
    )

    if (-not $EmailConfig.Enabled) {
        return $false
    }

    try {
        $Credential = Get-StoredCredential -CredentialName $EmailConfig.CredentialName
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $Body = $EmailNotificationTemplate
        $Body = $Body.Replace('{Timestamp}', $Timestamp)
        $Body = $Body.Replace('{TotalPolicies}', "1")
        $Body = $Body.Replace('{ProcessedPolicies}', "1")
        $Body = $Body.Replace('{FilesProcessed}', $Result.FilesProcessed)
        $Body = $Body.Replace('{SpaceFreed}', Format-FileSize $Result.SpaceFreed)
        $Body = $Body.Replace('{SpaceFreedMB}', [Math]::Round($Result.SpaceFreed / 1MB, 2))

        if ($Details -and $Details.Status) {
            $Body = $Body.Replace('{DiskStatus}', $Details.Status)
            $Body = $Body.Replace('{DiskStatusClass}', $Details.Color)
        }
        else {
            $Body = $Body.Replace('{DiskStatus}', "OK")
            $Body = $Body.Replace('{DiskStatusClass}', "space-ok")
        }

        $PolicyResults = @"
        <tr>
            <td>$($Policy.PolicyName)</td>
            <td>$($Policy.Path)</td>
            <td>$($Policy.Action)</td>
            <td>$($Result.FilesProcessed)</td>
            <td>$(Format-FileSize $Result.SpaceFreed)</td>
            <td>$(if ($Result.Success) { "✅ Success" } else { "❌ Failed" })</td>
        </tr>
"@
        $Body = $Body.Replace('{PolicyResults}', $PolicyResults)
        $Body = $Body.Replace('{LogPath}', $LogPath)
        $Body = $Body.Replace('{DryRunMode}', $DryRunMode)

        $Subject = "[$Severity] Log Retention: $($Policy.PolicyName) - $(if ($Result.Success) { "Success" } else { "Failed" })"

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
        Write-RetentionLog "Email notification sent" -Level "INFO" -Component "NOTIFY"
        return $true
    }
    catch {
        Write-RetentionLog "Failed to send email notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-TeamsNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Message,
        [hashtable]$Details
    )

    if (-not $TeamsConfig.Enabled) {
        return $false
    }

    try {
        $ThemeColor = @{
            'SUCCESS' = '00FF00'
            'INFO' = '0000FF'
            'WARNING' = 'FFA500'
            'ERROR' = 'FF0000'
            'CRITICAL' = '8B0000'
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $WebhookURLs = $TeamsConfig.WebhookURLs

        $Payload = $TeamsNotificationTemplate
        $Payload = $Payload.Replace('{ThemeColor}', $ThemeColor[$Severity])
        $Payload = $Payload.Replace('{Summary}', "$Severity: $($Policy.PolicyName)")
        $Payload = $Payload.Replace('{ActivityTitle}', "**$Severity: $($Policy.PolicyName)**")
        $Payload = $Payload.Replace('{ProcessedPolicies}', "1")
        $Payload = $Payload.Replace('{FilesProcessed}', $Result.FilesProcessed)
        $Payload = $Payload.Replace('{SpaceFreed}', Format-FileSize $Result.SpaceFreed)
        $Payload = $Payload.Replace('{DiskStatus}', if ($Details -and $Details.Status) { $Details.Status } else { "OK" })
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
                Write-RetentionLog "Teams notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-RetentionLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-RetentionLog "Failed to send Teams notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

function Send-SlackNotification {
    param(
        [hashtable]$Policy,
        [hashtable]$Result,
        [string]$Severity,
        [string]$Message,
        [hashtable]$Details
    )

    if (-not $SlackConfig.Enabled) {
        return $false
    }

    try {
        $ColorMap = @{
            'SUCCESS' = 'good'
            'INFO' = 'good'
            'WARNING' = 'warning'
            'ERROR' = 'danger'
            'CRITICAL' = 'danger'
        }

        $Timestamp = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))
        $WebhookURLs = $SlackConfig.WebhookURLs

        $Payload = $SlackNotificationTemplate
        $Payload = $Payload.Replace('{Channel}', $SlackConfig.Channel)
        $Payload = $Payload.Replace('{Username}', $SlackConfig.Username)
        $Payload = $Payload.Replace('{IconEmoji}', $SlackConfig.IconEmoji)
        $Payload = $Payload.Replace('{Color}', $ColorMap[$Severity])
        $Payload = $Payload.Replace('{Title}', "$Severity: $($Policy.PolicyName)")
        $Payload = $Payload.Replace('{ProcessedPolicies}', "1")
        $Payload = $Payload.Replace('{FilesProcessed}', $Result.FilesProcessed)
        $Payload = $Payload.Replace('{SpaceFreed}', Format-FileSize $Result.SpaceFreed)
        $Payload = $Payload.Replace('{DiskStatus}', if ($Details -and $Details.Status) { $Details.Status } else { "OK" })
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
                Write-RetentionLog "Slack notification sent to $URL" -Level "INFO" -Component "NOTIFY"
            }
            catch {
                Write-RetentionLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
                $Success = $false
            }
        }
        return $Success
    }
    catch {
        Write-RetentionLog "Failed to send Slack notification: $_" -Level "ERROR" -Component "NOTIFY"
        return $false
    }
}

# ---------- STATE TRACKING FUNCTIONS ----------
$PolicyState = @{}
$RetentionHistory = @{}

function Update-PolicyState {
    param(
        [string]$PolicyName,
        [hashtable]$Result
    )

    $State = @{
        LastCheck = Get-Date
        LastResult = $Result
        TotalFilesProcessed = 0
        TotalSpaceFreed = 0
    }

    if ($PolicyState.ContainsKey($PolicyName)) {
        $State.TotalFilesProcessed = $PolicyState[$PolicyName].TotalFilesProcessed + $Result.FilesProcessed
        $State.TotalSpaceFreed = $PolicyState[$PolicyName].TotalSpaceFreed + $Result.SpaceFreed
    }
    else {
        $State.TotalFilesProcessed = $Result.FilesProcessed
        $State.TotalSpaceFreed = $Result.SpaceFreed
    }

    $PolicyState[$PolicyName] = $State
}

function Save-RetentionHistory {
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
        $FilePath = Join-Path $PerformanceDataPath "Retention_$Date.csv"

        $Record = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            PolicyName = $Policy.PolicyName
            Path = $Policy.Path
            Action = $Policy.Action
            FilesProcessed = $Result.FilesProcessed
            SpaceFreed = $Result.SpaceFreed
            Success = $Result.Success
            Errors = ($Result.Errors -join "; ")
        }

        if (Test-Path $FilePath) {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation -Append
        }
        else {
            $Record | Export-Csv -Path $FilePath -NoTypeInformation
        }
    }
    catch {
        Write-RetentionLog "Failed to save retention history: $_" -Level "WARNING" -Component "PERF"
    }
}