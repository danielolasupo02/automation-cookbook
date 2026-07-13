# ============================================================
# CONFIGURATION FILE - Configure your settings here
# ============================================================

# ---------- EMAIL SETTINGS ----------
# Email recipient(s) - separate multiple with semicolon (;)
$EmailTo = "admin@yourcompany.com; it-team@yourcompany.com"

# Email sender (must be authorized to send through your SMTP server)
$EmailFrom = "server-reports@yourcompany.com"

# Email subject prefix (will include date automatically)
$EmailSubjectPrefix = "Server Health Report"

# SMTP Server configuration
$SMTPServer = "smtp.yourcompany.com"
$SMTPPort = 587  # 25, 465, or 587
$SMTPUseSSL = $true  # $true or $false

# Windows Credential Manager entry name (for secure password storage)
# Create this credential using: cmdkey /add:SMTP_CRED /user:email@domain.com /pass:YourPassword
$CredentialName = "SMTP_CRED"

# ---------- REPORT SETTINGS ----------
# Report format: "CSV" or "EXCEL" (case insensitive)
$ReportFormat = "EXCEL"

# Location to store temporary report files (will auto-create if doesn't exist)
$ReportOutputPath = "C:\ServerReports"

# Include these performance counters in the report
$PerformanceCounters = @(
    @{Name="CPU Usage"; Counter="\Processor(_Total)\% Processor Time"},
    @{Name="Memory Usage %"; Counter="\Memory\% Committed Bytes In Use"},
    @{Name="Memory Available (MB)"; Counter="\Memory\Available MBytes"},
    @{Name="Disk C: Usage %"; Counter="\LogicalDisk(C:)\% Free Space"},
    @{Name="Disk D: Usage %"; Counter="\LogicalDisk(D:)\% Free Space"},
    @{Name="Disk E: Usage %"; Counter="\LogicalDisk(E:)\% Free Space"}
)

# ---------- SERVER SETTINGS ----------
# Path to servers.csv file (should be in same directory as script)
$ServersCSVPath = ".\servers.csv"

# Timeout for remote connections (seconds)
$ServerConnectionTimeout = 30

# ---------- LOGGING SETTINGS ----------
# Enable logging to a file
$EnableLogging = $true
$LogPath = "C:\ServerReports\Logs"

# ---------- ADDITIONAL NOTES ----------
# For Excel reports, ensure these modules are installed:
#   Install-Module -Name ImportExcel -Scope CurrentUser -Force
# For Windows Credential Manager, use cmdkey command to store credentials:
#   cmdkey /add:SMTP_CRED /user:your-email@domain.com /pass:YourPasswordHere