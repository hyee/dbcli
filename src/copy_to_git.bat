cd "%~dp0"
cd ..
set GIT_HOME=d:\green\github
setlocal enabledelayedexpansion
echo Copying Java source into src..
echo =========================
del /F/S/Q ".\src\java"
XCOPY /E /Y "d:\JavaProjects\dbcli\dbcli_1\src\*" .\src\java
XCOPY /E /Y "d:\JavaProjects\dbcli\opencsv\src\*" "%GIT_HOME%\opencsv\src"
XCOPY /E /Y "d:\JavaProjects\dbcli\nuprocess\src\*" "%GIT_HOME%\nuprocess\src"
XCOPY /E /Y ".\lib\opencsv.jar" "%GIT_HOME%\opencsv\release"
XCOPY /E /Y ".\lib\disruptor*.jar" "%GIT_HOME%\opencsv\release"
set copyflag=1

set target=%GIT_HOME%\dbcli
:start
echo Copying files into %target% ..
echo =========================
cd /d "%~dp0"
cd ..
mkdir "%target%"
cd /d "%target%"
REM git pull
forfiles /c "cmd /c if @isdir==TRUE (if @file NEQ \".git\" if @file NEQ \"aliases\" (del /S/Q @file\*.*)) else (del /S/F/Q @file)"

cd /d "%~dp0"
cd ..
copy data\*_sample.cfg  "%target%\data"
xcopy  . "%target%" /E /Y  /exclude:.\src\excludes.txt

if %copyflag%==1 XCOPY /E /Y .\src "%target%\src"

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
for /f %%i in ('dir /b/s/a:-H .\*.jar') do (pack200 -O -S-1 -G "%%i.pack.gz" "%%i" && del "%%i")

echo Packing dbcli zip files ..
echo =========================
rmdir /S /Q src
cd ..
del /F /Q dbcli*.zip
rmdir /S /Q dbcli_all
mkdir dbcli_all\dbcli
xcopy /E /Y "%target%" dbcli_all\dbcli /exclude:%~dp0\excludes_zip.txt
cd dbcli_all
zip -r -9 -q ..\dbcli_all.zip dbcli
zip -r -9 -q ..\dbcli_win.zip dbcli -x "dbcli\jre_linux\*"
zip -r -9 -q ..\dbcli_linux.zip dbcli -x "dbcli\jre\*" "dbcli\bin\*"
zip -r -9 -q ..\dbcli_nojre.zip dbcli -x "dbcli\jre\*" "dbcli\jre_linux\*"
