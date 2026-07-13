# Daily Server Health Report (PowerShell)

Collect CPU, memory, and disk utilization from multiple Windows servers and email a daily health report.

Designed to run from a central **jump server** using **PowerShell Remoting (WinRM)**.

## Features

- Monitor multiple Windows servers
- CPU, memory, and disk usage
- CSV or Excel reports
- Email delivery
- Windows Credential Manager for SMTP credentials
- Logging
- Scheduled with Windows Task Scheduler

---

## Prerequisites

- Windows PowerShell 5.1+
- WinRM enabled on target servers
- Administrator access to monitored servers
- Network connectivity from the jump server

Optional (Excel reports):

```powershell
Install-Module ImportExcel -Scope CurrentUser
```

---

## Project Structure

```
ServerReports/
│
├── health-report.ps1
├── config.ps1
├── functions.ps1
├── servers.csv
└── README.md
```

---

## Configuration

### 1. Configure email

Edit `config.ps1`.

```powershell
$EmailTo = "admin@company.com"
$EmailFrom = "server-reports@company.com"

$SMTPServer = "smtp.company.com"
$SMTPPort = 587

$ReportFormat = "EXCEL"   # CSV or EXCEL

$CredentialName = "SMTP_CRED"
```

### 2. Configure servers

Edit `servers.csv`.

```csv
ServerName,IPAddress,Role
SRV-WEB01,192.168.1.10,Web
SRV-DB01,192.168.1.20,Database
```

### 3. Store SMTP credentials

```cmd
cmdkey /add:SMTP_CRED /user:smtp-user@company.com /pass:YourPassword
```

---

## Run

```powershell
.\health-report.ps1
```

---

## Schedule

Create a Windows Task Scheduler job that runs:

```text
powershell.exe -ExecutionPolicy Bypass -File "C:\ServerReports\health-report.ps1"
```

---

## Output

- Daily CSV or Excel report
- Email notification
- Log file

```
Logs/
└── ServerHealth_YYYYMMDD.log
```

---

## Customization

You can easily extend the script to monitor additional performance counters.

Example:

```powershell
$PerformanceCounters = @(
    @{ Name="CPU"; Counter="\Processor(_Total)\% Processor Time" },
    @{ Name="Network"; Counter="\Network Interface(*)\Bytes Sent/sec" }
)
```

---

## Troubleshooting

**Cannot connect**

```powershell
Enable-PSRemoting -Force
```

**Excel export fails**

```powershell
Install-Module ImportExcel
```

**Credential not found**

```cmd
cmdkey /list
```

---

## License

MIT