<#
.SYNOPSIS
    Quick health report for a Windows workstation.

.DESCRIPTION
    Read-only. Reports Windows version, uptime, memory use, free disk space,
    whether a restart is pending, the date of the last installed update and
    the processes that use the most memory. Anything that needs attention is
    listed under Warnings.

.PARAMETER MinFreePercent
    Free space below this percentage is reported as a warning. Default 15.

.PARAMETER MaxUptimeDays
    Uptime above this number of days is reported as a warning. Default 14.

.PARAMETER AsJson
    Writes the report as JSON, for collecting it from many machines.

.EXAMPLE
    .\Get-WorkstationHealth.ps1

.EXAMPLE
    .\Get-WorkstationHealth.ps1 -AsJson | Out-File "$env:COMPUTERNAME.json"
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$MinFreePercent = 15,

    [ValidateRange(1, 3650)]
    [int]$MaxUptimeDays = 14,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
$memoryUsedPercent = [math]::Round(100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize)

$disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{
        Drive       = $_.DeviceID
        SizeGB      = [math]::Round($_.Size / 1GB, 1)
        FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
        FreePercent = if ($_.Size) { [math]::Round(100 * $_.FreeSpace / $_.Size) } else { 0 }
    }
})

$pendingRestart =
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

$lastUpdate = $null
try {
    $lastUpdate = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
}
catch {
    $lastUpdate = $null   # the update history is not readable on every machine
}

$topProcesses = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
    [pscustomobject]@{ Name = $_.ProcessName; Id = $_.Id; MemoryMB = [math]::Round($_.WorkingSet64 / 1MB) }
})

$warnings = @()
foreach ($disk in $disks) {
    if ($disk.FreePercent -lt $MinFreePercent) { $warnings += "Drive $($disk.Drive) has $($disk.FreePercent)% free" }
}
if ($uptime.TotalDays -gt $MaxUptimeDays) { $warnings += "Not restarted for $([int]$uptime.TotalDays) days" }
if ($pendingRestart) { $warnings += 'A restart is pending (updates or component servicing)' }
if ($memoryUsedPercent -ge 90) { $warnings += "Memory is $memoryUsedPercent% used" }

$report = [pscustomobject]@{
    ComputerName      = $env:COMPUTERNAME
    Windows           = "$($os.Caption) ($($os.Version))"
    UptimeDays        = [math]::Round($uptime.TotalDays, 1)
    MemoryUsedPercent = $memoryUsedPercent
    Disks             = $disks
    PendingRestart    = [bool]$pendingRestart
    LastUpdate        = if ($lastUpdate) { $lastUpdate.InstalledOn.ToString('yyyy-MM-dd') } else { $null }
    TopProcesses      = $topProcesses
    Warnings          = $warnings
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 4
    return
}

Write-Host "$($report.ComputerName) - $($report.Windows)"
Write-Host "Uptime: $($report.UptimeDays) days   Memory used: $($report.MemoryUsedPercent)%   Last update: $($report.LastUpdate)"
$disks | Format-Table -AutoSize | Out-String | Write-Host
$topProcesses | Format-Table -AutoSize | Out-String | Write-Host
if ($warnings.Count) {
    Write-Host 'Warnings:'
    $warnings | ForEach-Object { Write-Host "  - $_" }
}
else {
    Write-Host 'No warnings.'
}
