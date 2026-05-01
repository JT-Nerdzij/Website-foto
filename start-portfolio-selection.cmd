@echo off
powershell -NoExit -STA -ExecutionPolicy Bypass -File "%~dp0generate-portfolio-selection.ps1"
echo.
echo Tip: als de GUI lastig doet, gebruik start-portfolio-selection-web.cmd
