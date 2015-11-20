
@echo off

ver|findstr -r " [1-5]\.[0-9]*\.[0-9]" > nul&&(
    echo     =========================================================================================================
    echo     This ConsoleZ release doesn't support the Windows version that lower than Win7.
    echo     Please download the legacy version from https://github.com/cbucher/console and override to .\bin\consolez
    echo     =========================================================================================================
    pause
)
REM Use ConsoleZ as the terminal
cd /d "%~dp0\bin\consoleZ"
start /i Console.exe