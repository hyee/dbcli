@echo off
Setlocal EnableDelayedExpansion
cd /d "%~dp0"

rem set font and background color
color 0A
rem color F0

SET JRE_HOME=d:\java\jre\bin
rem SET JRE_HOME=D:\Java\jre\bin
SET TNS_ADM=d:\Oracle\product\network\admin

If not exist "%TNSADM%\tnsnames.ora" if Defined ORACLE_HOME (set TNS_ADM=%ORACLE_HOME%\network\admin) 
IF not exist "%JRE_HOME%\java.exe" (set JRE_HOME=.\jre\bin)

SET PATH=%JRE_HOME%;%PATH%

for /r %%i in (*.pack.gz) do (
  set "var=%%i" &set "str=!var:@=!"
  unpack200 -q -r "%%i" "!str:~0,-8!"
)

java -noverify -Xmx128M -cp .\lib\*%OTHER_LIB% ^
     -XX:-UseAdaptiveSizePolicy -XX:+UseParallelGC ^
     -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Dclient.encoding.override=UTF-8 -Duser.language=en -Duser.region=US -Duser.country=US ^
     -Doracle.net.tns_admin="%TNS_ADM%" org.dbcli.Loader %*