# ============================================================
# ROLLBACK & FAILOVER - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# rollback and failover automation service.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to deployment-policies.csv file
$PoliciesCSVPath = ".\deployment-policies.csv"

# Master check interval (seconds)
$MasterCheckInterval = 30  # Check every 30 seconds

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\RollbackFailover\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- DEPLOYMENT SETTINGS ----------
# Deployment status file location
$DeploymentStatusPath = "C:\RollbackFailover\DeploymentStatus"

# Maximum concurrent deployments
$MaxConcurrentDeployments = 3

# Deployment timeout (seconds)
$DeploymentTimeout = 600

# Enable parallel processing
$EnableParallelProcessing = $true
$MaxParallelThreads = 5

# ---------- ROLLBACK SETTINGS ----------
# Automatic rollback on failure
$EnableAutoRollback = $true

# Rollback timeout (seconds)
$RollbackTimeout = 300

# Number of rollback retries
$RollbackRetries = 3

# Rollback retry interval (seconds)
$RollbackRetryInterval = 60

# ---------- FAILOVER SETTINGS ----------
# Enable automatic failover
$EnableAutoFailover = $true

# Failover timeout (seconds)
$FailoverTimeout = 300

# Failover validation checks
$EnableFailoverValidation = $true
$FailoverValidationRetries = 3
$FailoverValidationInterval = 30

# ---------- NOTIFICATION SETTINGS ----------
# Enable notifications
$EnableNotifications = $true

# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "rollback-failover@yourcompany.com"
    To = "admin@yourcompany.com; devops@yourcompany.com"
    CredentialName = "ROLLBACK_FAILOVER_EMAIL_CRED"
}

# Teams Configuration
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx"
    )
    MinSeverity = "WARNING"
}

# Slack Configuration
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX"
    )
    Channel = "#deployment-alerts"
    Username = "Rollback/Failover System"
    IconEmoji = ":warning:"
    MinSeverity = "WARNING"
}

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance tracking
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\RollbackFailover\Performance"

# Enable state persistence
$EnableStatePersistence = $true
$StatePath = "C:\RollbackFailover\State"

# ---------- ADVANCED SETTINGS ----------
# Enable health check before deployment
$EnablePreDeploymentHealthCheck = $true

# Enable deployment validation
$EnableDeploymentValidation = $true
$ValidationTimeout = 60

# Enable circuit breaker
$EnableCircuitBreaker = $true
$CircuitBreakerFailureThreshold = 3
$CircuitBreakerTimeout = 1800  # 30 minutes

# ---------- NOTIFICATION TEMPLATES ----------
$EmailNotificationTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .success { border-left: 4px solid #27ae60; padding: 10px; margin: 10px 0; background-color: #d5f5e3; }
        .warning { border-left: 4px solid #f39c12; padding: 10px; margin: 10px 0; background-color: #fef9e7; }
        .error { border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; background-color: #fde8e8; }
        .critical { border-left: 4px solid #c0392b; padding: 10px; margin: 10px 0; background-color: #fadbd8; }
        .info { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background-color: #ebf5fb; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
        .status-badge { display: inline-block; padding: 3px 8px; border-radius: 3px; color: white; font-weight: bold; }
        .badge-success { background-color: #27ae60; }
        .badge-warning { background-color: #f39c12; }
        .badge-error { background-color: #e74c3c; }
        .badge-critical { background-color: #c0392b; }
        .badge-info { background-color: #3498db; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔄 Rollback & Failover Report</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="{SeverityClass}">
        <h2><span class="status-badge badge-{SeverityBadge}">{Severity}</span> {EventType}</h2>
        <p><strong>Policy:</strong> {PolicyName}</p>
        <p><strong>Deployment Type:</strong> {DeploymentType}</p>
        <p><strong>Deployment Path:</strong> {DeploymentPath}</p>
        <p><strong>Status:</strong> <span class="status-badge badge-{StatusBadge}">{Status}</span></p>
    </div>
    <div class="info">
        <h3>Details</h3>
        <table>
            <tr>
                <td><strong>Start Time:</strong></td>
                <td>{StartTime}</td>
            </tr>
            <tr>
                <td><strong>End Time:</strong></td>
                <td>{EndTime}</td>
            </tr>
            <tr>
                <td><strong>Duration:</strong></td>
                <td>{Duration} seconds</td>
            </tr>
            <tr>
                <td><strong>Attempts:</strong></td>
                <td>{Attempts}</td>
            </tr>
            <tr>
                <td><strong>Action Taken:</strong></td>
                <td>{ActionTaken}</td>
            </tr>
            <tr>
                <td><strong>Action Result:</strong></td>
                <td>{ActionResult}</td>
            </tr>
        </table>
    </div>
    {DetailedOutput}
    <div class="footer">
        <p>This is an automated notification from the Rollback & Failover System.</p>
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
        "activitySubtitle": "Policy: {PolicyName}",
        "facts": [
            {"name": "Event", "value": "{EventType}"},
            {"name": "Status", "value": "{Status}"},
            {"name": "Deployment Type", "value": "{DeploymentType}"},
            {"name": "Action Taken", "value": "{ActionTaken}"},
            {"name": "Action Result", "value": "{ActionResult}"},
            {"name": "Duration", "value": "{Duration} seconds"},
            {"name": "Attempts", "value": "{Attempts}"},
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
            {"title": "Event", "value": "{EventType}", "short": false},
            {"title": "Policy", "value": "{PolicyName}", "short": true},
            {"title": "Status", "value": "{Status}", "short": true},
            {"title": "Deployment Type", "value": "{DeploymentType}", "short": true},
            {"title": "Action Taken", "value": "{ActionTaken}", "short": true},
            {"title": "Action Result", "value": "{ActionResult}", "short": true},
            {"title": "Duration", "value": "{Duration} seconds", "short": true},
            {"title": "Attempts", "value": "{Attempts}", "short": true}
        ],
        "footer": "Rollback & Failover System",
        "ts": {Timestamp}
    }]
}
'@