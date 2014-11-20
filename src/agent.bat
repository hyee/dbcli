@echo off
set JRE_HOME=C:\Program Files (x86)\Java\jdk7\jre\bin
SET OTHER_LIB=; -javaagent:agent.jar
"%~dp0\dbcli.bat" %*
