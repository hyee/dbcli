@echo off
cd /d "%~dp0"

rem set font and background color
color 0A
rem color F0


SET JRE_HOME=C:\Program Files\Java\jre7\bin
SET TNS_ADM=d:\Oracle\product\11.2.0\client\network\admin

If not exist "%TNSADM%\tnsnames.ora" if Defined ORACLE_HOME (set TNS_ADM=%ORACLE_HOME%\network\admin) 
IF not exist "%JRE_HOME%\java.exe" (set JRE_HOME=.\jre\bin)

SET PATH=%JRE_HOME%;%PATH%

java -Xmx64M -Dfile.encoding=UTF-8 -cp .\lib\.;.\lib\jline.jar;.\lib\jnlua-0.9.6.jar%OTHER_LIB% ^
             -Djava.library.path=.\lib\ ^
             -Doracle.net.tns_admin="%TNS_ADM%" ^
             Loader ^
             %*