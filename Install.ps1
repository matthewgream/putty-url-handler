<#
.SYNOPSIS
    Registers PuttyUrl.exe as a Windows URL protocol handler so ssh:// links
    in a browser open PuTTY.
.DESCRIPTION
    By default this writes per-user keys under HKCU\Software\Classes, which
    needs no administrator rights.

    Chromium-based browsers on some machines only consult HKLM for protocol
    handlers and ignore the per-user keys entirely, which looks like the link
    doing nothing at all with no prompt. Use -Machine for that: it writes
    HKLM\Software\Classes instead, the hive the original approach used, and
    requires an elevated shell.

    Where a machine-wide handler already exists (Windows ships one for
    telnet://), its command is saved under a PuttyUrlBackup value first, and
    Uninstall.ps1 -Machine puts it back.
.PARAMETER Schemes
    Which schemes to claim. Default: ssh, putty.
.PARAMETER Machine
    Write to HKLM instead of HKCU. Needs an elevated shell.
.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -Machine -Schemes ssh,putty,telnet,rlogin
#>
[CmdletBinding()]
param(
    [string[]] $Schemes = @('ssh', 'putty'),
    [switch]   $Machine
)

$ErrorActionPreference = 'Stop'

# powershell.exe -File hands arguments over as plain strings, so
# "-Schemes ssh,telnet,rlogin" arrives as a single element rather than three.
# Accept that form as well as a real PowerShell array.
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

$handler = Join-Path $PSScriptRoot 'PuttyUrl.exe'
$source  = Join-Path $PSScriptRoot 'PuttyUrl.cs'

# Build on demand, so a fresh clone installs in one command.
$needsBuild = -not (Test-Path -LiteralPath $handler)
if (-not $needsBuild -and (Test-Path -LiteralPath $source)) {
    $needsBuild = (Get-Item $source).LastWriteTime -gt (Get-Item $handler).LastWriteTime
}
if ($needsBuild) {
    Write-Host 'Building PuttyUrl.exe ...'
    & (Join-Path $PSScriptRoot 'Build.ps1')
}
if (-not (Test-Path -LiteralPath $handler)) {
    throw "PuttyUrl.exe is missing and could not be built."
}

if ($Machine) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw '-Machine writes to HKLM and needs an elevated shell. Right-click PowerShell > Run as administrator, then run this again.'
    }
    $classes = 'HKLM:\SOFTWARE\Classes'
}
else {
    $classes = 'HKCU:\Software\Classes'
}

$descriptions = @{
    ssh    = 'URL:Secure Shell (SSH) Protocol'
    putty  = 'URL:PuTTY Protocol'
    telnet = 'URL:Telnet Protocol'
    rlogin = 'URL:Rlogin Protocol'
}

# Icon comes from PuTTY itself when we can find it, so links look right.
$icon = $handler
foreach ($p in @("$env:ProgramW6432\PuTTY\putty.exe", "$env:ProgramFiles\PuTTY\putty.exe")) {
    if (Test-Path -LiteralPath $p) { $icon = $p; break }
}

foreach ($scheme in $Schemes) {
    $root = "$classes\$scheme"

    # Preserve whatever was there before we shadow it, once.
    $existing = (Get-ItemProperty "$root\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    if ($existing -and $existing -notlike "*PuttyUrl.exe*") {
        $already = (Get-ItemProperty $root -ErrorAction SilentlyContinue).'PuttyUrlBackup'
        if (-not $already) {
            New-Item -Path $root -Force | Out-Null
            Set-ItemProperty -Path $root -Name 'PuttyUrlBackup' -Value $existing
            Write-Host "  saved previous ${scheme}:// handler: $existing"
        }
    }

    New-Item -Path "$root\shell\open\command" -Force | Out-Null
    New-Item -Path "$root\DefaultIcon" -Force | Out-Null

    Set-ItemProperty -Path $root -Name '(default)'    -Value $descriptions[$scheme]
    Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''
    Set-ItemProperty -Path "$root\DefaultIcon" -Name '(default)' -Value "$icon,0"
    Set-ItemProperty -Path "$root\shell\open\command" -Name '(default)' `
        -Value ('"{0}" "%1"' -f $handler)

    Write-Host "Registered ${scheme}:// in $(if ($Machine) { 'HKLM' } else { 'HKCU' }) -> $handler"
}

Write-Host ''
Write-Host 'Done. Restart your browser, then try a link such as ssh://localhost'
