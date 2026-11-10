# Windows workstation setup

PowerShell and Batch scripts for preparing and checking office workstations. They replace a checklist I used to follow by hand on every new computer: create the IT administrator account, turn on Remote Desktop for the management network only, check the printers and the general state of the machine.

Every script that changes something can be previewed with `-WhatIf`, does nothing when the setting already has the wanted value, and can be run again safely.

## Scripts

| Script | Changes the system | What it does |
|---|---|---|
| `New-LocalAdmin.ps1` | yes | creates a local user if missing and makes it a member of the Administrators group |
| `Enable-RemoteDesktop.ps1` | yes | allows Remote Desktop, requires Network Level Authentication, enables the firewall rules and can limit them to given subnets |
| `Get-PrinterPortAudit.ps1` | no | lists printers with the port and address they really use, flags an address shared by several queues |
| `Get-WorkstationHealth.ps1` | no | Windows version, uptime, memory, free disk space, pending restart, last update, top processes, warnings |
| `Setup-Workstation.bat` | yes | runs the first two and the health report in one step, for a new machine |

## Usage

Preview first:

```powershell
.\New-LocalAdmin.ps1 -UserName itadmin -WhatIf
.\Enable-RemoteDesktop.ps1 -AllowedSubnet 10.0.10.0/24 -WhatIf
```

```text
What if: Performing the operation "Create local user" on target "itadmin".
What if: Performing the operation "Add to the local Administrators group" on target "itadmin".
What if: Performing the operation "Limit Remote Desktop to 10.0.10.0/24" on target "Windows Firewall".
```

Then run the same commands without `-WhatIf` from an elevated PowerShell. The password for the new account is asked for on screen and is not stored anywhere.

Read-only reports:

```powershell
.\Get-PrinterPortAudit.ps1 | Format-Table -AutoSize
.\Get-PrinterPortAudit.ps1 -CsvPath .\printers.csv
.\Get-WorkstationHealth.ps1
.\Get-WorkstationHealth.ps1 -AsJson | Out-File "$env:COMPUTERNAME.json"
```

For a new machine, right-click `Setup-Workstation.bat` and choose "Run as administrator".

## Design choices

- **Built-in groups by SID.** The Administrators group is addressed as `S-1-5-32-544` and the firewall rules by their resource name, so the scripts work on Windows in any display language.
- **Remote Desktop is not opened to everyone.** Network Level Authentication is required, and `-AllowedSubnet` limits the firewall rules to the management network.
- **No passwords in files or on the command line.** The password is read as a `SecureString`.
- **Input is validated.** The user name and the subnets must match a strict pattern before anything runs.
- **Windows PowerShell 5.1.** No extra modules are needed, so the scripts run on a freshly installed machine.

## Checks

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Checks.ps1
```

The checks are safe to run anywhere, without elevation. They verify that every script parses, that the two scripts that change settings do nothing under `-WhatIf` (local users, Remote Desktop settings and firewall rules are compared before and after), that invalid input is refused, and that the read-only reports return the expected fields.

The changing scripts are verified here only in preview mode. Try them on a test machine before using them widely.
