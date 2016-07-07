@echo off
Setlocal EnableDelayedExpansion EnableExtensions
for /r %%i in (jit\*.lua) do (
   set "var=%%i" &set "str=!var:@=!"
   luajit -b -n jit.%%~ni jit\%%~ni.lua jit\%%~ni.o
)

