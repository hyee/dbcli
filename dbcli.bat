@echo off
cd /d "%~dp0"

rem set font and background color
color 0A
rem color F0

SET JRE_HOME=D:\java\jre\bin
rem SET JRE_HOME=D:\Java\jre\bin
SET TNS_ADM=d:\Oracle\product\network\admin

If not exist "%TNSADM%\tnsnames.ora" if Defined ORACLE_HOME (set TNS_ADM=%ORACLE_HOME%\network\admin) 
IF not exist "%JRE_HOME%\java.exe" (set JRE_HOME=.\jre\bin)

SET PATH=%JRE_HOME%;%PATH%

java -Xmx128M -cp .\lib\*%OTHER_LIB% ^
     -XX:-UseAdaptiveSizePolicy -XX:+UseParallelGC ^
     -Dfile.encoding=UTF-8 -Doracle.net.tns_admin="%TNS_ADM%" ^
     org.dbcli.Loader %*