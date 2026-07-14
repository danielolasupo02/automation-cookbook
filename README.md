# Infrastructure Automation Cookbook 

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Modules](#modules)
    - [1. Server Health Report](#1-server-health-report)
    - [2. Infrastructure Monitoring](#2-infrastructure-monitoring)
    - [3. Batch Service Restart](#3-batch-service-restart)
    - [4. Basic Self-Healing (IIS)](#4-basic-self-healing-iis)
    - [5. Advanced Self-Healing (IIS + Database)](#5-advanced-self-healing-database)
    - [6. Scheduled Job Runner](#6-scheduled-job-runner)
    - [7. Log File Retention](#7-log-file-retention)
    - [8. Rollback and Failover](#8-rollback-and-failover)
- [Common Configuration](#common-configuration)
- [Installation](#installation)
- [Security](#security)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

Managing dozens or hundreds of Windows servers by hand doesn't scale. This toolkit provides eight integrated modules for infrastructure automation, monitoring, self-healing, and operations, all designed to run as Windows services via NSSM.

| # | Module | Purpose |
|---|--------|---------|
| 1 | Server Health Report | Daily CPU/memory/disk/service reports via email |
| 2 | Infrastructure Monitoring | Real-time threshold alerts (Email/Teams/Slack) |
| 3 | Batch Service Restart | Auto-restart hanging/timed-out batch services |
| 4 | Basic Self-Healing (IIS) | Recovers IIS app pools and sites |
| 5 | Advanced Self-Healing | DB-driven condition monitoring and automated actions |
| 6 | Scheduled Job Runner | Cron-like scheduler for PowerShell/Bash/Python jobs |
| 7 | Log File Retention | Automated log cleanup and archiving |
| 8 | Rollback and Failover | CI/CD-integrated deployment recovery |

---

## Architecture

```text
                         +------------------------------------------+
                         |            Jump Server                   |
                         |         (Centralized Management)         |
                         |  +----------------------------------+    |
                         |  |      Automation Toolkit          |    |
                         |  |  - Service Runner (NSSM)         |    |
                         |  |  - Configuration Manager         |    |
                         |  |  - Notification Engine           |    |
                         |  +----------------------------------+    |
                         +------------------+-----------------------+
                                            |
                             WinRM / PowerShell Remoting / HTTPS
                                            |
       +------------------------------------+-------------------------------------+
       |                                    |                                     |
+------v-------+                    +-------v--------+                    +-------v--------+
|   Web Server |                    |   App Server   |                    |   DB Server     |
|  - IIS       |                    |  - Services    |                    |  - Oracle       |
|  - Apps      |                    |  - Processes   |                    |  - SQL Server   |
+--------------+                    +----------------+                    +-----------------+
       |                                    |                                     |
       +------------------------------------+-------------------------------------+
                                            |
                              +-------------+--------------+
                              |                            |
                     Health Reports               Real-Time Alerts
                     (CSV / Excel Email)          (Email • Teams • Slack)
```

---

## Modules

### 1. Server Health Report

**Files**
```
health-report/
├── health-report.ps1
├── config.ps1
├── functions.ps1
└── servers.csv
```

**Config**
```powershell
$EmailTo = "admin@company.com; it-team@company.com"
$EmailFrom = "server-reports@company.com"
$SMTPServer = "smtp.company.com"
$SMTPPort = 587
$SMTPUseSSL = $true
$CredentialName = "SMTP_CRED"
$ReportFormat = "EXCEL"  # CSV or EXCEL
```

**servers.csv**
```csv
ServerName,IPAddress,Role,Description
SRV-WEB01,192.168.1.10,Web Server,Production Web Server
SRV-DB01,192.168.1.20,Database,Production SQL Server
```

**Usage**
```powershell
.\health-report.ps1
nssm install HealthReport powershell.exe -File health-report.ps1
```

[Back to top](#automation-cookbook-toolkit)

---

### 2. Infrastructure Monitoring

Real-time threshold-based monitoring with multi-channel alerts, circuit breaker, and parallel scanning.

**Files**
```
infrastructure-monitor/
├── monitor-service.ps1
├── config.ps1
├── functions.ps1
└── servers.txt
```

**Config**
```powershell
$MonitoringInterval = 60
$SummaryReportInterval = 60
$AlertCooldown = 300
$MinAlertSeverity = 2  # WARNING and above

$GlobalThresholds = @{
    CPU_Threshold = 80
    Memory_Threshold = 85
    Disk_Threshold = 90
    Network_Threshold = 70
}

$EmailConfig = @{ Enabled = $true; SMTPServer = "smtp.company.com"; Port = 587; UseSSL = $true; From = "monitoring@company.com"; To = "admin@company.com"; CredentialName = "MONITOR_EMAIL_CRED"; MinSeverity = "WARNING" }
$TeamsConfig = @{ Enabled = $true; WebhookURLs = @("https://company.webhook.office.com/xxxxx"); MinSeverity = "INFO" }
$SlackConfig = @{ Enabled = $true; WebhookURLs = @("https://hooks.slack.com/services/xxxxx"); Channel = "#alerts"; Username = "Infrastructure Monitor"; MinSeverity = "WARNING" }
```

**servers.txt** — one server per line (hostname or IP)

**Alert cooldown** prevents flooding by waiting a configurable period before repeating the same alert.

[Back to top](#automation-cookbook-toolkit)

---

### 3. Batch Service Restart

Detects and restarts batch services or processes that hang or time out.

**Files**
```
batch-service-restart/
├── service-restart.ps1
├── config.ps1
├── functions.ps1
├── services.csv
├── batch-scripts/
├── install-service.ps1
└── uninstall-service.ps1
```

**services.csv**
```csv
Name,Type,DisplayName,FilePath,WorkingDirectory,Arguments,CheckInterval,TimeoutThreshold,MaxRestarts,RestartDelay,HealthCheck,ActionOnFailure,LogOutput
BatchProcessor,Process,Batch Data Processor,C:\BatchScripts\processor.bat,C:\BatchScripts,/run:data,60,3600,5,30,"Get-Process -Name *batch*",Restart,true
```

**Key fields**
- **TimeoutThreshold** – max runtime before restart
- **MaxRestarts** – daily restart cap to avoid loops
- **HealthCheck** – optional post-restart verification
- **LogOutput** – captures stdout/stderr

[Back to top](#automation-cookbook-toolkit)

---

### 4. Basic Self-Healing (IIS)

Monitors and restarts IIS application pools/sites when unhealthy.

**Files**
```
iis-selfhealing/
├── iis-selfhealing.ps1
├── config.ps1
├── functions.ps1
├── applications.csv
├── install-service.ps1
└── uninstall-service.ps1
```

**applications.csv**
```csv
SiteName,ApplicationPath,CheckInterval,RestartMethod,HealthCheckURL,ExpectedResponse,MaxRestarts,ActionOnFailure
MyWebsite,/MyApp,60,AppPool,http://localhost/MyApp/health,OK,5,Restart
```

**Config**
```powershell
$MasterCheckInterval = 30
$PostRestartWaitTime = 10
$HealthCheckRetries = 3
$UseRecycling = $true
$GlobalMaxRestartsPerDay = 10
```

**Restart methods:** `AppPool` / `ApplicationPool` (same), `Site`, `All` (site + pool)

[Back to top](#automation-cookbook-toolkit)

---

### 5. Advanced Self-Healing (Database)

Monitors database tables for defined conditions and triggers automated actions — e.g., restart an IIS service if pending OTP requests exceed a threshold.

**Supports:** Oracle, SQL Server, MySQL, PostgreSQL, SQLite

**Files**
```
advanced-selfhealing/
├── advanced-selfhealing.ps1
├── config.ps1
├── functions.ps1
├── monitors.csv
├── install-service.ps1
└── uninstall-service.ps1
```

**monitors.csv**
```csv
MonitorName,DatabaseType,ConnectionString,TableName,QueryCondition,CheckInterval,ThresholdCount,TimeWindowSeconds,ConditionOperator,ActionType,ActionTarget,ActionParameters,Severity,Enabled
OTP_Monitor,Oracle,Data Source=ORCL;User Id={USER};Password={PASSWORD};,OTP_REQUESTS,"status='PENDING' AND created_date > SYSDATE - 2/1440",60,100,120,GreaterThan,RestartIIS,MyWebsite/OTPService,RestartAppPool,CRITICAL,true
```

**Connection strings**
```text
Oracle:     Data Source=ORCL;User Id={USER};Password={PASSWORD};
SQL Server: Server=localhost;Database=MyDB;User Id={USER};Password={PASSWORD};
MySQL:      Server=localhost;Database=MyDB;Uid={USER};Pwd={PASSWORD};
PostgreSQL: Host=localhost;Database=MyDB;Username={USER};Password={PASSWORD};
SQLite:     Data Source=C:\Data\MyDB.db;Version=3;
```

**Action types:** `RestartIIS`, `EmailAlert`, `TeamsAlert`, `SlackAlert`, `ExecuteScript`, `ExecuteSQL`

[Back to top](#automation-cookbook-toolkit)

---

### 6. Scheduled Job Runner

Runs scheduled jobs without depending on Task Scheduler, with retries, timeouts, and locking.

**Files**
```
scheduled-job-runner/
├── job-runner.ps1
├── config.ps1
├── functions.ps1
├── jobs.csv
├── install-service.ps1
└── uninstall-service.ps1
```

**jobs.csv**
```csv
JobName,JobType,ScriptPath,Parameters,Schedule,ScheduleDetails,Enabled,RetryCount,RetryDelay,Timeout,NotificationEmail
DailyBusinessReport,PowerShell,C:\Scripts\DailyReport.ps1,"-Format HTML -SendEmail",Daily,08:00,true,3,60,300,admin@company.com
```

**Schedule formats**
```text
Daily:   HH:mm            e.g. 08:00
Weekly:  Day,HH:mm        e.g. Monday,08:00
Monthly: Day,HH:mm        e.g. 15,08:00
Yearly:  MM,DD,HH:mm      e.g. 01,01,00:00
Hourly:  Minutes          e.g. 30
Custom:  Cron expression  e.g. 0 8 * * 1-5
```

**Cron examples**
```text
0 8 * * *      Every day at 8:00 AM
0 8 * * 1-5    Weekdays at 8:00 AM
*/15 * * * *   Every 15 minutes
0 0 1 * *      1st of the month at midnight
```

[Back to top](#automation-cookbook-toolkit)

---

### 7. Log File Retention

Deletes, archives, compresses, or moves log files by retention policy, with safety checks against critical files.

**Files**
```
log-retention/
├── log-retention.ps1
├── config.ps1
├── functions.ps1
├── retention-policies.csv
├── install-service.ps1
└── uninstall-service.ps1
```

**retention-policies.csv**
```csv
PolicyName,Path,Pattern,RetentionPeriod,RetentionUnit,Action,ArchivePath,Compress,ExcludePatterns,Enabled,NotifyOnAction
ApplicationLogs,C:\Logs\Apps,*.log,30,Days,Delete,,false,*,true,true
IISLogs,C:\inetpub\logs\LogFiles,W3SVC*.log,90,Days,Archive,C:\Archives\IISLogs,false,*,true,true
```

**Safety features**
```powershell
$ProtectedFolders  = @("C:\Windows", "C:\Program Files", "C:\Program Files (x86)")
$ProtectedPatterns = @("*.exe", "*.dll", "*.sys")
$MinimumFreeSpaceMB = 1024
$DryRunMode = $true   # test policies without deleting anything
```

[Back to top](#automation-cookbook-toolkit)

---

### 8. Rollback and Failover

Automates deployment rollback and failover, integrated with CI/CD pipelines.

**Files**
```
rollback-failover/
├── rollback-failover.ps1
├── config.ps1
├── functions.ps1
├── deployment-policies.csv
├── rollback-scripts/
├── install-service.ps1
└── uninstall-service.ps1
```

**deployment-policies.csv**
```csv
PolicyName,DeploymentType,DeploymentPath,HealthCheckURL,ExpectedResponse,RollbackScript,FailoverScript,MaxRetries,RetryInterval,CheckInterval,TimeoutSeconds,AlertEmail,Enabled
WebApp_Deployment,WebApp,C:\Deployments\WebApp,http://localhost/WebApp/health,OK,C:\Rollback\webapp-rollback.ps1,C:\Failover\webapp-failover.ps1,3,60,60,300,admin@company.com,true
```

**Sample rollback script**
```powershell
param([string]$PolicyName, [string]$DeploymentPath, [string]$DeploymentStatus)

$BackupPath = "$DeploymentPath.backup"
if (Test-Path $BackupPath) {
    Remove-Item -Path "$DeploymentPath\*" -Recurse -Force
    Copy-Item -Path "$BackupPath\*" -Destination $DeploymentPath -Recurse -Force
    exit 0
} else {
    exit 1
}
```

**CI/CD (Azure DevOps) example**
```yaml
- task: PowerShell@2
  displayName: 'Monitor Deployment'
  inputs:
    filePath: 'monitor-deployment.ps1'
    arguments: '-PolicyName "WebApp_Deployment"'
    pwsh: true
```

[Back to top](#automation-cookbook-toolkit)

---

## Common Configuration

All modules use Windows Credential Manager for secure credential storage — no passwords in scripts or config files.

```cmd
cmdkey /add:SMTP_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:MONITOR_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:SERVICE_RESTART_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:IIS_HEALING_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:SELF_HEALING_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:DB_ORACLE_CRED /user:oracle_user /pass:YourPassword
cmdkey /add:DB_SQLSERVER_CRED /user:sql_user /pass:YourPassword
cmdkey /add:DB_MYSQL_CRED /user:mysql_user /pass:YourPassword
cmdkey /add:DB_POSTGRESQL_CRED /user:postgres_user /pass:YourPassword
cmdkey /add:JOB_RUNNER_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:LOG_RETENTION_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword
cmdkey /add:ROLLBACK_FAILOVER_EMAIL_CRED /user:your-email@domain.com /pass:YourPassword

cmdkey /list   # verify
```

[Back to top](#automation-cookbook-toolkit)

---

## Installation

**Prerequisites**
- PowerShell 5.1+ / WMF 5.1+
- Administrative privileges
- WinRM enabled for remote monitoring

**Modules**
```powershell
Install-Module -Name CredentialManager -Scope CurrentUser -Force
Install-Module -Name ImportExcel -Scope CurrentUser -Force

# Database libraries (Advanced Self-Healing)
Install-Module -Name Oracle.ManagedDataAccess -Scope CurrentUser -Force
Install-Module -Name MySql.Data -Scope CurrentUser -Force
Install-Module -Name Npgsql -Scope CurrentUser -Force
# SQLite is built into .NET
```

**NSSM setup**
1. Download NSSM from https://nssm.cc/download
2. Place `nssm.exe` in each module's script directory
3. Run as Administrator: `.\install-service.ps1`

**Service management**
```cmd
nssm start ServiceName
nssm stop ServiceName
nssm restart ServiceName
nssm status ServiceName
nssm edit ServiceName
```

**Service names**

| Module | Service Name |
|--------|--------------|
| Server Health Report | HealthReport |
| Infrastructure Monitoring | InfrastructureMonitor |
| Batch Service Restart | BatchServiceRestart |
| Basic Self-Healing (IIS) | IISSelfHealing |
| Advanced Self-Healing | AdvancedSelfHealing |
| Scheduled Job Runner | ScheduledJobRunner |
| Log File Retention | LogRetention |
| Rollback and Failover | RollbackFailover |

[Back to top](#automation-cookbook-toolkit)

---

## Security

- Credentials stored only in Windows Credential Manager, never in scripts or config
- Run services under least-privilege dedicated accounts; restrict interactive logon
- Use WinRM over HTTPS (5986) in production; restrict access with firewall rules
- Use SSL/TLS for SMTP
- Restrict script directory permissions via NTFS; audit configuration changes
- Enable logging with rotation; review regularly

[Back to top](#automation-cookbook-toolkit)

---

## Performance Tuning

**General:** tune check intervals by criticality, use parallel processing, enable circuit breakers, cache state where possible.

```powershell
# Infrastructure Monitoring
$MasterCheckInterval = 60
$EnableParallelMonitoring = $true
$MaxParallelThreads = 10
$EnableCounterCaching = $true
$CounterCacheDuration = 30

# Batch Service Restart
$MasterCheckInterval = 30
$MaxConcurrentRestarts = 3
$EnableParallelChecking = $true
$MaxParallelChecks = 5

# Advanced Self-Healing
$MasterCheckInterval = 30
$EnableParallelMonitoring = $true
$MaxParallelMonitors = 10
$EnableCircuitBreaker = $true
$CircuitBreakerFailureThreshold = 5

# Scheduled Job Runner
$MasterCheckInterval = 30
$EnableParallelExecution = $true
$MaxConcurrentJobs = 5
$EnableJobLocking = $true

# Log Retention
$MasterCheckInterval = 3600
$EnableParallelProcessing = $true
$MaxParallelThreads = 5
$MaxFilesPerScan = 10000
```

[Back to top](#automation-cookbook-toolkit)

---

## Troubleshooting

**Service won't start**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\module-name.ps1   # test manually
Get-EventLog -LogName Application -Source "ServiceName" -Newest 10
nssm status ServiceName
```

**Credential issues**
```cmd
cmdkey /list | findstr CRED_NAME
cmdkey /delete:CRED_NAME
cmdkey /add:CRED_NAME /user:username /pass:password
```

**Remote connection issues**
```powershell
Test-WSMan -ComputerName SRV-WEB01
Enable-PSRemoting -Force
New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
```

**Performance issues:** increase check intervals, reduce parallel threads, enable circuit breakers, monitor with Performance Monitor.

**Notification testing**
```powershell
# Email
Send-MailMessage -To "test@company.com" -From "sender@company.com" -Subject "Test" -Body "Test" -SmtpServer "smtp.company.com" -Port 587 -UseSsl

# Teams / Slack
$Body = '{"text":"Test message"}'
Invoke-RestMethod -Uri "https://company.webhook.office.com/xxxxx" -Method Post -Body $Body -ContentType 'application/json'
```

**Log locations**

| Module | Path |
|--------|------|
| Health Report | `C:\ServerReports\Logs\` |
| Infrastructure Monitor | `C:\InfrastructureMonitor\Logs\` |
| Batch Service Restart | `C:\BatchServiceRestart\Logs\` |
| IIS Self-Healing | `C:\IISSelfHealing\Logs\` |
| Advanced Self-Healing | `C:\AdvancedSelfHealing\Logs\` |
| Scheduled Job Runner | `C:\ScheduledJobRunner\Logs\` |
| Log Retention | `C:\LogRetention\Logs\` |
| Rollback/Failover | `C:\RollbackFailover\Logs\` |

[Back to top](#automation-cookbook-toolkit)

---

## Roadmap

- **Phase 1 (done):** Health Report, Infrastructure Monitoring, config framework, NSSM/Credential Manager integration
- **Phase 2 (done):** Batch Service Restart, IIS Self-Healing, Advanced Self-Healing
- **Phase 3 (done):** Scheduled Job Runner, Log Retention, Rollback/Failover
- **Phase 4 (planned):** Web dashboard, API integration, anomaly detection via ML, Linux support, containerized deployment

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test thoroughly
4. Update this README if behavior changes
5. Submit a pull request
# License

MIT License

---

**Author:** Daniel Olasupo (danielolasupo02@gmail.com)

If you find this project useful, consider ⭐ starring the repository and contributing improvements through pull requests.
