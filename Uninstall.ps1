<#
.SYNOPSIS
    Removes the URL protocol handlers registered by Install.ps1.
.DESCRIPTION
    Removes the per-user keys by default, or the machine-wide ones with
    -Machine (which needs an elevated shell). Where Install.ps1 shadowed an
    existing handler, the saved PuttyUrlBackup command is restored rather than
    the key being deleted outright.
.EXAMPLE
    .\Uninstall.ps1
.EXAMPLE
    .\Uninstall.ps1 -Machine -Schemes ssh,putty,telnet,rlogin
#>
[CmdletBinding()]
param(
    [string[]] $Schemes = @('ssh', 'putty', 'telnet', 'rlogin'),
    [switch]   $Machine
)

$ErrorActionPreference = 'Stop'

$validSchemes = @('ssh', 'putty', 'telnet', 'rlogin')
$Schemes = @($Schemes |
    ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ } |
    Select-Object -Unique)

if (-not $Schemes) { throw 'No schemes given.' }
$unknown = @($Schemes | Where-Object { $validSchemes -notcontains $_ })
if ($unknown) {
    throw "Unknown scheme$(if ($unknown.Count -gt 1) { 's' }): $($unknown -join ', '). Valid: $($validSchemes -join ', ')"
}

if ($Machine) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw '-Machine writes to HKLM and needs an elevated shell.'
    }
    $classes = 'HKLM:\SOFTWARE\Classes'
}
else {
    $classes = 'HKCU:\Software\Classes'
}

foreach ($scheme in $Schemes) {
    $root = "$classes\$scheme"
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host "No ${scheme}:// handler in $(if ($Machine) { 'HKLM' } else { 'HKCU' })"
        continue
    }

    $backup = (Get-ItemProperty $root -ErrorAction SilentlyContinue).'PuttyUrlBackup'
    if ($backup) {
        Set-ItemProperty -Path "$root\shell\open\command" -Name '(default)' -Value $backup
        Remove-ItemProperty -Path $root -Name 'PuttyUrlBackup'
        Remove-Item -LiteralPath "$root\DefaultIcon" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Restored previous ${scheme}:// handler: $backup"
    }
    else {
        Remove-Item -LiteralPath $root -Recurse -Force
        Write-Host "Removed ${scheme}:// handler"
    }
}
