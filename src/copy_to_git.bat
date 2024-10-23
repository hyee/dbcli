cd "%~dp0"
echo select sys_context('userenv','current_schema') current_schema, sys_context('userenv','instance_name') instance from dual; > ..\oracle\sqlplus\init\init.sql
cd ..
for /f %%i in ('dir /b/s/a:-H dump\*.jar') do (pack200 -O -S-1 -G "%%i.pack.gz" "%%i" && del "%%i")
set GIT_HOME=d:\green\github
setlocal enabledelayedexpansion
echo Copying Java source into src..
echo =========================
del /F/S/Q ".\src\java"
XCOPY /E /Y "d:\JavaProjects\dbcli\dbcli\src\*" .\src\java
XCOPY /E /Y "d:\JavaProjects\dbcli\opencsv\src\*" "%GIT_HOME%\opencsv\src"
XCOPY /E /Y "d:\JavaProjects\dbcli\nuprocess\src\*" "%GIT_HOME%\nuprocess\src"
XCOPY /E /Y ".\lib\opencsv.jar" "%GIT_HOME%\opencsv\release"
set copyflag=1

set target=%GIT_HOME%\dbcli
:start
echo Copying files into %target% ..
echo =========================
cd /d "%~dp0"
cd ..
set "dump=%cd%\dump"
mkdir "%target%"
cd /d "%target%"
REM git pull
forfiles /c "cmd /c if @isdir==TRUE (if @file NEQ \".git\" if @file NEQ \"aliases\" (del /S/Q @file\*.*)) else (del /S/F/Q @file)"

cd /d "%~dp0"
cd ..
copy data\*_sample.cfg  "%target%\data"
ECHO Copy files...
xcopy  . "%target%" /E /Y  /exclude:.\src\excludes.txt

if %copyflag%==1 (
    XCOPY /E /Y .\src "%target%\src"
    pause
)

if %copyflag%==2 goto :end
set copyflag=2
set target=%GIT_HOME%\dbcli_compat
goto start
:end


xcopy /E /Y .\jre "%target%\jre"
xcopy /E /Y .\jre_linux "%target%\jre_linux"

echo Packing Jar library files ..
echo =========================
cd /d "%target%"
rem for /f %%i in ('dir /b/s/a:-H .\*.jar') do (pack200 -O -S-1 -G "%%i.pack.gz" "%%i" && del "%%i")

echo Packing dbcli zip files ..
echo =========================
rmdir /S /Q src
cd ..
del /F /Q dbcli*.zip
rmdir /S /Q dbcli_all
mkdir dbcli_all\dbcli
xcopy /E /Y "%target%" dbcli_all\dbcli /exclude:%~dp0\excludes_zip.txt
cd dbcli_all
del /F /Q dbcli\help.gif
zip -r -9 -q ..\dbcli_all.zip dbcli   
zip -r -9 -q ..\dbcli_win.zip dbcli   -x "dbcli\jre_linux\*"
zip -r -9 -q ..\dbcli_linux.zip dbcli -x "dbcli\jre\*" "dbcli\bin\*"
zip -r -9 -q ..\dbcli_nojre.zip dbcli -x "dbcli\jre\*" "dbcli\jre_linux\*"
del /F /Q .\dbcli\oracle\orai18n.*
del /F /Q .\dbcli\lib\x86\luv_winxp.dll
copy /Y "%dump%\*.jar" .\dbcli\oracle
del /F /Q .\dbcli\oracle\mysql*
rem move /Y .\dbcli\oracle\mysql* .\dbcli\mysql
zip -r -9 -q ..\dbcli_oracle_lite.zip dbcli -x "dbcli\help.gif" "dbcli\jre\*" "dbcli\docs\*" "dbcli\jre_linux\*" "dbcli\mysql\*" "dbcli\pgsql\*" "dbcli\db2\*" "dbcli\bin\*"
zip -r -9 -q ..\dbcli_mysql_lite.zip  dbcli -x "dbcli\help.gif" "dbcli\jre\*" "dbcli\docs\*" "dbcli\jre_linux\*" "dbcli\oracle\*" "dbcli\pgsql\*" "dbcli\db2\*" "dbcli\bin\*"
