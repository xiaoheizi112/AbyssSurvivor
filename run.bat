@echo off
rem Survivor Mini - double-click to run (standalone window, 1280x720)
set GODOT=D:\Godot\Godot_v4.6-stable_win64.exe
if not exist "%GODOT%" (
    echo Godot not found: %GODOT%
    echo Edit this file and fix the GODOT path.
    pause
    exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
