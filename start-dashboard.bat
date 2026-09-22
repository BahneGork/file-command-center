@echo off
title File Command Center
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dashboard-server.ps1"
if errorlevel 1 pause
