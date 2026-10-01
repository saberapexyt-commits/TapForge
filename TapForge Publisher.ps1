# TapForge Publisher - one button to ship your current build to everyone.
# Launch with "Publish TapForge.bat". Lives in the project folder (the git repo).
#
# What "Publish to everyone" does:
#   1. Test-builds TapForge.exe so a broken build never goes out
#   2. Writes VERSION and RELEASE_NOTES.md
#   3. git commit + push to main, then creates and pushes the vX.Y.Z tag
#   4. GitHub Actions builds TapForge.exe and attaches it to a new release
#   5. Every friend's TapForge sees the update next time it opens

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$root = $PSScriptRoot
$repo = 'saberapexyt-commits/TapForge'
$downloadLink = "https://github.com/$repo/releases/latest/download/TapForge.exe"
$script:git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $script:git) { foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) { if (Test-Path $p) { $script:git = $p; break } } }

# ---- small UI helpers ------------------------------------------------------
$bg = [System.Drawing.Color]::FromArgb(24, 24, 27); $panel = [System.Drawing.Color]::FromArgb(34, 34, 38)
$fg = [System.Drawing.Color]::FromArgb(240, 240, 244); $muted = [System.Drawing.Color]::FromArgb(160, 160, 170)
$accent = [System.Drawing.Color]::FromArgb(123, 97, 255)
function New-Label($text, $x, $y, $w, $h, $size = 9, $color = $fg, [switch]$Bold) {
    $l = [System.Windows.Forms.Label]::new(); $l.Text = $text; $l.Location = [System.Drawing.Point]::new($x, $y); $l.Size = [System.Drawing.Size]::new($w, $h)
    $l.ForeColor = $color; $l.Font = [System.Drawing.Font]::new('Segoe UI', $size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular })); $form.Controls.Add($l); $l
}
function New-Button($text, $x, $y, $w, $h, [switch]$Primary) {
    $b = [System.Windows.Forms.Button]::new(); $b.Text = $text; $b.Location = [System.Drawing.Point]::new($x, $y); $b.Size = [System.Drawing.Size]::new($w, $h)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.BackColor = $(if ($Primary) { $accent } else { $panel }); $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = [System.Drawing.Font]::new('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold); $b.Cursor = 'Hand'; $form.Controls.Add($b); $b
}
function New-Box($x, $y, $w, $h, [switch]$Multi, [switch]$ReadOnly) {
    $t = [System.Windows.Forms.TextBox]::new(); $t.Location = [System.Drawing.Point]::new($x, $y); $t.Size = [System.Drawing.Size]::new($w, $h)
    $t.BackColor = $panel; $t.ForeColor = $fg; $t.BorderStyle = 'FixedSingle'; $t.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    if ($Multi) { $t.Multiline = $true; $t.ScrollBars = 'Vertical' }
    if ($ReadOnly) { $t.ReadOnly = $true; $t.Font = [System.Drawing.Font]::new('Consolas', 8.5) }
    $form.Controls.Add($t); $t
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'TapForge Publisher'; $form.ClientSize = [System.Drawing.Size]::new(640, 640); $form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.BackColor = $bg; $form.ForeColor = $fg
$ico = Join-Path $root 'TapForge.ico'; if (Test-Path $ico) { try { $form.Icon = [System.Drawing.Icon]::new($ico) } catch { } }

[void](New-Label 'TapForge Publisher' 20 14 400 30 15 -Bold)
[void](New-Label "Project: $root" 20 46 600 20 9 $muted)
$versionInfo = New-Label 'This build: ...    Live for friends: checking...' 20 68 600 20 9 $muted

[void](New-Label 'New version' 20 102 160 20 9 -Bold)
$versionBox = New-Box 20 124 160 28
[void](New-Label "What's new (friends see this in the update popup)" 200 102 420 20 9 -Bold)
$notesBox = New-Box 200 124 420 90 -Multi

[void](New-Label 'Changes going out' 20 226 300 20 9 -Bold)
$changesBox = New-Box 20 248 600 90 -Multi -ReadOnly

$testButton = New-Button 'Test build' 20 352 140 42
$runTestButton = New-Button 'Run test build' 170 352 140 42
$publishButton = New-Button 'Publish to everyone' 320 352 300 42 -Primary
$runTestButton.Enabled = $false

[void](New-Label 'Log' 20 406 100 20 9 -Bold)
$logBox = New-Box 20 428 600 150 -Multi -ReadOnly
[void](New-Label 'Friend download link (always the newest version):' 20 588 400 18 8.5 $muted)
$linkBox = New-Box 20 606 430 26 -ReadOnly; $linkBox.Text = $downloadLink
$copyButton = New-Button 'Copy link' 460 604 75 28
$releasesButton = New-Button 'Releases' 545 604 75 28

function Log([string]$text) {
    $logBox.AppendText(('[{0}] {1}' -f (Get-Date).ToString('HH:mm:ss'), $text) + [Environment]::NewLine)
    [System.Windows.Forms.Application]::DoEvents()
}
function Invoke-Git {
    $out = & $script:git -c "safe.directory=$root" -C $root @args 2>&1 | ForEach-Object { "$_" } | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out.Trim() }
}
function Get-ProjectVersion { try { (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim() } catch { '0.0.0' } }
function Get-LiveRelease {
    try { Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'TapForge-Publisher' } -TimeoutSec 8 } catch { $null }
}
function Get-NextVersion([string]$project, [string]$live) {
    # If this build's version hasn't been released yet, suggest it as-is; otherwise bump the patch number.
    $p = try { [version]$project } catch { [version]'0.0.0' }
    $l = try { [version]$live } catch { [version]'0.0.0' }
    if ($p -gt $l) { return "$($p.Major).$($p.Minor).$([Math]::Max(0, $p.Build))" }
    "$($l.Major).$($l.Minor).$([Math]::Max(0, $l.Build) + 1)"
}
function Update-Info {
    $script:projectVersion = Get-ProjectVersion
    $live = Get-LiveRelease
    $script:liveVersion = if ($live) { ([string]$live.tag_name) -replace '^v', '' } else { '' }
    $liveText = if ($script:liveVersion) { "v$($script:liveVersion)" } else { 'unknown (offline?)' }
    $versionInfo.Text = "This build: v$($script:projectVersion)        Live for friends: $liveText"
    if (-not $versionBox.Text) { $versionBox.Text = Get-NextVersion $script:projectVersion $script:liveVersion }
    if ($script:git) {
        $st = Invoke-Git status --porcelain
        $changesBox.Text = if ($st.Out) { $st.Out } else { '(no file changes - publishing will just bump the version)' }
    } else {
        $changesBox.Text = 'Git was not found. Install Git for Windows (git-scm.com), then reopen the publisher.'
        $publishButton.Enabled = $false
    }
}

$script:testExe = Join-Path $root 'release\TapForge.exe'
function Invoke-TestBuild {
    Log 'Test build: compiling TapForge.exe...'
    $builder = Join-Path $root 'Build TapForge.ps1'
    $out = & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $builder -Output $script:testExe 2>&1 | Out-String
    $ok = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $script:testExe)
    if ($ok) {
        $kb = [Math]::Round((Get-Item -LiteralPath $script:testExe).Length / 1KB)
        Log "Test build OK ($kb KB): $($script:testExe)"
        $runTestButton.Enabled = $true
    } else {
        Log ('Test build FAILED:' + [Environment]::NewLine + $out.Trim())
    }
    $ok
}

$testButton.Add_Click({ $form.UseWaitCursor = $true; try { [void](Invoke-TestBuild) } finally { $form.UseWaitCursor = $false } })
$runTestButton.Add_Click({
    if (Test-Path -LiteralPath $script:testExe) { Start-Process -FilePath $script:testExe; Log 'Started the test build. (Close your normal TapForge first - only one can run at a time.)' }
})
$copyButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($downloadLink); Log 'Download link copied.' })
$releasesButton.Add_Click({ Start-Process "https://github.com/$repo/releases" })

$script:pollTag = $null; $script:pollStarted = $null
$pollTimer = [System.Windows.Forms.Timer]::new(); $pollTimer.Interval = 10000
$pollTimer.Add_Tick({
    $elapsed = ((Get-Date) - $script:pollStarted).TotalMinutes
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/tags/$($script:pollTag)" -Headers @{ 'User-Agent' = 'TapForge-Publisher' } -TimeoutSec 8
        if (@($rel.assets | Where-Object { $_.name -eq 'TapForge.exe' }).Count -gt 0) {
            $pollTimer.Stop()
            Log "LIVE: $($script:pollTag) is out. Friends get it next time they open TapForge."
            $publishButton.Text = 'Published!'; Update-Info
            [System.Windows.Forms.MessageBox]::Show("$($script:pollTag) is live.`n`nEveryone gets it the next time they open TapForge.", 'TapForge Publisher') | Out-Null
            $publishButton.Text = 'Publish to everyone'; $publishButton.Enabled = $true
            return
        }
    } catch { }
    if ($elapsed -gt 15) {
        $pollTimer.Stop(); $publishButton.Enabled = $true
        Log "Still not live after 15 minutes. Check the Actions tab: https://github.com/$repo/actions"
    } else { Log ('Waiting for GitHub to build the release... ({0:N0}s)' -f ($elapsed * 60)) }
})

$publishButton.Add_Click({
    $v = $versionBox.Text.Trim() -replace '^v', ''
    if ($v -notmatch '^\d+\.\d+\.\d+$') { [System.Windows.Forms.MessageBox]::Show('Use a version like 4.0.1', 'TapForge Publisher') | Out-Null; return }
    if ($script:liveVersion -and ([version]$v -le [version]$script:liveVersion)) {
        [System.Windows.Forms.MessageBox]::Show("Friends already have v$($script:liveVersion). Pick a higher version so their TapForge sees it as an update.", 'TapForge Publisher') | Out-Null; return
    }
    $workflow = Join-Path $root '.github\workflows\publish-release.yml'
    $wfText = if (Test-Path -LiteralPath $workflow) { Get-Content -LiteralPath $workflow -Raw } else { '' }
    if ($wfText -notmatch 'name=TapForge\.exe') {
        [System.Windows.Forms.MessageBox]::Show("The GitHub build recipe is still the old one, so friends wouldn't get the single TapForge.exe.`n`nMove 'publish-release.yml' from the project folder into the .github\workflows folder (replace the old file), then publish again.", 'TapForge Publisher', 'OK', 'Warning') | Out-Null
        return
    }
    $tag = "v$v"
    if ((Invoke-Git tag --list $tag).Out) { [System.Windows.Forms.MessageBox]::Show("$tag already exists. Pick a different version.", 'TapForge Publisher') | Out-Null; return }
    $notes = $notesBox.Text.Trim()
    if (-not $notes) {
        if ([System.Windows.Forms.MessageBox]::Show("You didn't write what's new. Publish $tag anyway?", 'TapForge Publisher', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    if ([System.Windows.Forms.MessageBox]::Show("Publish TapForge $tag to everyone?`n`nThis pushes your current project to GitHub and releases it.", 'TapForge Publisher', 'YesNo', 'Warning') -ne 'Yes') { return }

    $publishButton.Enabled = $false; $form.UseWaitCursor = $true
    try {
        Log "=== Publishing $tag ==="
        if (-not (Invoke-TestBuild)) { Log 'Stopped: fix the build error above, then try again.'; return }
        $remoteTag = Invoke-Git ls-remote --tags origin "refs/tags/$tag"
        if ($remoteTag.Out -match [regex]::Escape("refs/tags/$tag")) { Log "Stopped: $tag already exists on GitHub."; return }

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $root 'VERSION'), $v, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $root 'RELEASE_NOTES.md'), $notes, $utf8)
        Log "Wrote VERSION ($v) and release notes."

        $r = Invoke-Git add -A; if ($r.Code -ne 0) { Log ("git add failed:`r`n" + $r.Out); return }
        $r = Invoke-Git commit -m "TapForge $tag"
        if ($r.Code -ne 0 -and $r.Out -notmatch 'nothing to commit') { Log ("git commit failed:`r`n" + $r.Out); return }
        Log 'Committed.'
        Log 'Pushing to GitHub (a sign-in window may appear the first time)...'
        $r = Invoke-Git push origin HEAD:main
        if ($r.Code -ne 0) { Log ("Push failed:`r`n" + $r.Out); return }
        Log 'Pushed source.'
        $r = Invoke-Git tag -a $tag -m "TapForge $tag"; if ($r.Code -ne 0) { Log ("Tag failed:`r`n" + $r.Out); return }
        $r = Invoke-Git push origin $tag
        if ($r.Code -ne 0) { Log ("Tag push failed:`r`n" + $r.Out); return }
        Log "Pushed $tag. GitHub is building the release now (usually 1-3 minutes)."
        $script:pollTag = $tag; $script:pollStarted = Get-Date; $pollTimer.Start()
        $publishButton.Text = 'Building on GitHub...'
        Update-Info
    } finally {
        $form.UseWaitCursor = $false
        if (-not $pollTimer.Enabled) { $publishButton.Enabled = $true }
    }
})

$form.Add_Shown({ Log 'Checking project and GitHub...'; Update-Info; Log 'Ready.' })
[void]$form.ShowDialog()
$pollTimer.Dispose()
