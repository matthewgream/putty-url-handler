<#
.SYNOPSIS
    Compiles PuttyUrl.exe from PuttyUrl.cs using the .NET Framework compiler
    that ships with Windows, so there is nothing to install to build this.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    throw "C# compiler not found at $csc"
}

$source = Join-Path $PSScriptRoot 'PuttyUrl.cs'
$output = Join-Path $PSScriptRoot 'PuttyUrl.exe'

& $csc /nologo /target:winexe /optimize+ /warn:4 `
    /r:System.Windows.Forms.dll "/out:$output" $source
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }

Write-Host "Built $output"
