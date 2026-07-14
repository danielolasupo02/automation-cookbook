<#
.SYNOPSIS
    Sends a daily business report email
.DESCRIPTION
    This sample script generates and sends a daily business report
.PARAMETER Recipients
    Email recipients (comma separated)
.PARAMETER Format
    Report format (HTML, CSV, Excel)
#>

param(
    [string]$Recipients = "admin@company.com",
    [string]$Format = "HTML"
)

Write-Host "Generating daily business report..." -ForegroundColor Cyan
Write-Host "Recipients: $Recipients" -ForegroundColor Green
Write-Host "Format: $Format" -ForegroundColor Green

# Simulate report generation
$Report = @"
Daily Business Report
=====================
Date: $(Get-Date -Format "yyyy-MM-dd")
Time: $(Get-Date -Format "HH:mm:ss")

Summary
-------
Total Orders: 1,234
Revenue: $45,678.90
Active Users: 567
New Registrations: 89

Top Products
-----------
1. Product A - 234 units
2. Product B - 189 units
3. Product C - 145 units

Performance
----------
Page Load Time: 1.2s
Error Rate: 0.3%
Uptime: 99.97%

System Health
------------
CPU: 45%
Memory: 62%
Disk: 78%
"@

# Output the report
$Report | Out-String

# If this was a real script, it would send the report via email
Write-Host "Report would be sent to: $Recipients" -ForegroundColor Yellow

return $true