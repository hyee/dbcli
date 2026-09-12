@echo off
rem Agent-friendly headless dbcli runner; forwards every argument to agent-test.ps1.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-test.ps1" %*
