@echo off
REM Use ConsoleZ as the terminal
Setlocal EnableDelayedExpansion EnableExtensions
"%~dp0\bin"
if exist user.xml (set pref=user.xml) else  (set pref=console.xml)

ver|findstr -r " [1-5]\.[0-9]*\.[0-9]" > nul&&(
    echo     =========================================================================================================
    echo     This ConsoleZ release doesn't support the Windows version that lower than Win7.
    echo     Please download the legacy version from https://github.com/cbucher/console and override to .\bin\consolez
    echo     =========================================================================================================
)

(start /i Console.exe -c !pref! )||pause
cd /d "%~dp0"