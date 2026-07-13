# ============================================================
# FUNCTIONS FILE - Helper functions for the script
# ============================================================

# Function: Write-Log
# Purpose: Write messages to both console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    # Write to console with color
    Write-Host $LogMessage -ForegroundColor $Color

    # Write to log file if enabled
    if ($EnableLogging -and $LogPath) {
        if (!(Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $LogFile = Join-Path $LogPath "ServerHealth_$(Get-Date -Format 'yyyyMMdd').log"
        Add-Content -Path $LogFile -Value $LogMessage
    }
}

# Function: Test-ServerConnection
# Purpose: Check if a server is reachable before attempting to query
function Test-ServerConnection {
    param(
        [string]$ServerName,
        [string]$IPAddress
    )

    try {
        $TestParams = @{
            ComputerName = $IPAddress
            Count = 2
            TimeoutSeconds = $ServerConnectionTimeout
            Quiet = $true
        }
        $Result = Test-Connection @TestParams
        if ($Result) {
            Write-Log "Server $ServerName ($IPAddress) is reachable" -Level "INFO" -Color "Green"
            return $true
        } else {
            Write-Log "Server $ServerName ($IPAddress) is NOT reachable" -Level "WARNING" -Color "Yellow"
            return $false
        }
    }
    catch {
        Write-Log "Failed to ping $ServerName ($IPAddress): $_" -Level "ERROR" -Color "Red"
        return $false
    }
}

# Function: Get-ServerPerformance
# Purpose: Collect performance data from a remote server
function Get-ServerPerformance {
    param(
        [string]$ServerName,
        [string]$IPAddress,
        [array]$Counters
    )

    $ServerData = [PSCustomObject]@{
        ServerName = $ServerName
        IPAddress = $IPAddress
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Status = "Success"
    }

    try {
        Write-Log "Querying performance counters from $ServerName ($IPAddress)" -Level "INFO" -Color "Cyan"

        foreach ($Counter in $Counters) {
            try {
                $CounterParams = @{
                    ComputerName = $IPAddress
                    Counter = $Counter.Counter
                    MaxSamples = 1
                    ErrorAction = 'Stop'
                }
                $Value = (Get-Counter @CounterParams).CounterSamples.CookedValue

                # Format the value based on counter type
                if ($Counter.Counter -match "%") {
                    $FormattedValue = "{0:N2}%" -f $Value
                } elseif ($Counter.Counter -match "MBytes") {
                    $FormattedValue = "{0:N2} MB" -f $Value
                } else {
                    $FormattedValue = "{0:N2}" -f $Value
                }

                # Add property to the object
                $PropertyName = $Counter.Name -replace "[^a-zA-Z0-9_\-]", "_"
                $ServerData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $FormattedValue

                Write-Log "  $($Counter.Name): $FormattedValue" -Level "INFO" -Color "Gray"
            }
            catch {
                $PropertyName = $Counter.Name -replace "[^a-zA-Z0-9_\-]", "_"
                $ServerData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value "ERROR"
                Write-Log "  Failed to get $($Counter.Name): $_" -Level "WARNING" -Color "Yellow"
            }
        }
    }
    catch {
        Write-Log "Failed to get performance data from $ServerName: $_" -Level "ERROR" -Color "Red"
        $ServerData.Status = "Failed"
        foreach ($Counter in $Counters) {
            $PropertyName = $Counter.Name -replace "[^a-zA-Z0-9_\-]", "_"
            if (!($ServerData | Get-Member -Name $PropertyName)) {
                $ServerData | Add-Member -MemberType NoteProperty -Name $PropertyName -Value "ERROR"
            }
        }
    }

    return $ServerData
}

# Function: Get-StoredCredential
# Purpose: Retrieve credentials from Windows Credential Manager
function Get-StoredCredential {
    param([string]$CredentialName)

    try {
        # Use cmdkey to verify credential exists
        $CredCheck = cmdkey /list | Select-String $CredentialName
        if (!$CredCheck) {
            Write-Log "Credential '$CredentialName' not found in Windows Credential Manager" -Level "ERROR" -Color "Red"
            Write-Log "Please create it using: cmdkey /add:$CredentialName /user:your-email@domain.com /pass:YourPassword" -Level "INFO" -Color "Yellow"
            return $null
        }

        # Retrieve credential using .NET
        $Cred = [System.Net.CredentialCache]::DefaultNetworkCredentials

        # Alternative: Use Windows Credential Manager API
        # For PowerShell 5.1+, we can use the CredentialManager module
        if (Get-Module -Name CredentialManager -ListAvailable) {
            Import-Module CredentialManager -Force
            $StoredCred = Get-StoredCredential -Target $CredentialName
            return $StoredCred
        } else {
            # Fallback: Use cmdkey to retrieve (will prompt for password if not cached)
            Write-Log "CredentialManager module not found. Using alternative method." -Level "WARNING" -Color "Yellow"
            # Note: This will require user interaction if password not cached
            $Cred = Get-Credential -Message "Enter credentials for $CredentialName"
            return $Cred
        }
    }
    catch {
        Write-Log "Error retrieving credential: $_" -Level "ERROR" -Color "Red"
        return $null
    }
}

# Function: Send-EmailReport
# Purpose: Send the report via email in specified format
function Send-EmailReport {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$AttachmentPath,
        [string]$To,
        [string]$From,
        [string]$SMTPServer,
        [int]$Port,
        [bool]$UseSSL,
        [System.Management.Automation.PSCredential]$Credential
    )

    Write-Log "Preparing to send email..." -Level "INFO" -Color "Cyan"

    try {
        # Build email parameters
        $MailParams = @{
            To = $To
            From = $From
            Subject = $Subject
            Body = $Body
            SmtpServer = $SMTPServer
            Port = $Port
            UseSsl = $UseSSL
            BodyAsHtml = $true
        }

        # Add attachment if provided
        if ($AttachmentPath -and (Test-Path $AttachmentPath)) {
            $MailParams.Attachments = $AttachmentPath
            Write-Log "Attaching file: $AttachmentPath" -Level "INFO" -Color "Gray"
        }

        # Add credentials if provided
        if ($Credential) {
            $MailParams.Credential = $Credential
            Write-Log "Using stored credentials for SMTP authentication" -Level "INFO" -Color "Gray"
        }

        # Send email
        Send-MailMessage @MailParams
        Write-Log "Email sent successfully to: $To" -Level "SUCCESS" -Color "Green"
        return $true
    }
    catch {
        Write-Log "Failed to send email: $_" -Level "ERROR" -Color "Red"
        return $false
    }
}

# Function: Generate-CSVReport
# Purpose: Generate CSV report from server data
function Generate-CSVReport {
    param(
        [array]$ServerData,
        [string]$OutputPath,
        [string]$ReportDate
    )

    $CSVFile = Join-Path $OutputPath "ServerHealth_$ReportDate.csv"

    try {
        $ServerData | Export-Csv -Path $CSVFile -NoTypeInformation
        Write-Log "CSV report generated: $CSVFile" -Level "SUCCESS" -Color "Green"
        return $CSVFile
    }
    catch {
        Write-Log "Failed to generate CSV report: $_" -Level "ERROR" -Color "Red"
        return $null
    }
}

# Function: Generate-ExcelReport
# Purpose: Generate Excel report from server data
function Generate-ExcelReport {
    param(
        [array]$ServerData,
        [string]$OutputPath,
        [string]$ReportDate
    )

    $ExcelFile = Join-Path $OutputPath "ServerHealth_$ReportDate.xlsx"

    # Check if ImportExcel module is available
    if (!(Get-Module -Name ImportExcel -ListAvailable)) {
        Write-Log "ImportExcel module not installed. Attempting to install..." -Level "WARNING" -Color "Yellow"
        try {
            Install-Module -Name ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
            Import-Module ImportExcel -Force
            Write-Log "ImportExcel module installed successfully" -Level "SUCCESS" -Color "Green"
        }
        catch {
            Write-Log "Failed to install ImportExcel module. Please install manually: Install-Module ImportExcel" -Level "ERROR" -Color "Red"
            Write-Log "Falling back to CSV format" -Level "WARNING" -Color "Yellow"
            return $null
        }
    }

    try {
        Import-Module ImportExcel -Force

        # Create Excel with formatting
        $ServerData | Export-Excel -Path $ExcelFile -AutoSize -BoldTopRow -FreezeTopRow -WorksheetName "Server Health"

        Write-Log "Excel report generated: $ExcelFile" -Level "SUCCESS" -Color "Green"
        return $ExcelFile
    }
    catch {
        Write-Log "Failed to generate Excel report: $_" -Level "ERROR" -Color "Red"
        Write-Log "Falling back to CSV format" -Level "WARNING" -Color "Yellow"
        return $null
    }
}