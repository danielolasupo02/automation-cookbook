# ============================================================
# LOG RETENTION - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# log retention service.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to retention-policies.csv file
$PoliciesCSVPath = ".\retention-policies.csv"

# Master check interval (seconds) - How often to check for files to clean up
$MasterCheckInterval = 3600  # Check every hour (3600 seconds)

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\LogRetention\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- RETENTION SETTINGS ----------
# Enable dry run mode (log what would be done without actually doing it)
$DryRunMode = $false

# Maximum files to process per scan (to prevent performance issues)
$MaxFilesPerScan = 10000

# Maximum file size to process (MB) - skip files larger than this
$MaxFileSizeMB = 1024  # 1 GB

# Enable parallel processing
$EnableParallelProcessing = $true
$MaxParallelThreads = 5

# ---------- ARCHIVE SETTINGS ----------
# Archive compression level (0-9, where 9 is highest compression)
$ArchiveCompressionLevel = 5

# Archive format
$ArchiveFormat = "Zip"  # Zip, GZip, Tar

# Enable archive password protection (optional)
$ArchivePassword = $null  # Set to password string or $null for no password

# Archive naming format
$ArchiveNameFormat = "{PolicyName}_{Date}_{Time}"  # {PolicyName}, {Date}, {Time}, {Folder}

# ---------- NOTIFICATION SETTINGS ----------
# Enable notifications
$EnableNotifications = $true

# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "log-retention@yourcompany.com"
    To = "admin@yourcompany.com; it-team@yourcompany.com"
    CredentialName = "LOG_RETENTION_EMAIL_CRED"
}

# Teams Configuration
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx"
    )
    MinSeverity = "WARNING"  # ERROR, WARNING, INFO
}

# Slack Configuration
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX"
    )
    Channel = "#log-retention"
    Username = "Log Retention"
    IconEmoji = ":file_cabinet:"
    MinSeverity = "WARNING"
}

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance tracking
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\LogRetention\Performance"

# Enable disk space monitoring
$EnableDiskSpaceMonitoring = $true
$DiskSpaceWarningThresholdPercent = 80
$DiskSpaceCriticalThresholdPercent = 90

# Enable speed optimization
$EnableBatchProcessing = $true
$BatchSize = 100

# ---------- SAFETY SETTINGS ----------
# Enable safety checks (prevent deletion of critical files)
$EnableSafetyChecks = $true

# Protected folders (never delete files from these paths)
$ProtectedFolders = @(
    "C:\Windows",
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\System Volume Information",
    "C:\Boot"
)

# Protected file patterns (never delete files matching these patterns)
$ProtectedPatterns = @(
    "*.exe",
    "*.dll",
    "*.sys",
    "*.msi",
    "*.msp",
    "*.cab",
    "*.ini",
    "*.config",
    "*.xml",
    "*.json"
)

# Minimum free space to maintain (MB)
$MinimumFreeSpaceMB = 1024  # 1 GB

# ---------- NOTIFICATION TEMPLATES ----------
$EmailNotificationTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .success { border-left: 4px solid #27ae60; padding: 10px; margin: 10px 0; background-color: #d5f5e3; }
        .warning { border-left: 4px solid #f39c12; padding: 10px; margin: 10px 0; background-color: #fef9e7; }
        .error { border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; background-color: #fde8e8; }
        .info { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background-color: #ebf5fb; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
        .space-warning { color: #f39c12; font-weight: bold; }
        .space-critical { color: #e74c3c; font-weight: bold; }
        .space-ok { color: #27ae60; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📁 Log Retention Report</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Policies:</strong> {TotalPolicies}</p>
        <p><strong>Policies Processed:</strong> {ProcessedPolicies}</p>
        <p><strong>Files Processed:</strong> {FilesProcessed}</p>
        <p><strong>Space Freed:</strong> {SpaceFreed} ({SpaceFreedMB} MB)</p>
        <p><strong>Disk Space Status:</strong> <span class="{DiskStatusClass}">{DiskStatus}</span></p>
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
        {PolicyResults}
    </table>
    <div class="footer">
        <p>This is an automated notification from the Log Retention System.</p>
        <p>Logs are available at: {LogPath}</p>
        <p>Dry Run Mode: {DryRunMode}</p>
    </div>
</body>
</html>
"@

$TeamsNotificationTemplate = @'
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "{ThemeColor}",
    "summary": "{Summary}",
    "sections": [{
        "activityTitle": "**{ActivityTitle}**",
        "activitySubtitle": "Log Retention Report",
        "facts": [
            {"name": "Policies Processed", "value": "{ProcessedPolicies}"},
            {"name": "Files Processed", "value": "{FilesProcessed}"},
            {"name": "Space Freed", "value": "{SpaceFreed}"},
            {"name": "Disk Space", "value": "{DiskStatus}"},
            {"name": "Time", "value": "{Timestamp}"}
        ],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View Logs",
        "targets": [{ "os": "default", "uri": "{LogPath}" }]
    }]
}
'@

$SlackNotificationTemplate = @'
{
    "channel": "{Channel}",
    "username": "{Username}",
    "icon_emoji": "{IconEmoji}",
    "attachments": [{
        "color": "{Color}",
        "title": "{Title}",
        "fields": [
            {"title": "Policies Processed", "value": "{ProcessedPolicies}", "short": true},
            {"title": "Files Processed", "value": "{FilesProcessed}", "short": true},
            {"title": "Space Freed", "value": "{SpaceFreed}", "short": true},
            {"title": "Disk Status", "value": "{DiskStatus}", "short": true}
        ],
        "footer": "Log Retention System",
        "ts": {Timestamp}
    }]
}
'@