TapForge Auto-Clicker
====================

Launch TapForge.exe, TapForge.lnk, or Launch AutoClicker.bat.
TapForge.exe is a small Windows GUI host for the editable AutoClicker.ps1
feature script. Keep both files together. The executable uses Windows PowerShell,
which is included with Windows, without opening a console window.

The logo is embedded in TapForge.exe and also supplied as TapForge.ico. To use
the logo on the Windows taskbar, pin TapForge.exe or TapForge.lnk and unpin the
old PowerShell shortcut.

Features
- Left, right, or middle mouse clicks
- Click intervals from 1 millisecond to 60 minutes, displayed in ms, seconds, or minutes
- Set speed by interval or clicks per second (up to 1,000 CPS target)
- Dedicated high-resolution click worker, separate from the interface
- Continuous clicking, click-count limit, or time limit
- Global start/stop hotkey: F6 by default (choose F8-F12 in the app)
- Toggle or hold-to-click hotkey behavior
- Emergency stop: F7
- Mouse or keyboard input, double click, adjustable button hold time
- Speed randomization and screen edge and corner stops
- Saved click points that are clicked in sequence
- Live click count and elapsed time
- No installation or network connection required

Clicks are sent at the current mouse pointer position. At very short intervals,
the actual rate depends on system load, Windows scheduling, and the target app.

Use Pick point, then click the desired screen location; the clicker cycles
through saved points. F7 always stops the clicker.
At very short intervals, the actual click rate depends on system load, Windows
scheduling, and the application receiving the clicks; the 1 ms interval is a
target rather than a guaranteed rate.

TapForge saves your options, appearance, selected process, and click points
when the window closes or is sent to the tray. Settings are stored locally in
%LOCALAPPDATA%\TapForge. With Minimize to tray enabled, use the tray icon to
open TapForge again; choose Exit in its tray menu to close it completely.
