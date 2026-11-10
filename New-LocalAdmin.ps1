<#
.SYNOPSIS
    Creates a local administrator account, or repairs an existing one.

.DESCRIPTION
    Creates the local user if it does not exist and makes sure it is a member
    of the built-in Administrators group. Running it again changes nothing.
    The password is asked for interactively and is never written to disk or
    shown on screen.

.PARAMETER UserName
    Name of the local account (letters, digits, dot, dash, underscore; at most 20 characters).

.PARAMETER FullName
    Display name of the account.

.PARAMETER Password
    Password as a SecureString. When omitted, the script asks for it.

.EXAMPLE
    .\New-LocalAdmin.ps1 -UserName itadmin -WhatIf
    Shows what would be done without changing anything.

.EXAMPLE
    .\New-LocalAdmin.ps1 -UserName itadmin
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,20}$')]
    [string]$UserName,

    [string]$FullName = 'Local IT administrator',

    [securestring]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
Assert-Administrator -Preview:$WhatIfPreference

# The built-in Administrators group has the same SID on every display language.
$administratorsSid = 'S-1-5-32-544'

$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if ($user) {
    Write-Host "User '$UserName' already exists."
}
elseif ($PSCmdlet.ShouldProcess($UserName, 'Create local user')) {
    if (-not $Password) {
        $Password = Read-Host -AsSecureString "Password for $UserName"
    }
    $user = New-LocalUser -Name $UserName -FullName $FullName -Password $Password -Description 'Created by New-LocalAdmin.ps1'
    Write-Host "Created user '$UserName'."
}

$isMember = $false
if ($user) {
    try {
        $members = @(Get-LocalGroupMember -SID $administratorsSid)
        $isMember = [bool]($members | Where-Object { $_.SID.Value -eq $user.SID.Value })
    }
    catch {
        # Listing fails on some machines that have orphaned accounts in the
        # group. Adding the member is still safe: an existing member is reported below.
        $isMember = $false
    }
}

if ($isMember) {
    Write-Host "'$UserName' is already a local administrator."
}
elseif ($PSCmdlet.ShouldProcess($UserName, 'Add to the local Administrators group')) {
    try {
        Add-LocalGroupMember -SID $administratorsSid -Member $UserName
        Write-Host "Added '$UserName' to the local Administrators group."
    }
    catch [Microsoft.PowerShell.Commands.MemberExistsException] {
        Write-Host "'$UserName' is already a local administrator."
    }
}
