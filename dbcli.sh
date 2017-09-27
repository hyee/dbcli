#!/bin/bash
# Java executable is required

cd "$(dirname "$0")"
os=$(uname)

if [ "$os" = "Darwin" ]; then
    os="mac"
else
    os="linux"
fi

if [ "$TNS_ADM" = "" ] ; then
    DBCLI_ENCODING=UTF-8
fi

if [ "$TNS_ADM" = "" ] && [[ -n "$ORACLE_HOME" ]] ; then
    export TNS_ADM="$ORACLE_HOME/network/admin"
fi

if [[ -r ./data/init.conf ]]; then
    source ./data/init.conf
elif [[ -r ./data/init.cfg ]]; then
    source ./data/init.cfg
fi

if [[ "$EXT_PATH" ]]; then
    export PATH=$EXT_PATH:$PATH
fi

# find executable java program
if [[ -n "$JRE_HOME" ]] && [[ -x "$JRE_HOME/bin/java" ]];  then
    _java="$JRE_HOME/bin/java"
elif type -p java &>/dev/null; then
    _java="`type -p java`"
    if [ "$os" = "mac" ]; then
        _java=$(/usr/libexec/java_home)/bin/java
    else
        _java=$(readlink -f "$_java")
    fi
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then    
    _java="$JAVA_HOME/bin/java"
fi

# find executable java program
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

chmod  777 ./jre_$os/bin/* &>/dev/null
if [[ $found < 2 ]]; then
    if [[ -x ./jre_$os/bin/java ]];  then
        _java=./jre_$os/bin/java
    else
        echo "Cannot find java 1.8 64-bit executable, exit."
        exit 1
    fi
fi

unset _JAVA_OPTIONS JAVA_HOME

JAVA_BIN="$(echo "$_java"|sed 's|/[^/]*$||')"
JAVA_ROOT="$(echo "$JAVA_BIN"|sed 's|/[^/]*$||')"

if [[ -r "$JAVA_ROOT/jre" ]]; then
    JAVA_BIN="$JAVA_ROOT/jre/bin"
    JAVA_ROOT="$JAVA_ROOT/jre"
fi

export LUA_CPATH="./lib/$os/?.so;./lib/$os/?.dylib"
export LD_LIBRARY_PATH="./lib/$os:$JAVA_ROOT/bin:$JAVA_ROOT/lib:$JAVA_ROOT/lib/jli:$JAVA_ROOT/lib/server:$JAVA_ROOT/lib/amd64:$JAVA_ROOT/lib/amd64/server"

if [[ "$ORACLE_HOME" ]]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ORACLE_HOME/lib"
fi

# unpack jar files for the first use
unpack="$JAVA_ROOT/bin/unpack200"
if [[ -x ./jre_$ox/bin/unpack200 ]]; then
    unpack=./jre_$ox/bin/unpack200
elif [ ! -x "$unpack" ]; then
    echo "Cannot find unpack200 executable, exit."
    exit 1
fi

for f in `find . -type f -name "*.pack.gz" 2>/dev/null`; do
    echo "Unpacking $f ..."
    "$unpack" -q -r  $f $(echo $f|sed 's/\.pack\.gz//g') &
done
wait

chmod  777 ./lib/$os/luajit &>/dev/null
./lib/$os/luajit ./lib/bootstrap.lua "$_java" $*