@echo off
cd /d "%~dp0"

set BIN=dist\ai-radio-hunt-companion-win-x64.exe

if not exist "%BIN%" (
  echo Could not find %BIN%
  echo Make sure this file stays next to the dist\ folder it came with.
  echo.
  pause
  exit /b 1
)

echo Starting AI Radio Hunt companion...
echo Leave this window open while you play. Close the window to stop it.
echo.

"%BIN%"

echo.
pause
