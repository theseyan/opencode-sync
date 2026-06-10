@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0opencode-sync.ps1" %*
