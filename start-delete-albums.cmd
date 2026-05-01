@echo off
powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0delete-albums.ps1"
echo.
echo Tip: web versie = delete-albums-web.ps1
