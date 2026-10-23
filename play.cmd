@echo off
rem Launch the game (double-click). "play.cmd -e" opens the Godot editor instead.
setlocal
set "GODOT="
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
  for %%F in ("%%D\Godot_v*_win64.exe") do set "GODOT=%%F"
)
if not defined GODOT (
  echo Godot was not found. Install it with: winget install GodotEngine.GodotEngine
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0game" %*
