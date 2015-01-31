@echo off
SET OTHER_LIB=; -javaagent:.\lib\dbcli.jar -server
"%~dp0\..\dbcli.bat" %*
cd src