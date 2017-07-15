#!/bin/bash
# Java executable is required
cd "$(dirname "$0")"
if [ "$TNS_ADM" = "" ]; then
    export TNS_ADM="$ORACLE_HOME/network/admin"
fi

export LD_LIBRARY_PATH=./lib/linux:$LD_LIBRARY_PATH
export DBCLI_ENCODING=UTF-8

if [[ -r ./data/init.conf ]]; then
    source ./data/init.conf
elif [[ -r ./data/init.cfg ]]; then
    source ./data/init.cfg
fi


# find executable java program
if [[ -n "$JRE_HOME" ]] && [[ -x "$JRE_HOME/bin/java" ]];  then
    _java="$JRE_HOME/bin/java"
elif type -p java &>/dev/null; then
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then    
    _java="$JAVA_HOME/bin/java"
fi

found=0
if [[ "$_java" ]]; then
    found=2
    version=$("$_java" -version 2>&1)
    ver=$(echo $version | awk -F '"' '/version/ {print $2}')
    
    if [[ "$ver" < "1.8" ]]; then
        found=1
    fi
    echo $version|grep "64-Bit" &>/dev/null ||  found=1
fi

if [[ $found < 2 ]]; then
    if [[ -x ./jre_linux/bin/java ]];  then
        _java=./jre_linux/bin/java
    else
        echo "Cannot find java 1.8 64-bit executable, exit."
        exit 1
    fi
fi

unset _JAVA_OPTIONS
unset JAVA_HOME

# unpack jar files for the first use
for f in `find . -type f -name "*.pack.gz" 2>/dev/null`; do
  echo "Unpacking $f ..."
  unpack200 -q -r  $f $(echo $f|sed 's/\.pack\.gz//g') &
done
wait

umask 000
"$_java" -noverify -Xmx384M  -cp .:lib/*:lib/ext/*$OTHER_LIB -XX:+UseG1GC -XX:+UseStringDeduplication \
    -Dfile.encoding=$DBCLI_ENCODING -Duser.language=en -Duser.region=US -Duser.country=US \
    -Djava.awt.headless=true org.dbcli.Loader $*