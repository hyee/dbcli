cd "%~dp0"
cd ..
set GIT_HOME=d:\green\github
setlocal enabledelayedexpansion
del /F/S/Q ".\src\java"
XCOPY /S /Y "d:\JavaProjects\dbcli\dbcli_1\src\*" .\src\java
XCOPY /S /Y "d:\JavaProjects\dbcli\opencsv\src\*" "%GIT_HOME%\opencsv\src"
XCOPY /S /Y "d:\JavaProjects\dbcli\nuprocess\src\*" "%GIT_HOME%\nuprocess\src"
XCOPY  /S /Y ".\lib\opencsv.jar" "%GIT_HOME%\opencsv\release"
XCOPY  /S /Y ".\lib\disruptor*.jar" "%GIT_HOME%\opencsv\release"
set copyflag=1

set target=%GIT_HOME%\dbcli
:start
cd /d "%~dp0"
cd ..
mkdir "%target%"
cd /d "%target%"
REM git pull
forfiles /c "cmd /c if @isdir==TRUE (if @file NEQ \".git\" if @file NEQ \"aliases\" (del /S/Q @file\*.*)) else (del /S/F/Q @file)"

cd /d "%~dp0"
cd ..
copy data\*_sample.cfg  "%target%\data"
xcopy  . "%target%" /S /Y  /exclude:.\src\excludes.txt

if %copyflag%==1 XCOPY /S /Y .\src "%target%\src"

if %copyflag%==2 goto :end
set copyflag=2
set target=%GIT_HOME%\dbcli_compat
goto start


:end
xcopy /S /Y .\jre "%target%\jre"
xcopy /S /Y .\jre_linux "%target%\jre_linux"
cd /d "%target%"
for /f %%i in ('dir /b/s/a:-H .\*.jar') do ("D:\Program Files\Java\bin\pack200" -O -S-1 -G "%%i.pack.gz" "%%i" && del "%%i")

del ..\dbcli.zip
rmdir /S /Q src 
zip -r -9 -q ..\dbcli.zip *

