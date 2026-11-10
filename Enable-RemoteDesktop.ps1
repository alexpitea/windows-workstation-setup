<#
.SYNOPSIS
    Turns on Remote Desktop with Network Level Authentication and opens the
    firewall only as far as needed.

.DESCRIPTION
    - allows incoming Remote Desktop connections
    - requires Network Level Authentication (the user logs in before a session is created)
    - enables the built-in "Remote Desktop" firewall rules
    - optionally limits those rules to the given subnets

    Each step is skipped when the setting already has the wanted value.

.PARAMETER AllowedSubnet
    One or more addresses or subnets that may connect, for example 10.0.10.0/24.
    When omitted, the scope of the firewall rules is left as it is.

.EXAMPLE
    .\Enable-RemoteDesktop.ps1 -AllowedSubnet 10.0.10.0/24 -WhatIf

.EXAMPLE
    .\Enable-RemoteDesktop.ps1 -AllowedSubnet 10.0.10.0/24, 10.0.99.0/24
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$')]
    [string[]]$AllowedSubnet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-Administrator -Preview:$WhatIfPreference

$terminalServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpListenerKey = Join-Path $terminalServerKey 'WinStations\RDP-Tcp'
# Resource name of the "Remote Desktop" rule group; it does not depend on the display language.
$firewallGroup = '@FirewallAPI.dll,-28752'

function Set-RegistryValueIfDifferent {
    param([string]$Key, [string]$Name, [int]$Wanted, [string]$What)

    $current = (Get-ItemProperty -Path $Key -Name $Name).$Name
    if ($current -eq $Wanted) {
        Write-Host "$What - already set."
        return
    }
    if ($PSCmdlet.ShouldProcess('Remote Desktop', $What)) {
        Set-ItemProperty -Path $Key -Name $Name -Value $Wanted
        Write-Host "$What - done."
    }
}

Set-RegistryValueIfDifferent -Key $terminalServerKey -Name 'fDenyTSConnections' -Wanted 0 -What 'Allow incoming connections'
Set-RegistryValueIfDifferent -Key $rdpListenerKey -Name 'UserAuthentication' -Wanted 1 -What 'Require Network Level Authentication'

$rules = @(Get-NetFirewallRule -Group $firewallGroup)
if ($rules.Count -eq 0) {
    throw 'The built-in Remote Desktop firewall rules were not found.'
}

$disabled = @($rules | Where-Object { $_.Enabled -ne 'True' })
if ($disabled.Count -eq 0) {
    Write-Host 'Firewall rules for Remote Desktop - already enabled.'
}
elseif ($PSCmdlet.ShouldProcess('Windows Firewall', "Enable $($disabled.Count) Remote Desktop rule(s)")) {
    $disabled | Enable-NetFirewallRule
    Write-Host 'Firewall rules for Remote Desktop - enabled.'
}

if ($AllowedSubnet) {
    $scope = $AllowedSubnet -join ', '
    if ($PSCmdlet.ShouldProcess('Windows Firewall', "Limit Remote Desktop to $scope")) {
        $rules | Set-NetFirewallRule -RemoteAddress $AllowedSubnet
        Write-Host "Remote Desktop limited to $scope."
    }
}
else {
    Write-Host 'Firewall scope left unchanged (no -AllowedSubnet given).'
}
