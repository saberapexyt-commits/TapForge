# TapForge

TapForge is a portable Windows autoclicker. Download the latest portable ZIP
from [GitHub Releases](https://github.com/saberapexyt-commits/TapForge/releases).

## Features

- Configurable mouse or keyboard clicks and intervals in milliseconds, seconds,
  or minutes
- Start/stop and emergency hotkeys
- Optional click points, click limits, speed randomization, and screen safety
- Local settings persistence and tray support

## Build

Run `Build TapForge.ps1` in Windows PowerShell. The distributable consists of
`TapForge.exe`, `AutoClicker.ps1`, `TapForge.ico`, `TapForgeLogo.png`,
`Launch AutoClicker.bat`, and `README.txt`.

## Releases

After committing source changes, run
`Publish-TapForgeUpdate.ps1 -Version MAJOR.MINOR.PATCH`. The script pushes the
source and release tag; GitHub Actions builds the Windows app and attaches the
portable ZIP to the release.
