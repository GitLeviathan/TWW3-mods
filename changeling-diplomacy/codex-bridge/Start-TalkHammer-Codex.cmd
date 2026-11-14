@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-TalkHammer-Codex.ps1" %*
if errorlevel 1 pause
