@echo off
rem One-step setup for a new office workstation:
rem   1. local administrator account for IT
rem   2. Remote Desktop with Network Level Authentication, limited to one subnet
rem   3. health report
rem Run as administrator. The PowerShell scripts can also be used one by one.

setlocal

net session >nul 2>&1
if errorlevel 1 (
    echo This file must be run as administrator: right-click, "Run as administrator".
    pause
    exit /b 1
)

set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File"

set /p ADMINUSER=Name for the local administrator account:
if "%ADMINUSER%"=="" (
    echo No name given, nothing was changed.
    exit /b 1
)

set /p SUBNET=Subnet allowed to use Remote Desktop, for example 10.0.10.0/24 (empty = leave the firewall scope as it is):

%PS% "%~dp0New-LocalAdmin.ps1" -UserName "%ADMINUSER%"
if errorlevel 1 exit /b 1

if "%SUBNET%"=="" (
    %PS% "%~dp0Enable-RemoteDesktop.ps1"
) else (
    %PS% "%~dp0Enable-RemoteDesktop.ps1" -AllowedSubnet "%SUBNET%"
)
if errorlevel 1 exit /b 1

%PS% "%~dp0Get-WorkstationHealth.ps1"

echo.
echo Setup finished.
pause
