@echo off
Setlocal EnableDelayedExpansion EnableExtensions
cd /d "%~dp0"
SET TERM=

color 0A
SET JRE_HOME=C:\Program Files\Java\jre1.8.0_40

SET TNS_ADM=C:\app\anjul.sahu\product\11.2.0\client_1\network\admin

rem read config file
If exist "data\init.cfg" (for /f "eol=# delims=" %%i in (data\init.cfg) do (%%i)) 

If not exist "%TNS_ADM%\tnsnames.ora" if defined ORACLE_HOME (set TNS_ADM=%ORACLE_HOME%\network\admin) 
IF not exist "%JRE_HOME%\java.exe" if exist "%JRE_HOME%\bin\java.exe" (set JRE_HOME=%JRE_HOME%\bin) else (set JRE_HOME=.\jre\bin)
SET PATH=%JRE_HOME%;%EXT_PATH%;%PATH%

rem unpack jar files for the first use
for /r %%i in (*.pack.gz) do (
  set "var=%%i" &set "str=!var:@=!"
  unpack200 -q -r "%%i" "!str:~0,-8!"
)

start /b /wait java -noverify -Xmx384M -cp .\lib\*;.\lib\ext\*%OTHER_LIB% ^
    -XX:NewRatio=50 -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions ^
    -XX:+AggressiveOpts -XX:MaxGCPauseMillis=400 -XX:GCPauseIntervalMillis=8000 ^
    -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dclient.encoding.override=UTF-8 ^
    -Duser.language=en -Duser.region=US -Duser.country=US -Dinput.encoding=UTF-8 ^
    -Doracle.net.tns_admin="%TNS_ADM%" org.dbcli.Loader %DBCLI_PARAMS% %*
EndLocal