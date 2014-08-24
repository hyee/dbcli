@echo off
cd /d "%~dp0"
SET JRE_HOME=C:\Program Files (x86)\Java\jre7\bin
SET TNS_ADM=d:\Oracle\product\11.2.0\client\network\admin
SET PATH=%JRE_HOME%;%PATH%

java -Xmx32M -cp .\lib\.;.\lib\jnlua-0.9.6.jar%OTHER_LIB% ^
               -Djava.library.path=.\lib\ ^
               -Doracle.net.tns_admin="%TNS_ADM%" ^
               Loader ^
               %*