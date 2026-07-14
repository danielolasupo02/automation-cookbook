# ============================================================
# SCHEDULED JOB RUNNER - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# scheduled job runner service.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to jobs.csv file
$JobsCSVPath = ".\jobs.csv"

# Master check interval (seconds) - How often to check if jobs need to run
$MasterCheckInterval = 30  # Check every 30 seconds

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\ScheduledJobRunner\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- JOB EXECUTION SETTINGS ----------
# Maximum concurrent jobs
$MaxConcurrentJobs = 5

# Default timeout for jobs (seconds)
$DefaultTimeout = 300

# Default retry count
$DefaultRetryCount = 3

# Default retry delay (seconds)
$DefaultRetryDelay = 60

# Enable job history tracking
$EnableHistoryTracking = $true
$HistoryPath = "C:\ScheduledJobRunner\History"
$HistoryRetentionDays = 90

# ---------- NOTIFICATION SETTINGS ----------
# Enable notifications
$EnableNotifications = $true

# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "job-runner@yourcompany.com"
    CredentialName = "JOB_RUNNER_EMAIL_CRED"
    DefaultTo = "admin@yourcompany.com"
}

# Teams Configuration
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx"
    )
    MinSeverity = "ERROR"  # ERROR, WARNING, INFO
}

# Slack Configuration
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX"
    )
    Channel = "#job-notifications"
    Username = "Job Runner"
    IconEmoji = ":runner:"
    MinSeverity = "WARNING"
}

# ---------- SCHEDULING SETTINGS ----------
# Enable time zone support
$UseLocalTimeZone = $true
$TimeZone = "Eastern Standard Time"  # Only used if UseLocalTimeZone is false

# Enable daylight saving time adjustment
$AdjustForDST = $true

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance tracking
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\ScheduledJobRunner\Performance"

# Enable parallel job execution
$EnableParallelExecution = $true

# ---------- ADVANCED SETTINGS ----------
# Enable job locking (prevents overlapping runs)
$EnableJobLocking = $true

# Enable circuit breaker for jobs
$EnableCircuitBreaker = $true
$CircuitBreakerFailureThreshold = 3
$CircuitBreakerTimeout = 3600  # 1 hour

# Enable job dependencies
$EnableJobDependencies = $false

# ---------- NOTIFICATION TEMPLATES ----------
$EmailNotificationTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .success { border-left: 4px solid #27ae60; padding: 10px; margin: 10px 0; background-color: #d5f5e3; }
        .error { border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; background-color: #fde8e8; }
        .warning { border-left: 4px solid #f39c12; padding: 10px; margin: 10px 0; background-color: #fef9e7; }
        .info { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background-color: #ebf5fb; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📋 Scheduled Job Report</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="{Status}">
        <h2>Job: {JobName}</h2>
        <p><strong>Status:</strong> {Status}</p>
        <p><strong>Schedule:</strong> {Schedule}</p>
        <p><strong>Start Time:</strong> {StartTime}</p>
        <p><strong>End Time:</strong> {EndTime}</p>
        <p><strong>Duration:</strong> {Duration} seconds</p>
        <p><strong>Attempts:</strong> {Attempts}</p>
        <p><strong>Script Path:</strong> {ScriptPath}</p>
        <p><strong>Parameters:</strong> {Parameters}</p>
    </div>
    <div class="info">
        <h3>Output</h3>
        <pre>{Output}</pre>
    </div>
    <div class="footer">
        <p>This is an automated notification from the Scheduled Job Runner.</p>
        <p>Logs are available at: {LogPath}</p>
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
        "activitySubtitle": "Job: {JobName}",
        "facts": [
            {"name": "Status", "value": "{Status}"},
            {"name": "Schedule", "value": "{Schedule}"},
            {"name": "Start Time", "value": "{StartTime}"},
            {"name": "End Time", "value": "{EndTime}"},
            {"name": "Duration", "value": "{Duration} seconds"},
            {"name": "Attempts", "value": "{Attempts}"},
            {"name": "Script", "value": "{ScriptPath}"}
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
            {"title": "Job", "value": "{JobName}", "short": false},
            {"title": "Status", "value": "{Status}", "short": true},
            {"title": "Schedule", "value": "{Schedule}", "short": true},
            {"title": "Start Time", "value": "{StartTime}", "short": true},
            {"title": "End Time", "value": "{EndTime}", "short": true},
            {"title": "Duration", "value": "{Duration} seconds", "short": true},
            {"title": "Attempts", "value": "{Attempts}", "short": true},
            {"title": "Script", "value": "{ScriptPath}", "short": false}
        ],
        "footer": "Scheduled Job Runner",
        "ts": {Timestamp}
    }]
}
'@