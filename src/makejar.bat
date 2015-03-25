@echo off
set path=d:\java\bin;%path%;
cd "%~dp0"
cd ..\dump
for /f %%a in ('dir /b /a:d') do (cd %%a & echo Entering %%a & jar cvf ..\%%a.jar * & cd ..)
copy /B /Y *.jar ..\jre\lib
cd ..\jre\lib
del ojdbc* jline* dbcli* jnlua* db2* opencsv*
cd "%~dp0"
pause