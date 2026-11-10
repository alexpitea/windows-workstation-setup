# Shared helpers for the scripts in this repository.

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    param([bool]$Preview)

    # -WhatIf only describes the changes, so a preview may run without elevation.
    if ($Preview) { return }

    if (-not (Test-Administrator)) {
        throw 'This script changes system settings. Run it from an elevated PowerShell (Run as administrator), or add -WhatIf to preview.'
    }
}
