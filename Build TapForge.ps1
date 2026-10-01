# Builds the single-file TapForge.exe (script, logo, icon and VERSION embedded).
# Usage: .\Build TapForge.ps1            -> TapForge.exe in this folder
#        .\Build TapForge.ps1 -Output X  -> build somewhere else (used by the publisher's test build)
param([string]$Output)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$compiler = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path $compiler)) { $compiler = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (!(Test-Path $compiler)) { throw 'The .NET Framework C# compiler is not available.' }
if (!$Output) { $Output = Join-Path $root 'TapForge.exe' }
$outDir = Split-Path -Parent $Output
if ($outDir -and !(Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$sma = [System.Management.Automation.PSObject].Assembly.Location
$source = Join-Path $root 'TapForgeHost.cs'
$icon = Join-Path $root 'TapForge.ico'
$resources = foreach ($name in @('AutoClicker.ps1', 'TapForgeLogo.png', 'TapForge.ico', 'VERSION')) {
    $path = Join-Path $root $name
    if (!(Test-Path -LiteralPath $path)) { throw "Missing $name - it must be in $root." }
    "/resource:$path,TapForge.$name"
}

& $compiler /nologo /target:winexe "/out:$Output" "/win32icon:$icon" "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll @resources $source
if ($LASTEXITCODE -ne 0) { throw "TapForge build failed with exit code $LASTEXITCODE." }
Write-Host "Built $Output"
