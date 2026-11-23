@echo off
chcp 65001 >nul
cd /d "%~dp0"

rem =====================================================================
rem  miniserve quick launcher
rem
rem  All logic lives in web\serve.ps1 (PowerShell) - batch files are far
rem  too fragile with quotes, parentheses and delayed expansion.
rem  This file only locates PowerShell and hands over.
rem =====================================================================

where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell not found. Windows PowerShell 5.1+ is required.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0web\serve.ps1"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [ERROR] Launcher exited with code %EXITCODE%.
)
pause
exit /b %EXITCODE%
