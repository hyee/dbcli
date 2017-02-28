@echo off
Setlocal EnableDelayedExpansion EnableExtensions
cd /d "%~dp0"
SET JAVA_HOME=
SET CLASSPATH=
SET JAVA_TOOL_OPTIONS=
if not defined CONSOLE_COLOR SET CONSOLE_COLOR=0A
if not defined ANSICON_CMD SET ANSICON_CMD=.\lib\x64\ansicon.exe
if !ANSICOLOR!==off set ANSICON_CMD=

if not defined TNS_ADM SET TNS_ADM=d:\Soft\InstanceClient\network\admin
SET DBCLI_ENCODING=UTF-8

rem read config file
If exist "data\init.cfg" (for /f "eol=# delims=" %%i in (data\init.cfg) do (%%i))
rem if JRE_HOME is not defined in init.cfg, find java.exe in default path
if not defined JRE_HOME (
    for /F %%p in ('where java.exe') do (
        for /f tokens^=2-5^ delims^=.-_^" %%j in ('"%%p" -fullversion 2^>^&1') do (
            if 18000 LSS %%j%%k%%l%%m  set "JRE_HOME=%%~dpsp"
)))

If not exist "%TNS_ADM%\tnsnames.ora" if defined ORACLE_HOME (set "TNS_ADM=%ORACLE_HOME%\network\admin" )


IF not exist "%JRE_HOME%\java.exe" if exist "%JRE_HOME%\bin\java.exe" (set "JRE_HOME=%JRE_HOME%\bin") else (set JRE_HOME=.\jre\bin)

for %%x in ("!JRE_HOME!") do set "JRE_HOME=%%~sx"
IF %JRE_HOME:~-1%==\ SET "JRE_HOME=%JRE_HOME:~0,-1%"

SET PATH=%JRE_HOME%;%EXT_PATH%;.\bin;%PATH%
if defined ANSICON_CMD (
   SET ANSICON_EXC=nvd3d9wrap.dll;nvd3d9wrapx.dll
   SET ANSICON_DEF=ansicon
   echo %PROCESSOR_ARCHITECTURE%|findstr /i "64" >nul ||("!JRE_HOME!\java.exe" -version 2>&1 |findstr /i "64-bit" >nul)||(set ANSICON_CMD=.\lib\x86\ansicon.exe)
   if not exist "!ANSICON_CMD!" (
        set "ANSICON_CMD="
        set "ANSICON_DEF=jline"
   )     
)

rem For win10, don't used both JLINE/Ansicon to escape the ANSI codes
rem ver|findstr -r "[1-9][0-9]\.[0-9]*\.[0-9]">NUL && (SET "ANSICON_CMD=" && set "ANSICON_DEF=native")
color !CONSOLE_COLOR!
rem unpack jar files for the first use
for /r %%i in (*.pack.gz) do (
   set "var=%%i" &set "str=!var:@=!"
   echo Unpacking %%i to jar file for the first use...
   unpack200 -q -r "%%i" "!str:~0,-8!"
)

(%ANSICON_CMD% "!JRE_HOME!\java.exe" -noverify -Xmx384M -cp .\lib\*;.\lib\ext\*%OTHER_LIB% ^
    -XX:+UseG1GC -XX:+UseStringDeduplication ^
    -Dfile.encoding=%DBCLI_ENCODING% -Dsun.jnu.encoding=%DBCLI_ENCODING% -Dclient.encoding.override=%DBCLI_ENCODING% ^
    -Dinput.encoding=%DBCLI_ENCODING% -Duser.language=en -Duser.region=US -Duser.country=US ^
    -Doracle.net.tns_admin="%TNS_ADM%" -Djline.terminal=windows org.dbcli.Loader %DBCLI_PARAMS% %* )||pause
EndLocal