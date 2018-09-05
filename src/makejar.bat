@echo off
set jdk=d:\JDK8
set path=%jdk%\bin;%path%
cd "%~dp0"
cd ..\dump
for /f %%a in ('dir /b /a:d') do (cd %%a & echo Entering %%a & jar cnf ..\%%a.jar * & cd ..)
copy /B /Y *.jar ..\jre\lib
cd ..\jre\lib
del sunjce_provider* jardump* ojdbc* disruptor* jline* *gogo* jansi* dbcli* jnlua* db2* opencsv* jzlib* jsch* jna* nuproces* mysql* postgre* xdb* xmlparser* temp* jce*
move sunec* .\ext
cd "%~dp0"
pause