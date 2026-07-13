# 🖥️ Automation Cookbook Toolkit

> A PowerShell-based automation solution for Windows environments.

This toolkit consists of two complementary solutions:

- 📊 **Daily Server Health Report** – Generates scheduled CPU, Memory, and Disk utilization reports and emails them as CSV or Excel.
- 🚨 **Infrastructure Health Monitor Service** – Runs continuously as a Windows Service, monitors infrastructure health, and sends alerts through Email, Microsoft Teams, and Slack.

---

## 📑 Table of Contents

- [Overview](#overview)
- [Solution Architecture](#solution-architecture)

### Part I — Daily Server Health Report
- [Features](#daily-server-health-report)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Running the Script](#running-the-script)
- [Scheduling](#scheduling)
- [Output](#output)
- [Customization](#customization)
- [Troubleshooting](#daily-report-troubleshooting)

### Part II — Infrastructure Health Monitor Service
- [Overview](#infrastructure-health-monitor-service)
- [Features](#service-features)
- [Installation](#installation)
- [Configuration Guide](#configuration-guide)
- [Service Management](#service-management)
- [Testing](#testing)
- [Troubleshooting](#service-troubleshooting)
- [Security Considerations](#security-considerations)
- [Performance Tuning](#performance-tuning)

- [Project Roadmap](#project-roadmap)
- [License](#license)

---

# Overview

Managing dozens (or hundreds) of Windows servers manually is inefficient.

This toolkit automates infrastructure monitoring by providing:

- Daily scheduled health reports
- Real-time monitoring
- Threshold-based alerting
- Historical metrics collection
- Multi-channel notifications
- Centralized monitoring from a jump server

---

# Solution Architecture

```text
                         +----------------------+
                         |   Jump Server        |
                         | PowerShell Monitor   |
                         +----------+-----------+
                                    |
                     WinRM / PowerShell Remoting
                                    |
       +----------------------------+----------------------------+
       |                            |                            |
+--------------+             +--------------+             +--------------+
| WEB SERVER   |             | APP SERVER   |             | DB SERVER    |
+--------------+             +--------------+             +--------------+
       |                            |                            |
       +----------------------------+----------------------------+
                                    |
                         Metrics Collection
                                    |
                    +---------------+----------------+
                    |                                |
              Daily Reports                  Real-Time Alerts
                    |                                |
          CSV / Excel Email          Email • Teams • Slack
```

---

# Part I — Daily Server Health Report

Generate scheduled reports showing CPU, Memory, and Disk utilization across multiple Windows servers.

Designed to run daily from a central Jump Server.

---

## Features

- Monitor multiple Windows servers
- CPU utilization
- Memory utilization
- Disk usage
- Email reports
- CSV export
- Excel export
- Windows Credential Manager support
- Logging
- Windows Task Scheduler compatible

⬆️ [Back to Table of Contents](#-table-of-contents)

---

## Prerequisites

### Jump Server

- Windows PowerShell 5.1+
- WinRM enabled
- Administrator permissions
- Network connectivity to monitored servers

### Target Servers

- WinRM enabled

```powershell
Enable-PSRemoting -Force
```

### Optional

Install Excel export support.

```powershell
Install-Module ImportExcel -Scope CurrentUser
```

⬆️ [Back to Table of Contents](#-table-of-contents)

---

## Project Structure

```text
ServerReports/

├── health-report.ps1
├── config.ps1
├── functions.ps1
├── servers.csv
├── Logs/
├── Reports/
└── README.md
```

---

## Configuration

### Configure Email

Edit **config.ps1**

```powershell
$EmailTo = "admin@company.com"
$EmailFrom = "monitor@company.com"

$SMTPServer = "smtp.company.com"
$SMTPPort = 587

$ReportFormat = "EXCEL"

$CredentialName = "SMTP_CRED"
```

---

### Configure Servers

Edit **servers.csv**

```csv
ServerName,IPAddress,Role
SRV-WEB01,192.168.1.10,Web
SRV-APP01,192.168.1.15,Application
SRV-DB01,192.168.1.20,Database
```

---

### Store SMTP Credentials

```cmd
cmdkey /add:SMTP_CRED /user:smtp-user@company.com /pass:YourPassword
```

---

## Running the Script

```powershell
.\health-report.ps1
```

---

## Scheduling

Use Windows Task Scheduler.

Program

```text
powershell.exe
```

Arguments

```text
-ExecutionPolicy Bypass -File "C:\ServerReports\health-report.ps1"
```

---

## Output

```
Reports/
├── ServerHealth_20260715.csv
└── ServerHealth_20260715.xlsx

Logs/
└── ServerHealth_20260715.log
```

---

## Customization

Add additional performance counters.

Example:

```powershell
$PerformanceCounters = @(
    @{ Name="CPU"; Counter="\Processor(_Total)\% Processor Time" },
    @{ Name="Memory"; Counter="\Memory\Available MBytes" },
    @{ Name="Network"; Counter="\Network Interface(*)\Bytes Total/sec" }
)
```

---

## Daily Report Troubleshooting

### Cannot Connect

```powershell
Enable-PSRemoting -Force
```

### Excel Export Fails

```powershell
Install-Module ImportExcel
```

### Credential Not Found

```cmd
cmdkey /list
```

⬆️ [Back to Table of Contents](#-table-of-contents)

---

# Part II — Infrastructure Health Monitor Service

Runs continuously as a Windows Service and monitors infrastructure health in real time.

---

# Service Features

- 24/7 Continuous Monitoring
- Parallel Server Monitoring
- CPU Monitoring
- Memory Monitoring
- Disk Monitoring
- Network Monitoring
- Windows Service Monitoring
- Threshold-based Alerts
- Alert Cooldown
- Historical Metrics
- Email Notifications
- Microsoft Teams Notifications
- Slack Notifications
- Comprehensive Logging

⬆️ [Back to Table of Contents](#-table-of-contents)

---

# Installation

## 1. Download Files

```text
C:\InfrastructureMonitor\
```

---

## 2. Configure

Edit

```
config.ps1
```

Configure:

- Global Thresholds
- Email
- Teams
- Slack
- Server Overrides

---

## 3. Create Server List

```text
SRV-WEB01
SRV-APP01
SRV-DB01
192.168.1.30
```

---

## 4. Store Email Credentials

```cmd
cmdkey /add:MONITOR_EMAIL_CRED /user:monitor@company.com /pass:Password
```

---

## 5. Install Required Module

```powershell
Install-Module CredentialManager -Scope CurrentUser
```

---

## 6. Install NSSM

Download NSSM and run

```powershell
.\install-service.ps1
```

---

# Configuration Guide

## Global Thresholds

```powershell
$GlobalThresholds = @{
    CPU_Threshold = 80
    Memory_Threshold = 85
    Disk_Threshold = 90
    Network_Threshold = 70
}
```

---

## Server Overrides

```powershell
$ServerOverrides = @{
    "SRV-DB01" = @{
        CPU_Threshold = 70
        Memory_Threshold = 80
        Disk_Threshold = 85
    }
}
```

---

## Email Configuration

```powershell
$EmailConfig = @{
    Enabled = $true
    SMTPServer = "smtp.company.com"
    Port = 587
    UseSSL = $true
    From = "monitor@company.com"
    To = "admin@company.com"
    CredentialName = "MONITOR_EMAIL_CRED"
}
```

---

## Microsoft Teams

```powershell
$TeamsConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://company.webhook.office.com/..."
    )
}
```

---

## Slack

```powershell
$SlackConfig = @{
    Enabled = $true
    WebhookURLs = @(
        "https://hooks.slack.com/services/..."
    )
}
```

---

# Service Management

### Start

```cmd
nssm start InfrastructureMonitorService
```

### Stop

```cmd
nssm stop InfrastructureMonitorService
```

### Restart

```cmd
nssm restart InfrastructureMonitorService
```

### Status

```cmd
nssm status InfrastructureMonitorService
```

---

# Testing

## Manual Run

```powershell
.\monitor-service.ps1
```

---

## Test One Server

```powershell
Get-ServerMetrics -ServerName "SRV-WEB01"
```

---

## Test Notifications

```powershell
Send-AllNotifications
```

---

# Service Troubleshooting

## Service Won't Start

```powershell
Get-Service InfrastructureMonitorService
```

---

## Test WinRM

```powershell
Test-WSMan SRV-WEB01
```

---

## Enable WinRM

```powershell
Enable-PSRemoting -Force
```

---

## Test Email

```powershell
Send-MailMessage ...
```

---

## Test Teams

```powershell
Invoke-RestMethod ...
```

---

## Test Slack

```powershell
Invoke-RestMethod ...
```

⬆️ [Back to Table of Contents](#-table-of-contents)

---

# Security Considerations

- Store credentials using Windows Credential Manager
- Never hardcode passwords
- Use TLS for SMTP
- Enable WinRM HTTPS
- Restrict firewall access
- Restrict script folder permissions
- Rotate credentials regularly

---

# Performance Tuning

Monitoring Interval

```powershell
$MonitoringInterval = 60
```

Recommended Maintenance

- Review logs weekly
- Archive old metrics monthly
- Review thresholds quarterly
- Test alerts periodically
- Update server inventory

---

# Project Roadmap

## Completed

- Daily Reports
- CSV Export
- Excel Export
- Email Notifications
- Teams Notifications
- Slack Notifications
- Windows Service
- Historical Metrics

## Planned

- SMS Notifications
- Grafana Dashboard
- Prometheus Exporter
- REST API
- Web Dashboard
- Azure Monitor Integration
- AI-based Alert Correlation
- Predictive Failure Detection

---

# License

MIT License

---

**Author:** Daniel Olasupo

If you find this project useful, consider ⭐ starring the repository and contributing improvements through pull requests.