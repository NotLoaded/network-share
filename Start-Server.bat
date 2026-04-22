@echo off
TITLE Local Network Share Server

:: Ensure we are working in the directory where the script is located
cd /d "%~dp0"
echo [INFO] Starting Server...
powershell -NoProfile -ExecutionPolicy Bypass -File "ServerLogic.ps1"

echo.
echo Server has stopped.
pause
