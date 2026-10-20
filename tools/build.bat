@echo off
rem Builds the game as one file: build\Lantern.exe, the Godot runtime with the game's pack
rem folded into it (tools\embed_pck.gd), and a copy in the project folder to double-click.
rem Scripts go into the pack as compressed binary tokens (export preset), not source text,
rem and the project settings as project.binary: no project.godot, no .gd text in the game.
chcp 65001 > nul
rem Godot 4.3: set GODOT and GODOT_CONSOLE to say where it is, if not in the usual place.
if not defined GODOT set "GODOT=%LOCALAPPDATA%\Programs\Godot\Godot_v4.3-stable_win64.exe"
if not defined GODOT_CONSOLE set "GODOT_CONSOLE=%LOCALAPPDATA%\Programs\Godot\Godot_v4.3-stable_win64_console.exe"
cd /d "%~dp0.."
if not exist build mkdir build
"%GODOT_CONSOLE%" --headless --path . --import > nul 2>&1
"%GODOT_CONSOLE%" --headless --path . --export-pack "Windows Desktop" "build\Lantern.pck"
rem The runtime gets the game's icon (needs Python; without it the exe keeps Godot's icon).
copy /y "%GODOT%" "build\runtime.exe" > nul
python tools\set_icon.py "build\runtime.exe" "tools\icon.ico"
"%GODOT_CONSOLE%" --headless -s tools/embed_pck.gd -- "build\runtime.exe" "build\Lantern.pck" "build\Lantern.exe"
del "build\Lantern.pck"
del "build\runtime.exe"
copy /y "tools\HOW TO RUN.txt" "build\HOW TO RUN.txt" > nul
copy /y "build\Lantern.exe" "Lantern.exe" > nul
echo Built build\Lantern.exe (one file) and Lantern.exe in the project folder
