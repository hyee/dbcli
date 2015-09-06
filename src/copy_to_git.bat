cd "%~dp0"
cd ..
set GIT_HOME=d:\green\github
setlocal enabledelayedexpansion
del /F/S/Q ".\src\java"
XCOPY /S /Y "D:\JavaProjects\dbcli\src\*" .\src\java
XCOPY /S /Y "D:\JavaProjects\dbcli\opencsv\src\*" "%GIT_HOME%\opencsv\src"
XCOPY  /S /Y ".\lib\opencsv.jar" "%GIT_HOME%\opencsv\release"
set copyflag=1

set target=%GIT_HOME%\dbcli
:start
cd /d "%~dp0"
cd ..
mkdir "%target%"
cd /d "%target%"
REM git pull
del /s /f "%target%\*.lua"
del /s /f "%target%\*.jar"
del /s /f "%target%\*.zip"
del /s /f "%target%\*.gz"
del /s /f "%target%\*.cfg"
del /s /f "%target%\*.sql"
del /s /f "%target%\*.chm"
del /s /f "%target%\*.bat"
del /s /f "%target%\*.txt"
del /s /f "%target%\*.bak"
del /s /f "%target%\*.so"
del /s /f "%target%\*.log"
del /s /f "%target%\*.dll"
del /s /f "%target%\*.bat"
del /s /f "%target%\*.exe"
del /s /f "%target%\*.java"
del /s /f "%target%\*.class"
del /s /f "%target%\*.chart"
del /s /f "%target%\*.snap"
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
cd /d "%target%"
for /f %%i in ('dir /b/s/a:-H .\*.jar') do ("d:\java\jre\bin\pack200" -O -S-1 -G "%%i.pack.gz" "%%i" && del "%%i")

del ..\dbcli.zip
rmdir /S /Q src 
zip -r -9 -q ..\dbcli.zip *

pause
