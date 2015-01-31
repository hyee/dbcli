@echo off
SET OTHER_LIB=; -javaagent:.\lib\dbcli.jar
"%~dp0\..\dbcli.bat" %*
cd src