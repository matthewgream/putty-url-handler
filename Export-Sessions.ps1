<#
.SYNOPSIS
    Exports PuTTY saved sessions to a .reg file, to carry them to another machine.
.DESCRIPTION
    Key authentication through this handler comes from saved sessions, so a new
    machine needs those sessions as well as the handler.

    This exports the sessions only. The private keys they point at are separate
    files: copy those too, to the SAME path, or edit PublicKeyFile in the .reg
    before importing.

    Import on the other machine by double-clicking the .reg, or:
        reg import putty-sessions.reg
.EXAMPLE
    .\Export-Sessions.ps1
.EXAMPLE
    .\Export-Sessions.ps1 -Path D:\transfer\putty-sessions.reg
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path $PWD 'putty-sessions.reg')
)

$ErrorActionPreference = 'Stop'

$key = 'HKCU\Software\SimonTatham\PuTTY\Sessions'
if (-not (Test-Path "HKCU:\Software\SimonTatham\PuTTY\Sessions")) {
    throw 'No PuTTY saved sessions found on this machine.'
}

& reg.exe export $key $Path /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg export failed ($LASTEXITCODE)" }

$sessions = Get-ChildItem 'HKCU:\Software\SimonTatham\PuTTY\Sessions'
Write-Host "Exported $($sessions.Count) session(s) to $Path"

$keys = $sessions |
    ForEach-Object { (Get-ItemProperty $_.PSPath).PublicKeyFile } |
    Where-Object { $_ } |
    Select-Object -Unique
if ($keys) {
    Write-Host ''
    Write-Host 'Copy these key files to the other machine at the same paths:'
    $keys | ForEach-Object { Write-Host "  $_$(if (-not (Test-Path $_)) { '   [MISSING HERE]' })" }
}
