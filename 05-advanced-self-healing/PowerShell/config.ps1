# ============================================================
# ADVANCED SELF-HEALING - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# advanced self-healing automation.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to monitors.csv file
$MonitorsCSVPath = ".\monitors.csv"

# Master check interval (seconds)
$MasterCheckInterval = 30  # Check every 30 seconds

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\AdvancedSelfHealing\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- DATABASE SETTINGS ----------
# Credential Manager entries for database connections
# Format: CredentialName = "DB_<DatabaseType>_<Environment>"
$CredentialManagerEntries = @{
    Oracle = "DB_ORACLE_CRED"
    SQLServer = "DB_SQLSERVER_CRED"
    MySQL = "DB_MYSQL_CRED"
    PostgreSQL = "DB_POSTGRESQL_CRED"
}

# Connection timeout (seconds)
$DBConnectionTimeout = 30

# Query execution timeout (seconds)
$DBQueryTimeout = 60

# Max retry attempts for failed connections
$DBMaxRetries = 3
$DBRetryDelay = 5  # Seconds between retries

# ---------- ACTION SETTINGS ----------
# IIS restart settings
$IISRestartMethod = "Recycle"  # Recycle, StopStart, SiteRestart
$IISPostRestartWait = 10  # Seconds to wait after restart
$IISHealthCheckRetries = 3

# Email settings
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "self-healing@yourcompany.com"
    CredentialName = "SELF_HEALING_EMAIL_CRED"
    DefaultTo = "admin@yourcompany.com; it-team@yourcompany.com"
}

# Teams settings
$TeamsConfig = @{
    Enabled = $true
    DefaultWebhookURL = "https://yourcompany.webhook.office.com/webhookb2/xxxxx"
}

# Slack settings
$SlackConfig = @{
    Enabled = $true
    DefaultWebhookURL = "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX"
    DefaultChannel = "#infrastructure-alerts"
    Username = "Self-Healing System"
    IconEmoji = ":robot_face:"
}

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance tracking
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\AdvancedSelfHealing\Performance"

# Enable parallel monitoring
$EnableParallelMonitoring = $true
$MaxParallelMonitors = 10

# ---------- ADVANCED SETTINGS ----------
# Enable circuit breaker
$EnableCircuitBreaker = $true
$CircuitBreakerFailureThreshold = 5
$CircuitBreakerTimeout = 300  # Seconds

# Enable alert cooldown (prevent duplicate alerts)
$EnableAlertCooldown = $true
$AlertCooldownSeconds = 300  # 5 minutes

# Enable action throttling
$EnableActionThrottling = $true
$MaxActionsPerHour = 10

# ---------- CUSTOM ACTION SCRIPTS ----------
# Define custom action scripts that can be referenced in monitors.csv
$CustomActionScripts = @{
    # "ScriptName" = { ScriptBlock }
    "ScaleUp.ps1" = {
        param($Parameters)
        Write-SelfHealingLog "Executing scale up action with parameters: $Parameters" -Level "INFO" -Component "CUSTOM"
        # Custom scaling logic here
        # Example: Increase instance count in cloud environment
        # Start-Process -FilePath "C:\Scripts\ScaleUp.exe" -ArgumentList "--count=2"
        return $true
    }
    "RestartService.ps1" = {
        param($Parameters)
        Write-SelfHealingLog "Restarting service: $Parameters" -Level "INFO" -Component "CUSTOM"
        Restart-Service -Name $Parameters -Force
        return $true
    }
}

# ---------- NOTIFICATION TEMPLATES ----------
$EmailAlertTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .critical { border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; background-color: #fde8e8; }
        .warning { border-left: 4px solid #f39c12; padding: 10px; margin: 10px 0; background-color: #fef9e7; }
        .info { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background-color: #ebf5fb; }
        .success { border-left: 4px solid #27ae60; padding: 10px; margin: 10px 0; background-color: #d5f5e3; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🤖 Advanced Self-Healing Alert</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="{Severity}">
        <h2>{Severity}: {MonitorName}</h2>
        <p><strong>Condition:</strong> {Condition}</p>
        <p><strong>Current Count:</strong> {CurrentCount}</p>
        <p><strong>Threshold:</strong> {ThresholdCount}</p>
        <p><strong>Time Window:</strong> {TimeWindowSeconds} seconds</p>
        <p><strong>Action Taken:</strong> {Action}</p>
        <p><strong>Action Result:</strong> {ActionResult}</p>
        <p><strong>Database:</strong> {DatabaseType}</p>
        <p><strong>Table:</strong> {TableName}</p>
    </div>
    <div class="info">
        <h3>Details</h3>
        <table>
            <tr>
                <td><strong>Monitor Name:</strong></td>
                <td>{MonitorName}</td>
            </tr>
            <tr>
                <td><strong>Query:</strong></td>
                <td><code>{QueryCondition}</code></td>
            </tr>
            <tr>
                <td><strong>Check Interval:</strong></td>
                <td>{CheckInterval} seconds</td>
            </tr>
            <tr>
                <td><strong>Action Type:</strong></td>
                <td>{ActionType}</td>
            </tr>
            <tr>
                <td><strong>Action Target:</strong></td>
                <td>{ActionTarget}</td>
            </tr>
        </table>
    </div>
    <div class="footer">
        <p>This is an automated alert from the Advanced Self-Healing System.</p>
        <p>Logs are available at: {LogPath}</p>
    </div>
</body>
</html>
"@

$TeamsAlertTemplate = @'
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "{ThemeColor}",
    "summary": "{Summary}",
    "sections": [{
        "activityTitle": "**{ActivityTitle}**",
        "activitySubtitle": "Monitor: {MonitorName}",
        "facts": [
            {"name": "Severity", "value": "{Severity}"},
            {"name": "Condition", "value": "{Condition}"},
            {"name": "Current Count", "value": "{CurrentCount}"},
            {"name": "Threshold", "value": "{ThresholdCount}"},
            {"name": "Time Window", "value": "{TimeWindowSeconds} seconds"},
            {"name": "Action Taken", "value": "{Action}"},
            {"name": "Action Result", "value": "{ActionResult}"},
            {"name": "Database", "value": "{DatabaseType}"},
            {"name": "Table", "value": "{TableName}"},
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

$SlackAlertTemplate = @'
{
    "channel": "{Channel}",
    "username": "{Username}",
    "icon_emoji": "{IconEmoji}",
    "attachments": [{
        "color": "{Color}",
        "title": "{Title}",
        "fields": [
            {"title": "Monitor", "value": "{MonitorName}", "short": false},
            {"title": "Severity", "value": "{Severity}", "short": true},
            {"title": "Condition", "value": "{Condition}", "short": false},
            {"title": "Current Count", "value": "{CurrentCount}", "short": true},
            {"title": "Threshold", "value": "{ThresholdCount}", "short": true},
            {"title": "Time Window", "value": "{TimeWindowSeconds} seconds", "short": true},
            {"title": "Action Taken", "value": "{Action}", "short": true},
            {"title": "Action Result", "value": "{ActionResult}", "short": true},
            {"title": "Database", "value": "{DatabaseType}", "short": true},
            {"title": "Table", "value": "{TableName}", "short": true}
        ],
        "footer": "Advanced Self-Healing System",
        "ts": {Timestamp}
    }]
}
'@