DBCLI doesn't include the dependent libs for MYSQL due to size consideration. Please take following action before use:
1. Download mysql connector from http://dev.mysql.com/downloads/connector/j/, and extract the jar file into this dir
2. Make sure mysql.exe can be found in your pc, and add its path into the EXT_PATH variable of file 'data\init.cfg'.
3. launch dbcli.bat, and execute 'set -p platform mysql' to permanently switch to mysql platform 