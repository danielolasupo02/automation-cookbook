# ============================================================
# BATCH SERVICE RESTART - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# batch service restart automation.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to services.csv file
$ServicesCSVPath = ".\services.csv"

# Default working directory for processes (if not specified in CSV)
$DefaultWorkingDirectory = "C:\BatchScripts"

# Check interval for all services (seconds)
$MasterCheckInterval = 30  # Check every 30 seconds

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\BatchServiceRestart\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- PROCESS MONITORING SETTINGS ----------
# How to detect if a process is running
# Options: "Name" (by process name), "Path" (by executable path), "Both"
$ProcessDetectionMethod = "Both"

# Process detection timeout (seconds)
$ProcessDetectionTimeout = 5

# Enable process tree killing (kill child processes too)
$KillProcessTree = $true

# Time to wait after killing before starting (seconds)
$KillWaitTime = 3

# Time to wait after starting before health check (seconds)
$StartWaitTime = 5

# ---------- SERVICE RESTART SETTINGS ----------
# Global restart cooldown (seconds between restarts of same service)
$GlobalRestartCooldown = 60  # 1 minute minimum between restarts

# Maximum concurrent service restarts
$MaxConcurrentRestarts = 3

# Time to wait before checking service health after restart (seconds)
$PostRestartWaitTime = 10

# Number of health check retries after restart
$HealthCheckRetries = 3

# ---------- NOTIFICATION SETTINGS ----------
# Enable notifications
$EnableNotifications = $true

# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "service-restart@yourcompany.com"
    To = "admin@yourcompany.com; it-team@yourcompany.com"
    CredentialName = "SERVICE_RESTART_EMAIL_CRED"
    MinSeverity = "WARNING"  # INFO, WARNING, ERROR, CRITICAL
}

# Teams Configuration
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx/yyyyy"
    )
    MinSeverity = "WARNING"
}

# Slack Configuration
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX"
    )
    Channel = "#service-alerts"
    Username = "Service Restart Manager"
    IconEmoji = ":recycle:"
    MinSeverity = "WARNING"
}

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance monitoring
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\BatchServiceRestart\Performance"

# Enable parallel checking
$EnableParallelChecking = $true
$MaxParallelChecks = 5

# Service operation timeout (seconds)
$ServiceOperationTimeout = 30

# ---------- ADVANCED SETTINGS ----------
# Enable automatic recovery after multiple failures
$EnableAutoRecovery = $true

# If a service fails this many times in a row, trigger recovery
$FailureThreshold = 10

# Recovery action to take
$RecoveryAction = "NotifyAdmin"  # RebootServer, StopService, NotifyAdmin

# Enable service state caching
$EnableStateCaching = $true
$StateCacheDuration = 15  # Seconds

# Enable process stdout/stderr logging
$EnableProcessLogging = $true
$ProcessLogPath = "C:\BatchServiceRestart\ProcessLogs"

# ---------- NOTIFICATION TEMPLATES ----------
# Email notification template
$EmailNotificationTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .info { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background-color: #ebf5fb; }
        .warning { border-left: 4px solid #f39c12; padding: 10px; margin: 10px 0; background-color: #fef9e7; }
        .error { border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; background-color: #fde8e8; }
        .critical { border-left: 4px solid #c0392b; padding: 10px; margin: 10px 0; background-color: #fadbd8; }
        .success { border-left: 4px solid #27ae60; padding: 10px; margin: 10px 0; background-color: #d5f5e3; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
        .filepath { font-family: Consolas, monospace; background-color: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔄 Service Restart Notification</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="{Severity}">
        <h2>{Severity}: {Action} for {ServiceName}</h2>
        <p><strong>Service Type:</strong> {ServiceType}</p>
        <p><strong>Display Name:</strong> {DisplayName}</p>
        <p><strong>File Path:</strong> <span class="filepath">{FilePath}</span></p>
        <p><strong>Working Directory:</strong> <span class="filepath">{WorkingDirectory}</span></p>
        <p><strong>Arguments:</strong> {Arguments}</p>
        <p><strong>Reason:</strong> {Reason}</p>
        <p><strong>Action Taken:</strong> {Action}</p>
        <p><strong>Result:</strong> {Result}</p>
        <p><strong>Uptime Before:</strong> {UptimeBefore}</p>
        <p><strong>Uptime After:</strong> {UptimeAfter}</p>
        <p><strong>Restart Count (24h):</strong> {RestartCount}</p>
        <p><strong>PID Before:</strong> {PIDBefore}</p>
        <p><strong>PID After:</strong> {PIDAfter}</p>
    </div>
    <div class="info">
        <h3>Service Details</h3>
        <table>
            <tr>
                <td><strong>Name:</strong></td>
                <td>{ServiceName}</td>
            </tr>
            <tr>
                <td><strong>Type:</strong></td>
                <td>{ServiceType}</td>
            </tr>
            <tr>
                <td><strong>Display Name:</strong></td>
                <td>{DisplayName}</td>
            </tr>
            <tr>
                <td><strong>Check Interval:</strong></td>
                <td>{CheckInterval} seconds</td>
            </tr>
            <tr>
                <td><strong>Timeout Threshold:</strong></td>
                <td>{TimeoutThreshold} seconds</td>
            </tr>
            <tr>
                <td><strong>Max Restarts:</strong></td>
                <td>{MaxRestarts} per day</td>
            </tr>
        </table>
    </div>
    <div class="footer">
        <p>This is an automated notification from the Service Restart Manager.</p>
        <p>To view detailed logs, check: {LogPath}</p>
    </div>
</body>
</html>
"@

# Teams notification template
$TeamsNotificationTemplate = @'
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "{ThemeColor}",
    "summary": "{Summary}",
    "sections": [{
        "activityTitle": "**{ActivityTitle}**",
        "activitySubtitle": "Service: {ServiceName}",
        "facts": [
            {"name": "Severity", "value": "{Severity}"},
            {"name": "Action", "value": "{Action}"},
            {"name": "Service Type", "value": "{ServiceType}"},
            {"name": "File Path", "value": "{FilePath}"},
            {"name": "Reason", "value": "{Reason}"},
            {"name": "Result", "value": "{Result}"},
            {"name": "Uptime Before", "value": "{UptimeBefore}"},
            {"name": "Uptime After", "value": "{UptimeAfter}"},
            {"name": "Restart Count (24h)", "value": "{RestartCount}"},
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

# Slack notification template
$SlackNotificationTemplate = @'
{
    "channel": "{Channel}",
    "username": "{Username}",
    "icon_emoji": "{IconEmoji}",
    "attachments": [{
        "color": "{Color}",
        "title": "{Title}",
        "title_link": "{LogPath}",
        "fields": [
            {"title": "Service", "value": "{ServiceName}", "short": false},
            {"title": "Severity", "value": "{Severity}", "short": true},
            {"title": "Action", "value": "{Action}", "short": true},
            {"title": "Service Type", "value": "{ServiceType}", "short": true},
            {"title": "File Path", "value": "{FilePath}", "short": false},
            {"title": "Reason", "value": "{Reason}", "short": false},
            {"title": "Result", "value": "{Result}", "short": true},
            {"title": "Uptime Before", "value": "{UptimeBefore}", "short": true},
            {"title": "Uptime After", "value": "{UptimeAfter}", "short": true},
            {"title": "Restart Count (24h)", "value": "{RestartCount}", "short": true}
        ],
        "footer": "Service Restart Manager",
        "ts": {Timestamp}
    }]
}
'@