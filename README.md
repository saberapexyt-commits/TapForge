# TapForge

TapForge is a Windows autoclicker.

**[Download TapForge.exe](https://github.com/saberapexyt-commits/TapForge/releases/latest/download/TapForge.exe)**: one file, no install. It updates itself.

## Features

- Mouse or keyboard clicks, interval (ms/sec/min) or clicks per second
- High-resolution click engine, global hotkeys (including Mouse 4/5), hold or toggle
- Click points, process filter, screen safety stops, presets, tray and compact modes
- Light/dark theme with custom accent colors

## Developing

- `AutoClicker.ps1` is the app (WPF interface + click engine). `TapForge.exe` in this
  folder runs it directly because of the `TapForge.dev` marker file.
- `Build TapForge.ps1` builds the single-file `TapForge.exe` (script, logo, icon and
  `VERSION` are embedded).

## Publishing

Double-click **Publish TapForge.bat**, type what's new and click **Publish to everyone**.
It test-builds, commits, pushes and tags; GitHub Actions then builds `TapForge.exe` and
attaches it (plus a legacy portable ZIP for older versions) to a new release.
