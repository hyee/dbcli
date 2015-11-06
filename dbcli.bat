@echo off
Setlocal EnableDelayedExpansion EnableExtensions
cd /d "%~dp0"
SET CONSOLE_COLOR=0A
SET JRE_HOME=d:\soft\java
SET TNS_ADM=d:\Soft\InstanceClient\network\admin
SET ANSICON_EXC=nvd3d9wrap.dll;nvd3d9wrapx.dll
SET ANSICON_CMD=.\bin\ansiconx64.exe -m0A
SET DBCLI_ENCODING=UTF-8

rem read config file
If exist "data\init.cfg" (for /f "eol=# delims=" %%i in (data\init.cfg) do (%%i)) 

If not exist "%TNS_ADM%\tnsnames.ora" if defined ORACLE_HOME (set TNS_ADM=%ORACLE_HOME%\network\admin) 
IF not exist "%JRE_HOME%\java.exe" if exist "%JRE_HOME%\bin\java.exe" (set JRE_HOME=%JRE_HOME%\bin) else (set JRE_HOME=.\jre\bin)
SET PATH=%JRE_HOME%;%EXT_PATH%;%PATH%

if defined ANSICON_CMD (
   "%JRE_HOME%\java.exe" -version 2>&1 |findstr /i "64-bit" >nul
   if %errorlevel% equ 1 (.\bin\ansiconx86.exe -m%CONSOLE_COLOR% -p) ELSE (%ANSICON_CMD% -m%CONSOLE_COLOR% -p) 
) ELSE (COLOR %CONSOLE_COLOR%)
rem unpack jar files for the first use
for /r %%i in (*.pack.gz) do (
  set "var=%%i" &set "str=!var:@=!"
  unpack200 -q -r "%%i" "!str:~0,-8!"
)

"%JRE_HOME%\java.exe" -noverify -Xmx384M -cp .\lib\*;.\lib\ext\*%OTHER_LIB% ^
    -XX:NewRatio=50 -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions ^
    -XX:+AggressiveOpts -XX:MaxGCPauseMillis=400 -XX:GCPauseIntervalMillis=8000 ^
    -Dfile.encoding=%DBCLI_ENCODING% -Dsun.jnu.encoding=%DBCLI_ENCODING% -Dclient.encoding.override=%DBCLI_ENCODING% ^
    -Dinput.encoding=%DBCLI_ENCODING% -Duser.language=en -Duser.region=US -Duser.country=US ^
    -Doracle.net.tns_admin="%TNS_ADM%" -Djline.terminal=windows org.dbcli.Loader %DBCLI_PARAMS% %*
EndLocal