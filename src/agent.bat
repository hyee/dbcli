@echo off
SET OTHER_LIB=; -javaagent:.\lib\dbcli.jar -Xshare:off
"%~dp0\..\dbcli.bat" %*
cd src