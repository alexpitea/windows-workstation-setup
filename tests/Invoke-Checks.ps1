<#
.SYNOPSIS
    Checks the scripts without changing the computer.

.DESCRIPTION
    1. every script parses without syntax errors
    2. the two scripts that change settings are run with -WhatIf and the
       relevant system state is compared before and after
    3. the two read-only scripts are run and their output is checked

    Safe to run on any machine, without elevation.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$results = New-Object System.Collections.Generic.List[bool]

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $results.Add($Ok)
    $mark = if ($Ok) { '  OK   ' } else { '  FAIL ' }
    $suffix = if (-not $Ok -and $Detail) { "  -> $Detail" } else { '' }
    Write-Host "$mark$Name$suffix"
}

function Get-RelevantState {
    $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rules = Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
    [pscustomobject]@{
        Users        = (Get-LocalUser | Sort-Object Name | ForEach-Object { $_.Name }) -join ','
        DenyRdp      = (Get-ItemProperty $ts).fDenyTSConnections
        Nla          = (Get-ItemProperty (Join-Path $ts 'WinStations\RDP-Tcp')).UserAuthentication
        RulesEnabled = ($rules | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ','
        RuleScope    = ($rules | Sort-Object Name | ForEach-Object { ($_ | Get-NetFirewallAddressFilter).RemoteAddress -join '+' }) -join ','
    } | ConvertTo-Json -Compress
}

Write-Host '1. syntax'
foreach ($file in Get-ChildItem $root -Recurse -Filter *.ps1) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
    Check "$($file.Name) parses" ($errors.Count -eq 0) (($errors | ForEach-Object { $_.Message }) -join '; ')
}

Write-Host '2. -WhatIf changes nothing'
$before = Get-RelevantState
# "What if" messages are written straight to the console, so the scripts run in
# a child process whose output can be captured as text.
$adminOutput = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'New-LocalAdmin.ps1') -UserName 'whatif-check-user' -WhatIf | Out-String
$rdpOutput = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Enable-RemoteDesktop.ps1') -AllowedSubnet '10.0.10.0/24' -WhatIf | Out-String
$after = Get-RelevantState
Check 'New-LocalAdmin -WhatIf announces the user and the group' (($adminOutput -match 'Create local user') -and ($adminOutput -match 'Administrators')) $adminOutput
Check 'Enable-RemoteDesktop -WhatIf announces the firewall limit' ($rdpOutput -match 'Limit Remote Desktop to 10\.0\.10\.0/24') $rdpOutput
Check 'users, Remote Desktop settings and firewall rules are unchanged' ($before -eq $after)
Check 'the preview user was not created' (-not (Get-LocalUser -Name 'whatif-check-user' -ErrorAction SilentlyContinue))

Write-Host '3. invalid input is refused'
$refused = $false
try { & (Join-Path $root 'New-LocalAdmin.ps1') -UserName 'bad name;rm' -WhatIf | Out-Null } catch { $refused = $true }
Check 'New-LocalAdmin refuses a name with spaces and punctuation' $refused
$refused = $false
try { & (Join-Path $root 'Enable-RemoteDesktop.ps1') -AllowedSubnet 'anywhere' -WhatIf | Out-Null } catch { $refused = $true }
Check 'Enable-RemoteDesktop refuses a subnet that is not an address' $refused

Write-Host '4. read-only scripts'
$printers = @(& (Join-Path $root 'Get-PrinterPortAudit.ps1'))
$columns = 'Printer', 'Driver', 'Type', 'Port', 'Address', 'PortNumber', 'Shared', 'Note'
$shapeOk = ($printers.Count -eq 0) -or (@($columns | Where-Object { -not $printers[0].PSObject.Properties[$_] }).Count -eq 0)
Check "Get-PrinterPortAudit returns $($printers.Count) printers with the expected columns" $shapeOk

$csv = Join-Path $env:TEMP "printer-audit-check-$PID.csv"
& (Join-Path $root 'Get-PrinterPortAudit.ps1') -CsvPath $csv | Out-Null
Check 'Get-PrinterPortAudit writes the CSV' (Test-Path $csv)
Remove-Item $csv -ErrorAction SilentlyContinue

$health = & (Join-Path $root 'Get-WorkstationHealth.ps1') -AsJson | ConvertFrom-Json
Check 'Get-WorkstationHealth reports this computer' ($health.ComputerName -eq $env:COMPUTERNAME)
Check 'Get-WorkstationHealth lists at least one disk and five processes' ((@($health.Disks).Count -ge 1) -and (@($health.TopProcesses).Count -eq 5))
Check 'memory use is a percentage' (($health.MemoryUsedPercent -ge 1) -and ($health.MemoryUsedPercent -le 100))

$passed = @($results | Where-Object { $_ }).Count
Write-Host ''
Write-Host "RESULT: $passed of $($results.Count) checks passed"
if ($passed -ne $results.Count) { exit 1 }
