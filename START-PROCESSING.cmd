@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-processing.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Processing did not finish. Review the message above.
) else (
    echo The launcher finished successfully.
)
echo Press any key to close this window.
pause >nul
exit /b %EXIT_CODE%
