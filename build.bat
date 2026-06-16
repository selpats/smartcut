@echo off
REM Launcher script for build_windows.ps1
REM Prioritizes modern PowerShell Core (pwsh) over Windows PowerShell (powershell)

where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Launching build script via PowerShell Core ^(pwsh^)...
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0distribution\pyinstaller\build_windows.ps1" %*
) else (
    echo [INFO] PowerShell Core ^(pwsh^) not found.
    echo [INFO] Falling back to Windows PowerShell...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0distribution\pyinstaller\build_windows.ps1" %*
)
