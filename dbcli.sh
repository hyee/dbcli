#!/bin/bash
# Java executable is required
cd "$(dirname "$0")"
if [ "$TNS_ADM" = "" ]; then
    export TNS_ADM="$ORACLE_HOME/network/admin"
fi

export LD_LIBRARY_PATH=./lib/linux:$LD_LIBRARY_PATH
export DBCLI_ENCODING=UTF-8

if [ "$TNS_ADM" = "" ]; then
    export TNS_ADM="$ORACLE_HOME/network/admin"
fi

# find executable java program
if [[ -n "$JRE_HOME" ]] && [[ -x "$JRE_HOME/bin/java" ]];  then
    _java="$JRE_HOME/bin/java"
elif type -p java &>/dev/null; then
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then    
    _java="$JAVA_HOME/bin/java"
else
    echo >&2 'Aborted due to could not find "java" executable in your $PATH. '
    exit 1
fi

version=$("$_java" -version 2>&1)

ver=$(echo $version | awk -F '"' '/version/ {print $2}')

if [[ "$ver" < "1.8" ]]; then
    echo >&2 'Aborted due to java version less than 1.8'
    exit 1
fi

echo $version|grep "64-Bit" &>/dev/null ||  { echo >&2 "Aborted due to $_java is not a 64-bit executable program."; exit 1; } 

unset _JAVA_OPTIONS

"$_java" -noverify -Xmx384M  -cp .:lib/* -XX:+UseG1GC -XX:+UseStringDeduplication \
    -Dfile.encoding=$DBCLI_ENCODING -Duser.language=en -Duser.region=US -Duser.country=US \
    -Doracle.net.tns_admin="$TNS_ADM" org.dbcli.Loader $*