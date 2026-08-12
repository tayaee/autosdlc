@echo off
set GATE_NAME=run-regression-tests
set REPORT=%TEMP%\aacpd-%GATE_NAME%-%RANDOM%.log

if "%AACP_VERBOSE%"=="1" (
    bash bin/run-regression-tests.sh
    exit /b %ERRORLEVEL%
)

bash bin/run-regression-tests.sh > "%REPORT%" 2>&1
if %ERRORLEVEL% equ 0 (
    del /f "%REPORT%" 2>nul
    exit /b 0
) else (
    set EXIT_CODE=%ERRORLEVEL%
    echo ERROR: %GATE_NAME% failed with exit code %EXIT_CODE%. 1>&2
    echo Full log saved to: %REPORT% 1>&2
    echo --- Last lines of %REPORT% --- 1>&2
    type "%REPORT%" 1>&2
    exit /b %EXIT_CODE%
)
