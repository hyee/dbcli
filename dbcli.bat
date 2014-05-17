@echo off
cd /d "%~dp0"
SET JRE_HOME=C:\Program Files (x86)\Java\jdk7\jre\bin;
SET TNS_ADM=C:\Oracle\product\11.2.0\client_1\network\admin

SET PATH=%JRE_HOME%;%PATH%
java -server -Xmx32M -cp .\lib\.;.\lib\jnlua-0.9.6.jar ^
               -Djava.library.path=.\lib\ ^
               -Doracle.net.tns_admin="%TNS_ADM%" ^
               Loader ^
               %*