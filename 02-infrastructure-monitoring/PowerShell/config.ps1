# ============================================================
# INFRASTRUCTURE MONITOR - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# infrastructure monitoring service.
# ============================================================

# ---------- SERVER SETTINGS ----------
# Path to server list file (one server per line)
$ServerListPath = ".\servers.txt"

# Global threshold settings (applied to all servers)
# Individual overrides can be defined in $ServerOverrides
$GlobalThresholds = @{
    CPU_Threshold = 80          # Percentage
    Memory_Threshold = 85       # Percentage
    Disk_Threshold = 90         # Percentage used
    Network_Threshold = 70      # MB/s
}

# Server-specific overrides (optional)
# Key = ServerName, Value = Hashtable of overrides
$ServerOverrides = @{
    "SRV-DB01" = @{
        CPU_Threshold = 70
        Memory_Threshold = 80
        Disk_Threshold = 85
        Network_Threshold = 50
        CustomServices = @("MSSQLSERVER", "SQLSERVERAGENT")
    }
    "SRV-EXCH01" = @{
        CPU_Threshold = 75
        Memory_Threshold = 85
        CustomServices = @("MSExchangeIS", "MSExchangeTransport")
    }
    "192.168.1.60" = @{
        CPU_Threshold = 65
        Memory_Threshold = 70
        Disk_Threshold = 85
    }
}

# Services to monitor (global list, can be overridden per server)
$GlobalServicesToMonitor = @(
    "W3SVC",          # IIS Web Server
    "IISADMIN",       # IIS Admin
    "LanmanServer",   # File Server
    "LanmanWorkstation", # Workstation
    "NTDS",           # Active Directory
    "DNS",            # DNS Server
    "KDC",            # Kerberos
    "DhcpServer",     # DHCP
    "Spooler",        # Print Spooler
    "WinRM"           # Windows Remote Management
)

# ---------- MONITORING SETTINGS ----------
# How often to check health (in seconds)
$MonitoringInterval = 60  # Check every 60 seconds

# How often to send summary reports (in minutes)
$SummaryReportInterval = 60  # Send every 60 minutes

# Enable/disable different monitoring components
$EnableCPU = $true
$EnableMemory = $true
$EnableDisk = $true
$EnableNetwork = $true
$EnableServices = $true
$EnableCustomEndpoints = $true

# Performance counter collection timeout (seconds)
$CounterTimeout = 10

# Number of retry attempts for failed connections
$MaxRetryAttempts = 3
$RetryDelay = 5  # Seconds between retries

# ---------- ALERT SETTINGS ----------
# Enable/disable alerting
$EnableAlerts = $true

# Alert cooldown period (seconds) - prevents alert spam
$AlertCooldown = 300  # 5 minutes

# Alert severity levels
$AlertSeverities = @{
    'INFO' = 1
    'WARNING' = 2
    'CRITICAL' = 3
    'ERROR' = 4
}

# Minimum severity to send alerts (1=INFO, 2=WARNING, 3=CRITICAL, 4=ERROR)
$MinAlertSeverity = 2  # WARNING and above

# ---------- NOTIFICATION SETTINGS ----------
# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "monitoring@yourcompany.com"
    To = "admin@yourcompany.com; it-team@yourcompany.com"
    CredentialName = "MONITOR_EMAIL_CRED"

    # Send only critical alerts via email
    MinSeverity = "WARNING"
}

# Microsoft Teams Configuration
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx/yyyyy",  # General
        "https://yourcompany.webhook.office.com/webhookb2/xxxxx/zzzzz"   # Critical
    )
    # Send all alerts to Teams
    MinSeverity = "INFO"
}

# Slack Configuration
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXX",  # General
        "https://hooks.slack.com/services/TXXXXX/BXXXXX/YYYYY"   # Critical
    )
    Channel = "#infrastructure-alerts"
    Username = "Infrastructure Monitor"
    IconEmoji = ":warning:"
    MinSeverity = "WARNING"
}

# ---------- DATA STORAGE SETTINGS ----------
# Store metrics for historical analysis
$EnableMetricsStorage = $true
$MetricsStoragePath = "C:\InfrastructureMonitor\Metrics"
$MetricsRetentionDays = 30

# Store alert history
$AlertHistoryPath = "C:\InfrastructureMonitor\Alerts"
$AlertHistoryRetentionDays = 90

# ---------- LOGGING SETTINGS ----------
$EnableLogging = $true
$LogPath = "C:\InfrastructureMonitor\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- SERVICE SETTINGS ----------
$ServiceName = "InfrastructureMonitorService"
$ServiceDisplayName = "Infrastructure Health Monitor Service"
$ServiceDescription = "Continuously monitors server health and sends alerts"

# ---------- ADVANCED SETTINGS ----------
# Enable parallel monitoring
$EnableParallelMonitoring = $true
$MaxParallelThreads = 10

# Circuit breaker pattern
$EnableCircuitBreaker = $true
$CircuitBreakerFailureThreshold = 5
$CircuitBreakerTimeout = 300  # Seconds

# ---------- HEALTH CHECK ENDPOINTS ----------
$CustomEndpoints = @(
    @{Server="SRV-WEB01"; URL="http://192.168.1.10/health"; ExpectedResponse="OK"; Port=80}
    @{Server="SRV-APP01"; URL="http://192.168.1.40/api/health"; ExpectedResponse="Healthy"; Port=8080}
    @{Server="SRV-DB01"; URL="http://192.168.1.20/db-health"; ExpectedResponse="Connected"; Port=1433}
)

# ---------- NOTIFICATION TEMPLATES ----------
# Email template (HTML)
$EmailAlertTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .alert { padding: 15px; margin: 10px 0; border-left: 4px solid #3498db; }
        .critical { border-left-color: #e74c3c; background-color: #fde8e8; }
        .warning { border-left-color: #f39c12; background-color: #fef9e7; }
        .info { border-left-color: #3498db; background-color: #ebf5fb; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #34495e; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { font-size: 12px; color: #7f8c8d; margin-top: 20px; border-top: 1px solid #ddd; padding-top: 10px; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 3px; color: white; font-weight: bold; }
        .badge-critical { background-color: #e74c3c; }
        .badge-warning { background-color: #f39c12; }
        .badge-info { background-color: #3498db; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚨 Infrastructure Health Alert</h1>
        <p>Alert triggered at: {AlertTime}</p>
    </div>
    <div class="alert {Severity}">
        <h2><span class="badge badge-{Severity}">{Severity}</span> {AlertType} Alert</h2>
        <p><strong>Server:</strong> {ServerName}</p>
        <p><strong>Message:</strong> {Message}</p>
        <p><strong>Current Value:</strong> {Value}</p>
        <p><strong>Threshold:</strong> {Threshold}</p>
    </div>
    <div class="summary">
        <h3>Server Status Summary</h3>
        <table>
            <tr>
                <td><strong>Status:</strong></td>
                <td>{Status}</td>
            </tr>
            <tr>
                <td><strong>Last Check:</strong></td>
                <td>{LastCheck}</td>
            </tr>
            <tr>
                <td><strong>CPU Usage:</strong></td>
                <td>{CPU_Usage}</td>
            </tr>
            <tr>
                <td><strong>Memory Usage:</strong></td>
                <td>{Memory_Usage}</td>
            </tr>
            <tr>
                <td><strong>Disk Usage:</strong></td>
                <td>{Disk_Usage}</td>
            </tr>
        </table>
    </div>
    <div class="footer">
        <p>This is an automated alert from the Infrastructure Health Monitoring System.</p>
        <p>To acknowledge or resolve this alert, check the monitoring dashboard.</p>
    </div>
</body>
</html>
"@

# Teams message template
$TeamsAlertTemplate = @'
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "{ThemeColor}",
    "summary": "{Summary}",
    "sections": [{
        "activityTitle": "{ActivityTitle}",
        "activitySubtitle": "Server: {ServerName}",
        "facts": [
            {"name": "Severity", "value": "{Severity}"},
            {"name": "Alert Type", "value": "{AlertType}"},
            {"name": "Message", "value": "{Message}"},
            {"name": "Current Value", "value": "{Value}"},
            {"name": "Threshold", "value": "{Threshold}"},
            {"name": "Time", "value": "{AlertTime}"}
        ],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View Dashboard",
        "targets": [{ "os": "default", "uri": "{DashboardURL}" }]
    }]
}
'@

# Slack message template
$SlackAlertTemplate = @'
{
    "channel": "{Channel}",
    "username": "{Username}",
    "icon_emoji": "{IconEmoji}",
    "attachments": [{
        "color": "{Color}",
        "title": "{Title}",
        "title_link": "{DashboardURL}",
        "fields": [
            {"title": "Server", "value": "{ServerName}", "short": false},
            {"title": "Severity", "value": "{Severity}", "short": true},
            {"title": "Alert Type", "value": "{AlertType}", "short": true},
            {"title": "Message", "value": "{Message}", "short": false},
            {"title": "Current Value", "value": "{Value}", "short": true},
            {"title": "Threshold", "value": "{Threshold}", "short": true}
        ],
        "footer": "Infrastructure Health Monitor",
        "ts": {Timestamp}
    }]
}
'@