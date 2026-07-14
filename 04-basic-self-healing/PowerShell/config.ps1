# ============================================================
# IIS SELF-HEALING - CONFIGURATION FILE
# ============================================================
#
# This file contains all configuration settings for the
# IIS self-healing automation.
# ============================================================

# ---------- GENERAL SETTINGS ----------
# Path to applications.csv file
$ApplicationsCSVPath = ".\applications.csv"

# How often to check all applications (seconds)
# This is the master loop interval
$MasterCheckInterval = 30  # Check every 30 seconds

# Enable/disable logging
$EnableLogging = $true
$LogPath = "C:\IISSelfHealing\Logs"
$LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
$LogRotationSizeMB = 10

# ---------- IIS SETTINGS ----------
# IIS server name (use localhost for local IIS)
$IISServerName = "localhost"

# Web management service (WMSVC) settings
$UseWMI = $true  # Use WMI for IIS management (recommended)
$UseWebAdministration = $true  # Use WebAdministration module

# ---------- RESTART SETTINGS ----------
# Time to wait after restart before health check (seconds)
$PostRestartWaitTime = 10

# Number of health check retries after restart
$HealthCheckRetries = 3

# Time between health check retries (seconds)
$HealthCheckRetryInterval = 5

# Maximum concurrent restarts
$MaxConcurrentRestarts = 2

# ---------- NOTIFICATION SETTINGS ----------
# Enable email notifications for restarts
$EnableEmailNotifications = $true

# Email Configuration
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.yourcompany.com"
    Port = 587
    UseSSL = $true
    From = "iis-healing@yourcompany.com"
    To = "admin@yourcompany.com"
    CredentialName = "IIS_HEALING_EMAIL_CRED"
}

# ---------- PERFORMANCE SETTINGS ----------
# Enable performance tracking (log restart history)
$EnablePerformanceTracking = $true
$PerformanceDataPath = "C:\IISSelfHealing\Performance"

# Enable parallel checking of applications
$EnableParallelChecking = $true
$MaxParallelChecks = 10

# ---------- ADVANCED SETTINGS ----------
# Enable application pool recycling instead of stop/start
$UseRecycling = $true

# Enable IIS reset as last resort
$EnableIISResetFallback = $false

# Maximum restarts per application per day
$GlobalMaxRestartsPerDay = 10

# ---------- CUSTOM HEALTH CHECK SCRIPTS ----------
# Define custom health check scripts for specific applications
# These will override the HealthCheckURL check
$CustomHealthChecks = @{
    # "SiteName/ApplicationPath" = { ScriptBlock returning $true/$false }
    # Example:
    # "MyWebsite/MyApp" = {
    #     # Custom health check logic
    #     try {
    #         $response = Invoke-WebRequest -Uri "http://localhost/MyApp/status" -UseBasicParsing -TimeoutSec 5
    #         return $response.Content -match "OK"
    #     }
    #     catch {
    #         return $false
    #     }
    # }
}

# ---------- LOGGING TEMPLATES ----------
# Email notification template
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
        <h1>🔄 IIS Self-Healing Notification</h1>
        <p>Time: {Timestamp}</p>
    </div>
    <div class="{Severity}">
        <h2>{Action} Performed</h2>
        <p><strong>Site:</strong> {SiteName}</p>
        <p><strong>Application:</strong> {ApplicationPath}</p>
        <p><strong>Action:</strong> {Action}</p>
        <p><strong>Result:</strong> {Result}</p>
        <p><strong>Reason:</strong> {Reason}</p>
        <p><strong>Restart Count (24h):</strong> {RestartCount}</p>
    </div>
    <div class="info">
        <h3>Details</h3>
        <table>
            <tr>
                <td><strong>Check Interval:</strong></td>
                <td>{CheckInterval} seconds</td>
            </tr>
            <tr>
                <td><strong>Health Check URL:</strong></td>
                <td>{HealthCheckURL}</td>
            </tr>
            <tr>
                <td><strong>Expected Response:</strong></td>
                <td>{ExpectedResponse}</td>
            </tr>
            <tr>
                <td><strong>Max Restarts:</strong></td>
                <td>{MaxRestarts}</td>
            </tr>
        </table>
    </div>
    <div class="footer">
        <p>This is an automated notification from the IIS Self-Healing System.</p>
        <p>Logs are available at: {LogPath}</p>
    </div>
</body>
</html>
"@