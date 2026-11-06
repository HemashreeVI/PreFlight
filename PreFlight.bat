@echo off
rem Double-click to open PreFlight.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PreFlight.ps1"
