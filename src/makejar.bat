@echo off
set jdk=d:\JDK8
set path=%jdk%\bin;path
cd "%~dp0"
cd ..\dump
for /f %%a in ('dir /b /a:d') do (cd %%a & echo Entering %%a & jar cvf ..\%%a.jar * & cd ..)
copy /B /Y *.jar ..\jre\lib
cd ..\jre\lib
del ojdbc* disruptor* jline* dbcli* jnlua* db2* opencsv* jzlib* jsch* jna* nuproces* mysql* postgre* xdb* xmlparser* temp*
rem copy /B/Y %jdk%\jre\lib\ext\sunjce_provider* ..\jre\lib\ext
cd "%~dp0"
pause