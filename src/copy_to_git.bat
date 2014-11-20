cd "%~dp0"
set target=D:\green\github\dbcli
del /s "%target%\*.lua"
del /s "%target%\*.jar"
del /s "%target%\*.sql"
del /s "%target%\*.chm"
del /s "%target%\*.bat"
del /s "%target%\*.txt"
del /s "%target%\*.bak"
del /s "%target%\*.mnk"
xcopy  . "%target%" /S /Y  /exclude:excludes.txt

COPY /Y "C:\Software\eclipse\workspace\dbcli\src\Loader.java" .\src\
COPY /Y .\src\Loader.java "%target%\src"
COPY /Y .\copy_to_git.bat "%target%\src"
COPY /Y .\excludes.txt "%target%\src"
COPY /Y .\docs\*.mnk "%target%\src"
COPY /Y .\agent.* "%target%\src"
pause
