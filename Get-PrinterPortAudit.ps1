<#
.SYNOPSIS
    Lists every installed printer with the port and network address it really uses.

.DESCRIPTION
    Read-only. Joins Get-Printer with Get-PrinterPort, classifies the
    connection type and flags addresses shared by more than one printer queue,
    which is the usual sign of a leftover or duplicated queue.

.PARAMETER CsvPath
    Optional path of a CSV file to write the result to.

.EXAMPLE
    .\Get-PrinterPortAudit.ps1 | Format-Table -AutoSize

.EXAMPLE
    .\Get-PrinterPortAudit.ps1 -CsvPath .\printers.csv
#>
[CmdletBinding()]
param(
    [string]$CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalProperty {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

$ports = @{}
foreach ($port in Get-PrinterPort) { $ports[$port.Name] = $port }

$rows = foreach ($printer in Get-Printer) {
    $port = $ports[$printer.PortName]
    $address = Get-OptionalProperty $port 'PrinterHostAddress'

    $type = 'Local or virtual'
    if ($address) { $type = 'TCP/IP' }
    elseif ($printer.PortName -like 'WSD*') { $type = 'WSD (auto-discovered)' }
    elseif ($printer.PortName -like 'USB*') { $type = 'USB' }
    elseif ($printer.PortName -like '\\*') { $type = 'Shared from a print server' }

    [pscustomobject]@{
        Printer    = $printer.Name
        Driver     = $printer.DriverName
        Type       = $type
        Port       = $printer.PortName
        Address    = $address
        PortNumber = Get-OptionalProperty $port 'PortNumber'
        Shared     = $printer.Shared
        Note       = ''
    }
}
$rows = @($rows)

$byAddress = $rows | Where-Object { $_.Address } | Group-Object Address | Where-Object { $_.Count -gt 1 }
foreach ($group in $byAddress) {
    foreach ($row in $group.Group) { $row.Note = "address used by $($group.Count) printer queues" }
}

if ($CsvPath) {
    $rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $($rows.Count) printers to $CsvPath"
}

$rows
