#!/bin/bash

if [ ! "$BASH" ] ; then
    echo "  Please do not use 'sh' to run this script, just execute with 'bash'." 1>&2
    exit 1
fi

pushd "$(dirname "$0")" > /dev/null
os=$(uname -a)
if [[ "$os" =~ Darwin.*ARM ]]; then
    os="mac-arm"
elif [[ "$os" = *Darwin* ]]; then
    os="mac"
elif [[ "$os" =~ Linux.*x86 ]]; then
    os="linux"
    bind 'set enable-bracketed-paste on' &>/dev/null
elif [[ "$os" =~ Linux.* ]]; then
    os="linux-arm"
    bind 'set enable-bracketed-paste on' &>/dev/null
fi

#DBCLI_ENCODING=UTF-8

if [ "$TNS_ADMIN" = "" ] && [[ -n "$ORACLE_HOME" ]] ; then
    export TNS_ADMIN="$ORACLE_HOME/network/admin"
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
if [[ -n "$JDK_HOME" ]] && [[ -x "$JDK_HOME/bin/java" ]];  then
    _java="$JDK_HOME/bin/java"
elif [[ -n "$JRE_HOME" ]] && [[ -x "$JRE_HOME/bin/java" ]];  then
    _java="$JRE_HOME/bin/java"
elif type -p java &>/dev/null; then
    if [[ "$os" = mac* ]]; then
        unset JAVA_VERSION
        if [ "$os" = "mac" ]; then
            _java=`/usr/libexec/java_home -V 2>&1|egrep "^\s+\d"|grep -oh "/Library.*"|head -1`
        else
            _java=`/usr/libexec/java_home -V 2>&1|egrep "^\s+\d.+arm64"|grep -oh "/Library.*"|head -1`
        fi
        if [[ "$_java" ]]; then
            _java="$_java/bin/java"
        elif [ "$os" = "mac-arm" ]; then
            echo "Cannot find Java 8 - Java 20 executable for ARM-64, please manually set JRE_HOME for suitable JDK/JRE."
            popd
            exit 1
        fi
    else
        _java=$(readlink -f "`type -p java`")
    fi
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then    
    _java="$JAVA_HOME/bin/java"
fi

# find executable java program
found=0
if [[ "$_java" ]]; then
    found=2
    info=$("$_java" -XshowSettings:properties 2>&1)
    bit=$(echo "$info"|grep "sun.arch.data.model"|awk '{print $3}')
    ver=$(echo "$info"|grep "java.class.version" |awk '{print $3}')

    if [[ "$ver" < "52.0" ]] || [[ "$ver" > "64.0" ]] || [[ "$bit" != "64" ]]; then
        found=1
    fi
fi


if [[ $found < 2 ]]; then
    if [[ -f ./jre_$os/bin/unpack200 ]];  then
        _java=./jre_$os/bin/java
        ver="52"
    else
        echo "Cannot find Java 8 - Java 20 for X86-64, please manually set JRE_HOME for suitable JDK/JRE."
        exit 1
    fi
fi

unset _JAVA_OPTIONS JAVA_HOME DYLD_FALLBACK_LIBRARY_PATH DYLD_LIBRARY_PATH

JAVA_BIN="$(echo "$_java"|sed 's|/[^/]*$||')"
JAVA_ROOT="$(echo "$JAVA_BIN"|sed 's|/[^/]*$||')"

if [[ -r "$JAVA_ROOT/jre" ]]; then
    JAVA_BIN="$JAVA_ROOT/jre/bin"
    JAVA_ROOT="$JAVA_ROOT/jre"
fi

export LUA_CPATH="./lib/$os/?.so;./lib/$os/?.dylib"
export LD_LIBRARY_PATH="./lib/$os:$JAVA_ROOT/bin:$JAVA_ROOT/lib:$JAVA_ROOT/lib/jli:$JAVA_ROOT/lib/server:$JAVA_ROOT/lib/amd64:$JAVA_ROOT/lib/amd64/server:$LD_LIBRARY_PATH"

#used for JNA
if [ -f "$JAVA_ROOT/lib/amd64/libjsig.so" ] && [ $found = 2 ]; then
    export LD_PRELOAD="$JAVA_ROOT/lib/amd64/libjsig.so:$JAVA_ROOT/lib/amd64/jli/libjli.so" 
elif [[ -f "$JAVA_ROOT/lib/libjsig.dylib" ]]; then
    export LD_PRELOAD="$JAVA_ROOT/lib/libjsig.dylib:$JAVA_ROOT/lib/jli/libjli.dylib"
    export DYLD_PRELOAD="$LD_PRELOAD"
fi

if [[ "$ORACLE_HOME" ]]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ORACLE_HOME/lib:$ORACLE_HOME"
fi

if [[ "$os" = mac* ]]; then
    export DYLD_FALLBACK_LIBRARY_PATH="$LD_LIBRARY_PATH"
fi
# unpack jar files for the first use
unpack="$JAVA_ROOT/bin/unpack200"
if [[ -f ./jre_$os/bin/unpack200 ]]; then
    unpack=./jre_$os/bin/unpack200
    if [ ! -x "$unpack" ]; then
        chmod  +x ./jre_$os/bin/* &>/dev/null
    fi
elif [ ! -x "$unpack" ]; then
    echo "Cannot find unpack200 executable, exit."
    popd
    exit 1
fi

for f in `find . -type f -name "*.pack.gz" 2>/dev/null | egrep -v "cache|dump"`; do
    echo "Unpacking $f ..."
    "$unpack" -q -r  $f $(echo $f|sed 's/\.pack\.gz//g') &
done
wait

trap '' TSTP &>/dev/null

chmod  +x ./lib/$os/luajit &>/dev/null
exec -a "dbcli" ./lib/$os/luajit ./lib/bootstrap.lua "$_java" "$ver" "$@"
popd