cd "%~dp0"
cd ..
setlocal enabledelayedexpansion
XCOPY /S /Y "D:\JavaProjects\dbcli\src\*" .\src\java

set copyflag=1

set target=D:\green\github\dbcli
:start
cd "%~dp0"
cd ..
mkdir "%target%"
del /s "%target%\*.lua"
del /s "%target%\*.jar"
del /s "%target%\*.sql"
del /s "%target%\*.chm"
del /s "%target%\*.bat"
del /s "%target%\*.txt"
del /s "%target%\*.bak"
del /s "%target%\*.so"
del /s "%target%\*.ddl"
del /s "%target%\*.bat"
del /s "%target%\*.exe"

xcopy  . "%target%" /S /Y  /exclude:.\src\excludes.txt

if %copyflag%==1 XCOPY /S /Y .\src "%target%\src"

if %copyflag%==2 goto :end
set copyflag=2
set target=D:\green\github\dbcli_compat
goto start


:end
xcopy /S /Y .\jre %target%\jre
cd /d %target%
del ..\dbcl*.zip
rmdir /S /Q src 
zip -r -9 -q ..\dbcli.zip *

pause
