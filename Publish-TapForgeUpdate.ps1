[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tag = "v$Version"

$remote = & git -c "safe.directory=$root" -C $root remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0 -or !$remote) { throw 'The GitHub repository has not been connected as the origin remote yet.' }

$changes = & git -c "safe.directory=$root" -C $root status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Could not read the Git working tree.' }
if ($changes) { throw 'Commit or discard your source changes before publishing. This script only publishes a clean commit.' }

$versionPath = Join-Path $root 'VERSION'
$currentVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($Version -ne $currentVersion) {
    Set-Content -LiteralPath $versionPath -Value $Version -Encoding ascii -NoNewline
    & git -c "safe.directory=$root" -C $root add -- VERSION
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage VERSION.' }
    & git -c "safe.directory=$root" -C $root commit -m "Set release version $Version"
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit the version change.' }
}

$existingTag = & git -c "safe.directory=$root" -C $root tag --list $tag
if ($existingTag) { throw "Release tag $tag already exists." }

# Publish the committed source to main, then push the release tag. The tag push
# starts the GitHub Actions workflow that builds and attaches the portable ZIP.
& git -c "safe.directory=$root" -C $root push origin 'HEAD:main'
if ($LASTEXITCODE -ne 0) { throw 'Could not push the source commit to origin/main.' }
& git -c "safe.directory=$root" -C $root tag -a $tag -m "TapForge $Version"
if ($LASTEXITCODE -ne 0) { throw "Could not create release tag $tag." }
& git -c "safe.directory=$root" -C $root push origin $tag
if ($LASTEXITCODE -ne 0) { throw "Could not push release tag $tag." }

Write-Host "Release $tag sent to GitHub. The release workflow will build and publish the portable download."
