$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$compiler = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path $compiler)) { $compiler = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (!(Test-Path $compiler)) { throw 'The .NET Framework C# compiler is not available.' }
$sma = [System.Management.Automation.PSObject].Assembly.Location
$source = Join-Path $root 'TapForgeHost.cs'
$icon = Join-Path $root 'TapForge.ico'
$output = Join-Path $root 'TapForge.exe'
& $compiler /nologo /target:winexe "/out:$output" "/win32icon:$icon" "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $source
if ($LASTEXITCODE -ne 0) { throw "TapForge build failed with exit code $LASTEXITCODE." }
Write-Host "Built $output"
