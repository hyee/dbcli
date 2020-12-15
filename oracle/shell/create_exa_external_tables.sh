#!/bin/bash
# Usage: ./create_exa_external_tables.sh <dir path to of the extertnal directory> [cell ssh user] [sqlplus connect string]
dir=`realpath $1`
ssh_user=${2:-root}
db_account="${3:-/ as sysdba}"

if [ "$1" = "" ] ; then
    echo "Usage: create_exa_external_tables.sh <dir path to of the extertnal directory> [cell ssh user] [sqlplus connect string]" 1>&2
    exit 1
fi

if [ "$ORACLE_SID" = "" ] ; then
    echo "Environment variable \$ORACLE_SID is not found, please make sure the current OS user is correct." 1>&2
    exit 1
fi

unset TWO_TASK
echo "*****************************************"
echo "* Target database is : $ORACLE_SID       "
echo "*****************************************"

mkdir -p $dir
if [ ! -d "$dir" ]; then
    echo "Failed to mkdir directory $dir, exit." 1>&2
    exit 1
fi

chmod g+x $dir
cd $dir
echo "">EXA_NULL

cat >get_cell_group.sql<<!
    set feed off pages 0 head off echo off TRIMSPOOL ON
    PRO List of cell nodes:
    PRO ===================
    spool cell_group
    SELECT  trim(b.name)
    FROM    v\$cell_config a,
            XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                    NAME VARCHAR2(300) path 'name') b
    WHERE  conftype = 'CELL'
    ORDER  BY 1;
    spool off
    create or replace directory EXA_SHELL as '`pwd`';
    GRANT READ,EXECUTE ON DIRECTORY EXA_SHELL to select_catalog_role;
    PRO ===================
    PRO
    exit
!
rm -f cell_group.lst cell_group
sqlplus -l "$db_account" @get_cell_group

if [ ! -f "cell_group.lst" ]; then
    echo "Failed to build cell node list, exit." 1>&2
    exit 1
fi

mv cell_group.lst cell_group
while IFS= read -r cell; do
    echo $cell > $cell
done <cell_group

echo "Creating SSH Key-Based Authentication to $ssh_user@<cells nodes> ... "
echo =======================================================================
dcli -g cell_group -l $ssh_user -k

cat >cellcli.sh<<'!'
#!/bin/bash
ac=root
export PATH=$PATH:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin
. /etc/profile &> /dev/null
. ~/.bash_profile &> /dev/null
cd $(dirname $0)
rm -f EXA*.log*.bad EXA*.log 2>/dev/null
cmd="cellcli -e $*"
cell=""
if [ -f "$1" ];then cmd=`head -1 $1`;fi
if [ -f "$2" ];then
  cell=`head -1 $2`
fi
if [ "$cell" = "" ]; then
  if [ -f "$1" ];then
    while IFS= read -r cell; do
      cm=`echo $cmd|sed "s/\\$cell/$cell/"`
      exec ssh $ac@$cell ${cm} | grep --line-buffered '^' &
    done <cell_group
    wait
  else
    dcli -g cell_group -l $ac "$cmd" | sed 's/:/    /'
  fi
else
  cmd=`echo $cmd|sed "s/\\$cell/$cell/"`
  exec ssh $ac@$cell ${cmd}
fi
!

cat >celllua.sh<<'!'
#!/bin/bash
ac=root
export PATH=$PATH:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin
. /etc/profile &> /dev/null
. ~/.bash_profile &> /dev/null
cd $(dirname $0)
rm -f EXA*.log*.bad EXA*.log 2>/dev/null

script="$1"
shift
cell=""
if [ -f "$1" ];then
  cell=`head -1 $1`
  shift
fi

if [ "$cell" = "" ]; then
  while IFS= read -r cell; do
    cmd="lua $script $cell $*"
    exec ${cmd} | grep --line-buffered '^' & 
  done <cell_group
  wait
else
  cmd="lua $script $cell $*"
  exec ${cmd}
fi
!

cat >getcellparams.cli<<'!'
cellcli -e 'alter cell events="immediate cellsrv.cellsrv_dump('cellparams',1)'|grep trc|awk '{print "cat " $NF "; rm -f " $NF}'|sh|grep -P "^\S+ ="|sed 's/(default = \(.*\))/ \1/'|awk -v c=$cell '{print c "|" $1 "|" $3 "|" $4}'
!
cat >getcellparams.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getcellparams.cli $1
!

cat >getfcobjects.cli<<'!'
cellcli -e "list FLASHCACHECONTENT attributes DBID,DBUNIQUENAME,OBJECTNUMBER,TABLESPACENUMBER,CACHEDKEEPSIZE,CACHEDSIZE,CACHEDWRITESIZE,COLUMNARCACHESIZE,COLUMNARKEEPSIZE,HITCOUNT,MISSCOUNT,clusterName" | awk -v c=$cell '{print c " " $0}'
!

cat >getfcobjects.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getfcobjects.cli $1
!


cat >getpmemobjects.cli<<'!'
cellcli -e "list PMEMCACHECONTENT attributes  DBID,DBUNIQUENAME,OBJECTNUMBER,TABLESPACENUMBER,CACHEDKEEPSIZE,CACHEDSIZE,CACHEDWRITESIZE,COLUMNARCACHESIZE,COLUMNARKEEPSIZE,HITCOUNT,MISSCOUNT,clusterName" | awk -v c=$cell '{print c " " $0}'
!

cat >getpmemobjects.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getpmemobjects.cli $1
!


cat >getmetricdefinition.cli<<'!'
cellcli -e list metricdefinition attributes name,objecttype,metrictype,unit,description | sed 's/^[[:space:]]*//'
!
cat >getmetricdefinition.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetricdefinition.cli $1
!

cat >getmetriccurrent.cli<<'!'
cellcli -e LIST METRICCURRENT ATTRIBUTES objectType,name,alertState,collectionTime,metricObjectName,metricType,metricValue|awk -v c=$cell '{gsub(",","",$7);print c "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 " " $9 " " $10}'|egrep -v "\|[\.0]+\|"
!

cat >getmetriccurrent.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetriccurrent.cli $1
!


cat >getmetrichistory_1h.cli<<'!'
cellcli -e "LIST METRICHISTORY WHERE ageInMinutes < 61 ATTRIBUTES objectType,name,alertState,collectionTime,metricObjectName,metricType,metricValueAvg over 1"|awk -v c=$cell '{gsub(",","",$7);print c "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 " " $9 " " $10}'|egrep -v "\|[\.0]+\|"
!

cat >getmetrichistory_1h.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetrichistory_1h.cli $1
!

cat >getmetrichistory_1d.cli<<'!'
cellcli -e "LIST METRICHISTORY WHERE ageInMinutes < 1441 ATTRIBUTES objectType,name,alertState,collectionTime,metricObjectName,metricType,metricValueAvg over 1"|awk -v c=$cell '{gsub(",","",$7);print c "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 " " $9 " " $10}'|egrep -v "\|[\.0]+\|"
!

cat >getmetrichistory_1d.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetrichistory_1d.cli $1
!

cat >getmetrichistory_10d.cli<<'!'
cellcli -e "LIST METRICHISTORY WHERE ageInMinutes < 14401 ATTRIBUTES objectType,name,alertState,collectionTime,metricObjectName,metricType,metricValueAvg over 10"|awk -v c=$cell '{gsub(",","",$7);print c "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 " " $9 " " $10}'|egrep -v "\|[\.0]+\|"
!

cat >getmetrichistory_10d.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetrichistory_10d.cli $1
!

cat >getmetrichistory.cli<<'!'
cellcli -e "LIST METRICHISTORY ATTRIBUTES objectType,name,alertState,collectionTime,metricObjectName,metricType,metricValueAvg over 180"|awk -v c=$cell '{gsub(",","",$7);print c "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 " " $9 " " $10}'|egrep -v "\|[\.0]+\|"
!

cat >getmetrichistory.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getmetrichistory.cli $1
!

cat >getactiverequest.cli<<'!'
cellcli -e "list activerequest attributes ioType,requestState,dbID,dbName,sqlID,objectNumber,sessionID,sessionSerNumber,tableSpaceNumber,name,asmDiskGroupNumber,asmFileIncarnation,asmFileNumber,consumerGroupID,id,instanceNumber,ioBytes,ioBytesSofar,ioOffset,parentID,dbRequestID,ioReason,ioGridDisk"| awk -v c=$cell '{print c " " $0}'
!
cat >getactiverequest.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getactiverequest.cli $1
!

cat >getcelllist.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./celllua.sh celllist.lua $1
!

cat >getcellalert.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./celllua.sh cellalert.lua $1
!

cat >cellsrvstat.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./celllua.sh cellsrvstat.lua $1
!

cat >cellsrvstat_10s.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./celllua.sh cellsrvstat.lua "$1" 10
!

cat >celllist.lua<<'!'
#!/usr/bin/env lua
if not arg[1] or arg[1]=="" then
    io.stderr:write("Please input the target cell name.\n")
    os.exit(1)
end

function string.trim(s,sep)
    sep='[%s%z'..(sep or '')..']'
    return tostring(s):match('^'..sep..'*(.-)'..sep..'*$')
end

local cell,object,name=arg[1]:match('[^/]+$')
local cmd=([[ssh %s@%s 'cellcli -xml -n -x -e "list CELL detail;list CELLDISK detail;list DATABASE detail;list DISKMAP detail;list FLASHCACHE detail;list FLASHLOG detail;list GRIDDISK detail;list IBPORT detail;list LUN detail;list OFFLOADGROUP detail;list PHYSICALDISK detail;list PLUGGABLEDATABASE detail;list PMEMCACHE detail;list PMEMLOG detail;list QUARANTINE detail"']]):format('root',cell)
local fmt='"%s" | "%s" | "%s" | "%s" | "%s" | "%s"'

local escapes={
    ['&amp;']='&',
	['&apos;']="'",
    ['&lt;']='<',
    ['&gt;']='>',
    ['&quot;']=''
}

local pipe=io.popen(cmd, 'r')
if not pipe then
    print("execute cellcli on "..cell.." failed.")
    os.exit(1)
end
local output = pipe:read('*all')
pipe:close()
local kmg={
    T=1024*1024*1024*1024,
    G=1024*1024*1024,
    M=1024*1024,
    K=1024
}
for line in output:gmatch("[^\n\t]+") do
    local tag=line:match('<(.-)>')
    local node,value,typ=line:match('<(.-)>(.-)</%1>')
    if tag and tag~=node then object=tag:upper() end
    if tostring(node):lower()=='name' then
        name=value
    elseif node then
        value=value:gsub('&%w-;',escapes):trim()
        value=value:gsub('^(%d+)([GMTK])B?$',function(v,u) return v*kmg[u] end)
        if value=='' then 
            typ=''
        elseif value and tonumber(value) and not value:find('^0[xX]') then
            typ='NUMBER'
        elseif value:find('^%d%d%d%d%-%d%d?%-%d%d?T') then
            typ='TIMESTAMP'
        else
            typ='VARCHAR2'
        end
        print(fmt:format(cell,object,name,node,value,typ))
    end
end
!

cat >cellalert.lua<<'!'
#!/usr/bin/env lua
if not arg[1] or arg[1]=="" then
    io.stderr:write("Please input the target cell name.\n")
    os.exit(1)
end

function string.rtrim(s,sep)
    sep='[%s%z'..(sep or '')..']'
    return tostring(s):match('^(.-)'..sep..'*$')
end

local cell,tstamp=arg[1]:match('[^/]+$')
local cmd=([[ssh %s@%s 'tail -10000 $CELLTRACE/alert.log']]):format('root',cell)
local fmt='%s | %s | %s'

local pipe=io.popen(cmd, 'r')
if not pipe then
    print("execute command on "..cell.." failed.")
    os.exit(1)
end

local output = pipe:read('*all')
pipe:close()
for line in output:gmatch("[^\n\t]+") do
    line=line:rtrim()
    if line:find('^%d%d%d%d%-%d%d?%-%d%d?T') then
        tstamp=line
    elseif tstamp and line~="" then
        print(fmt:format(cell, tstamp,line:gsub('|',"l")))
    end
end
!

cat >cellsrvstat.lua<<'!'
#!/usr/bin/env lua

if not arg[1] or arg[1]=="" then
    io.stderr:write("Please input the target cell name.\n")
    os.exit(1)
end
local cell,secs=arg[1]:match('[^/]+$'),tonumber(arg[2])
local oflgrp,section,sub=''
function string.trim(s,sep)
    sep='[%s%z'..(sep or '')..']'
    return tostring(s):match('^'..sep..'*(.-)'..sep..'*$')
end

function string.rtrim(s,sep)
    sep='[%s%z'..(sep or '')..']'
    return tostring(s):match('^(.-)'..sep..'*$')
end

local fmt1='"%s" | "%s" | "%s" | "%s" | "" | %s'
local fmt2='"%s" | "%s" | "%s" | "%s" | "%s" | %s'
local pipe=io.popen("ssh root@"..cell.." cellsrvstat"..(not secs and '' or (' -count=2 -interval='..secs)), 'r')
if not pipe then
    print("execute cellsrvstat on "..cell.." failed.")
    os.exit(1)
end
local output = pipe:read('*all')
local found=0
pipe:close()
for line in output:gmatch("[^\n\t]+") do
    line=line:rtrim()
    if line~=""
       and not line:find('^ *END ')
       and not line:find('^ *OSS%- ')
       and not line:find('^ *Job types consuming most buffers')
       and not line:find('[%.%d]+ +[%.%d]+ +[%.%d]+ +[%.%d]+ *$')
       and not line:find('^ {8,}Total')then
        local sec=line:match('^ *==[= ]*([^=]-) *==')
        if sec then
            sec=sec:trim():gsub(' related stats$',''):gsub(' stats$','')
            section,oflgrp=sec,""
        end
        if sec=="Current Time" then
            if secs then
                found=found+1
            else
                found=2
            end
            if not secs then print(fmt2:format(cell,sec,"","",line:gsub('^.*= *',''):trim(),"")) end
        elseif found==2 and not sec then
            local item,cur,total=line:match("^(.-) +(%-?%d[%.%d]*) +(%-?%d[%.%d]*)$")
            if not item then
                item,total=line:match("^(.-) +(%-?%d[%.%d]*)$")
            elseif cur:find('^00') then
                item=item..': '..cur
            elseif secs then
                total=cur
            end
            item,total=(item or line):trim():gsub('"',"''"),tonumber(total)
            local grp=item:match('^Offload group name: *(%S+)')
            if grp then oflgrp=grp end
            if line:sub(1,2)~="  " then
                sub=item
                if total and (not secs or total~=0) then print(fmt1:format(cell,section,sub,oflgrp,total)) end
            elseif total and (not secs or total~=0) then
                print(fmt2:format(cell,section,sub,oflgrp,item,total))
            end
        end
    end
end
!
sed -i "s/root/$ssh_user/" cellcli.sh cellsrvstat.lua celllist.lua
chmod g+x get*.sh cell*.sh cell*.lua
chmod +x get*.sh cell*.sh cell*.lua

sqlplus -s "$db_account" <<'EOF'
    set verify off lines 150
    PRO
    PRO
    PRO Cleaning up residual EXA$* objects before setup
    PRO ===============================================
    begin
        for r in(select * from user_objects where object_name like 'EXA$%' and object_type in('VIEW','TABLE')) loop
            execute immediate 'drop '||r.object_type||' '||r.object_name;
        end loop;

        for r in(select * from dba_synonyms where table_name like 'EXA$%' and owner='PUBLIC') loop
            execute immediate 'drop public synonym '||r.synonym_name;
        end loop;
    end;
/

    col cells new_value cells noprint;
    col locations new_value locations noprint;
    col first_cell new_value first_cell noprint;
    col pivots new_value pivots noprint;
    col px new_value px noprint;
    col cl new_value cl noprint;
    define ver=122.2

    SELECT case when v.ver >=&ver then 'PARTITION BY LIST(CELLNODE) ('||listagg(replace(q'[PARTITION @ VALUES('@') LOCATION ('@')]','@',b.name),','||chr(10)) WITHIN GROUP(ORDER BY b.name)||')' end cells,
           case when v.ver >=&ver then 'PARALLEL' end PX,
           case when v.ver < &ver then 'LOCATION(''EXA_NULL'')' end locations,
           case when v.ver >11    then 'NOLOGFILE DISABLE_DIRECTORY_LINK_CHECK' end cl,
         --case when v.ver < &ver then 'LOCATION ('||listagg(''''||b.name||'''',',') within group(order by b.name)||')' end locations,
           listagg(replace(q'['@' "@"]','@',b.name),',') within group(order by b.name) pivots,
           min(b.name) first_cell
    FROM   (select regexp_substr(value,'\d+\.\d+')+0 ver from nls_database_parameters where parameter='NLS_RDBMS_VERSION') v,
           v$cell_config a,
           XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS NAME VARCHAR2(300) path 'name') b
    WHERE  conftype = 'CELL'
    GROUP  BY v.ver;
    
    
    PRO Creating table EXA$CELLPARAMS
    PRO ==================================
    CREATE TABLE EXA$CELLPARAMS
    (
        CELLNODE VARCHAR2(30),
        NAME VARCHAR2(100),
        VALUE VARCHAR2(100),
        DEFAULT_VALUE VARCHAR2(100)
    )
    ORGANIZATION EXTERNAL
     ( TYPE ORACLE_LOADER
       DEFAULT DIRECTORY EXA_SHELL
       ACCESS PARAMETERS
       ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
         PREPROCESSOR 'getcellparams.sh'  &cl
         FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
       ) &locations
     )
    REJECT LIMIT UNLIMITED &px &cells;
    
    PRO Creating table EXA$CELLCONFIG
    PRO ==================================
    CREATE TABLE EXA$CELLCONFIG
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        NAME VARCHAR2(100),
        FIELDNAME VARCHAR2(100),
        VALUE VARCHAR2(4000),
        DATATYPE VARCHAR2(20)
    )
    ORGANIZATION EXTERNAL
     ( TYPE ORACLE_LOADER
       DEFAULT DIRECTORY EXA_SHELL
       ACCESS PARAMETERS
       ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
         PREPROCESSOR 'getcelllist.sh'  &cl
         FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
       ) &locations
     )
    REJECT LIMIT UNLIMITED &px &cells;
    
    PRO Creating table EXA$ALERTLOG
    PRO ==================================
    CREATE TABLE EXA$ALERTLOG
    (
        CELLNODE VARCHAR2(30),
        tstamp TIMESTAMP WITH TIME ZONE,
        text VARCHAR2(1024)
    )
    ORGANIZATION EXTERNAL
     ( TYPE ORACLE_LOADER
       DEFAULT DIRECTORY EXA_SHELL
       ACCESS PARAMETERS
       ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
         PREPROCESSOR 'getcellalert.sh'  &cl
         FIELDS TERMINATED BY  '|' LRTRIM MISSING FIELD VALUES ARE NULL(
          CELLNODE,tstamp CHAR(32) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSxff6TZH:TZM',text
         )
       ) &locations
     )
    REJECT LIMIT UNLIMITED &px &cells;
    
    PRO Creating table EXA$ACTIVE_REQUESTS
    PRO ==================================
    CREATE TABLE EXA$ACTIVE_REQUESTS
    (
        CELLNODE VARCHAR2(30),
        ioType varchar2(30),
        requestState varchar2(50),
        dbID int,
        dbName varchar2(30),
        sqlID varchar2(15),
        objectNumber int,
        sessionID  int,
        sessionSerNumber  int,
        tableSpaceNumber int,
        name  int,
        asmDiskGroupNumber  int,
        asmFileIncarnation  int,
        asmFileNumber int,
        consumerGroupID  int,
        id  int,
        instanceNumber  int,
        ioBytes  int,
        ioBytesSofar  int,
        ioOffset  int,
        parentID  int,
        dbRequestID  int,
        ioReason varchar2(30),
        ioGridDisk varchar2(50)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getactiverequest.sh'  &cl
        FIELDS TERMINATED BY whitespace OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$CACHED_OBJECTS
    PRO =================================
    CREATE TABLE EXA$CACHED_OBJECTS
    (
        CELLNODE VARCHAR2(30),
        DBID NUMBER,
        DBUNIQUENAME VARCHAR2(128),
        OBJECTNUMBER NUMBER,
        TABLESPACENUMBER NUMBER,
        CACHEDKEEPSIZE NUMBER,
        CACHEDSIZE NUMBER,
        CACHEDWRITESIZE NUMBER,
        COLUMNARCACHESIZE NUMBER,
        COLUMNARKEEPSIZE NUMBER,
        HITCOUNT NUMBER,
        MISSCOUNT NUMBER
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getfcobjects.sh'  &cl
        FIELDS TERMINATED BY  whitespace LRTRIM
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;
    
    PRO Creating table EXA$PMEM_OBJECTS
    PRO =================================
    CREATE TABLE EXA$PMEM_OBJECTS
    (
        CELLNODE VARCHAR2(30),
        DBID NUMBER,
        DBUNIQUENAME VARCHAR2(128),
        OBJECTNUMBER NUMBER,
        TABLESPACENUMBER NUMBER,
        CACHEDKEEPSIZE NUMBER,
        CACHEDSIZE NUMBER,
        CACHEDWRITESIZE NUMBER,
        COLUMNARCACHESIZE NUMBER,
        COLUMNARKEEPSIZE NUMBER,
        HITCOUNT NUMBER,
        MISSCOUNT NUMBER
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getpmemobjects.sh'  &cl
        FIELDS TERMINATED BY  whitespace LRTRIM
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$CELLSRVSTAT
    PRO ==============================
    CREATE TABLE EXA$CELLSRVSTAT
    (
        CELLNODE VARCHAR2(30),
        CATEGORY VARCHAR2(100),
        NAME VARCHAR2(300),
        OFFLOAD_GROUP VARCHAR2(100),
        Item VARCHAR2(300),
        VALUE NUMBER
    )
    ORGANIZATION EXTERNAL
     ( TYPE ORACLE_LOADER
       DEFAULT DIRECTORY EXA_SHELL
       ACCESS PARAMETERS
       ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
         PREPROCESSOR 'cellsrvstat.sh'  &cl
         FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
       ) &locations
     )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$CELLSRVSTAT_10S
    PRO ==================================
    CREATE TABLE EXA$CELLSRVSTAT_10S
    (
     CELLNODE VARCHAR2(30),
     CATEGORY VARCHAR2(100),
     NAME VARCHAR2(300),
     OFFLOAD_GROUP VARCHAR2(100),
     Item VARCHAR2(300),
     VALUE NUMBER
    )
    ORGANIZATION EXTERNAL
     ( TYPE ORACLE_LOADER
       DEFAULT DIRECTORY EXA_SHELL
       ACCESS PARAMETERS
       ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
         PREPROCESSOR 'cellsrvstat_10s.sh'  &cl
         FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
       ) &locations
     )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$METRIC_DESC
    PRO ==============================
    CREATE TABLE EXA$METRIC_DESC
    (
        name VARCHAR2(40),
        objectType VARCHAR2(30),
        metricType VARCHAR2(30),
        Unit VARCHAR2(30),
        Description VARCHAR2(2000)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetricdefinition.sh'  &cl
        FIELDS TERMINATED BY  whitespace OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
      ) LOCATION('&first_cell')
    )
    REJECT LIMIT UNLIMITED;

    PRO Creating table EXA$METRIC
    PRO =========================
    CREATE TABLE EXA$METRIC
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(30),
        metricValue NUMBER,
        Unit VARCHAR2(30)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetriccurrent.sh'  &cl
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$METRIC_HISTORY_1H
    PRO ====================================
    CREATE TABLE EXA$METRIC_HISTORY_1H
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(30),
        metricValue NUMBER,
        Unit VARCHAR2(30)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetrichistory_1h.sh' &cl
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$METRIC_HISTORY_1D
    PRO ====================================
    CREATE TABLE EXA$METRIC_HISTORY_1D
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(30),
        metricValue NUMBER,
        Unit VARCHAR2(30)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetrichistory_1d.sh' &cl
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$METRIC_HISTORY_10D
    PRO =====================================
    CREATE TABLE EXA$METRIC_HISTORY_10D
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(30),
        metricValue NUMBER,
        Unit VARCHAR2(30)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetrichistory_10d.sh' &cl
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating table EXA$METRIC_HISTORY
    PRO =================================
    CREATE TABLE EXA$METRIC_HISTORY
    (
        CELLNODE VARCHAR2(30),
        objectType VARCHAR2(30),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(30),
        metricValue NUMBER,
        Unit VARCHAR2(30)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 1048576
        PREPROCESSOR 'getmetrichistory.sh' &cl
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' LRTRIM MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED &px &cells;

    PRO Creating views for EXA$ tables
    PRO ==============================
    CREATE OR REPLACE FORCE VIEW EXA$CELLPARAMS_AGG AS
        SELECT /*+opt_param('parallel_force_local' 'true')*/ *
        FROM   (SELECT CELLNODE c,NAME,trim(VALUE) v FROM EXA$CELLPARAMS) 
        PIVOT(MAX(v) FOR c IN(&pivots))
        ORDER BY 1,2,3,4;

    CREATE OR REPLACE VIEW EXA$METRIC_VW AS
        SELECT /*+leading(b) use_hash(b a)*/ A.*,B.DESCRIPTION
        FROM EXA$METRIC A,EXA$METRIC_DESC B WHERE A.NAME=B.NAME AND A.OBJECTTYPE=B.OBJECTTYPE;


    CREATE OR REPLACE FORCE VIEW EXA$METRIC_AGG AS
    SELECT /*+opt_param('parallel_force_local' 'true')use_hash(a b)*/ A.*,B.DESCRIPTION
    FROM (
        SELECT *
        FROM   (SELECT OBJECTTYPE,
                       NAME,
                       METRICOBJECT METRICOBJECTNAME,
                       METRICTYPE,
                       IS_AVG,
                       UNIT,
                       nvl(CELLNODE, 'TOTAL') c,
                       round(DECODE(IS_AVG, 'YES', AVG(METRICVALUE), SUM(METRICVALUE)), 2) v
                FROM   (SELECT A.*,
                               CASE
                                   WHEN trim(UNIT) IN ('us/request', '%', 'C') THEN
                                    'YES'
                                   ELSE
                                    'NO'
                               END IS_AVG,
                               regexp_replace(METRICOBJECTNAME,'_?'||cellnode,'',1,0,'i') METRICOBJECT
                        FROM   EXA$METRIC A)
                GROUP  BY OBJECTTYPE, NAME, METRICOBJECT, METRICTYPE, IS_AVG, UNIT, ROLLUP(CELLNODE))
        PIVOT(MAX(v) FOR c IN('TOTAL' TOTAL, &pivots))) A, EXA$METRIC_DESC B
    WHERE  A.OBJECTTYPE=B.OBJECTTYPE AND A.NAME=B.NAME
    ORDER  BY 1, 2, 3, 4;

    CREATE OR REPLACE FORCE VIEW EXA$CELLSRVSTAT_AGG AS
        SELECT /*+opt_param('parallel_force_local' 'true')*/ *
        FROM   (SELECT nvl(CELLNODE, 'TOTAL') cellnode,
                       CATEGORY,
                       NAME,
                       regexp_replace(ITEM,'_?'||cellnode,'',1,0,'i') item,
                       IS_AVG,
                       ROUND(decode(IS_AVG,'YES',AVG(VALUE),SUM(VALUE)),2) VALUE
                FROM   (SELECT A.*,
                               CASE
                                 WHEN regexp_like(NAME, '(avg|average|percentage)', 'i') OR
                                      (LOWER(NAME) LIKE '%util%' AND lower(NAME) NOT LIKE '% rate %util%') THEN
                                  'YES'
                                 ELSE
                                  'NO'
                               END IS_AVG
                       FROM exa$cellsrvstat a)
                GROUP  BY CATEGORY, NAME, regexp_replace(ITEM,'_?'||cellnode,'',1,0,'i'),IS_AVG,ROLLUP(cellnode))
        PIVOT(MAX(VALUE)
        FOR    cellnode IN('TOTAL' TOTAL, &pivots ))
        ORDER BY 1,2,3,4;

    CREATE OR REPLACE FORCE VIEW EXA$CELLSRVSTAT_10s_AGG AS
        SELECT /*+opt_param('parallel_force_local' 'true')*/ *
        FROM   (SELECT nvl(CELLNODE, 'TOTAL') cellnode,
                       CATEGORY,
                       NAME,
                       regexp_replace(ITEM,'_?'||cellnode,'',1,0,'i') item,
                       IS_AVG,
                       ROUND(decode(IS_AVG,'YES',AVG(VALUE),SUM(VALUE)),2) VALUE
                FROM   (SELECT A.*,
                               CASE
                                 WHEN regexp_like(NAME, '(avg|average|percentage)', 'i') OR
                                      (LOWER(NAME) LIKE '%util%' AND lower(NAME) NOT LIKE '% rate %util%') THEN
                                  'YES'
                                 ELSE
                                  'NO'
                               END IS_AVG
                       FROM exa$cellsrvstat_10s a)
                GROUP  BY CATEGORY, NAME, regexp_replace(ITEM,'_?'||cellnode,'',1,0,'i'),IS_AVG,ROLLUP(cellnode))
        PIVOT(MAX(VALUE)
        FOR    cellnode IN('TOTAL' TOTAL, &pivots ))
        ORDER BY 1,2,3,4;

    DECLARE
        NAME VARCHAR2(30);
        stmt VARCHAR2(32767);
        cols VARCHAR2(32767);
        DATA XMLTYPE;
        PROCEDURE pr IS
        BEGIN
            stmt := stmt || ' FROM EXA$CELLCONFIG WHERE OBJECTTYPE=''' || NAME || ''' GROUP BY CELLNODE,NAME ORDER BY 1,2';
            EXECUTE IMMEDIATE stmt;
        END;
    BEGIN
        SELECT XMLTYPE(CURSOR
                       (SELECT NAME,
                               objecttype typ,
                               'Type: ' || RPAD(nvl(METRICTYPE,' '), 15) || '  Unit: ' || RPAD(nvl(UNIT,' '), 15) || '  Desc: ' || DESCRIPTION d
                        FROM   EXA$METRIC_DESC))
        INTO   DATA
        FROM   dual;
        FOR r IN (SELECT typ, listagg(NAME, ',') WITHIN GROUP(ORDER BY NAME) cols
                  FROM   XMLTABLE('/ROWSET/ROW' PASSING DATA COLUMNS NAME PATH 'NAME', typ PATH 'TYP')
                  WHERE  length(regexp_replace(name,'^\w\w_'))<=30
                  GROUP  BY typ) LOOP
            NAME := SUBSTR('EXA$METRIC_' || r.typ, 1, 30);
            cols := regexp_replace(regexp_replace(r.cols, '([^,]+)', q'['\1' \1]'), ''' \w\w_', ''' ');
            stmt := 'create or replace view ' || NAME ||
                    ' as select /*+opt_param(''parallel_force_local'' ''true'')*/ * from (select CELLNODE,METRICOBJECTNAME OBJECTNAME,name n,METRICVALUE v from EXA$METRIC where objecttype=''' || r.typ ||
                    ''') pivot(sum(v) for n in(' || cols || '))';
            EXECUTE IMMEDIATE (stmt);

            FOR r1 IN (SELECT regexp_replace(NAME, '^\w\w_') n, d
                       FROM   XMLTABLE('/ROWSET/ROW' PASSING DATA COLUMNS NAME PATH 'NAME', typ PATH 'TYP', D PATH 'D')
                       WHERE  typ = r.typ) LOOP
                BEGIN
                       EXECUTE IMMEDIATE 'comment on column '||NAME||'.'||r1.n||' is q''['||r1.d||']''';
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END LOOP;
        END LOOP;
        
        NAME := ' ';
        FOR r IN (SELECT objecttype, FIELDNAME NAME, MIN(r) r, nvl(MAX(datatype), 'VARCHAR2') datatype,nvl(max(length(value)),0)+30 dlen
                  FROM   (SELECT a.*, ROWNUM r FROM EXA$CELLCONFIG a)
                  GROUP  BY objecttype, FIELDNAME
                  ORDER  BY objecttype, r) LOOP
            IF NAME != r.objecttype THEN
                IF NAME != ' ' THEN
                    pr;
                END IF;
                NAME := r.objecttype;
                stmt := 'CREATE OR REPLACE FORCE VIEW EXA$' || NAME || ' AS SELECT /*+opt_param(''parallel_force_local'' ''true'')*/ CELLNODE,NAME';
            END IF;
            stmt := stmt || ',MAX(DECODE(FIELDNAME,''' || r.name || ''',' || CASE r.datatype
                        WHEN 'NUMBER' THEN
                         'VALUE+0'
                        WHEN 'TIMESTAMP' THEN
                         'to_timestamp_tz(value,''YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'')'
                        ELSE
                         'CAST(VALUE AS VARCHAR2('||r.dlen||'))'
                    END || ')) "' || substr(r.name,1,30) || '"';
        END LOOP;
        pr;
    END;
/
    PRO Granting access rights ...
    PRO ==========================
    begin
        for r in(select * from user_objects where object_name like 'EXA$%' and object_type in('TABLE','VIEW')) loop
            execute immediate 'create or replace public synonym '||r.object_name||' for '||r.object_name;
            execute immediate 'grant select on '||r.object_name||' to select_catalog_role';
        end loop;
    end;
/
    --remove those metric history tables since they could impact the auto stats gathering
    PRO Dropping time-consuming EXA$METRIC_HISTORY tables
    PRO =================================================
    drop table EXA$METRIC_HISTORY_1H;
    drop table EXA$METRIC_HISTORY_1D;
    drop table EXA$METRIC_HISTORY_10D;
    drop table EXA$METRIC_HISTORY;
    drop public synonym EXA$METRIC_HISTORY_1H;
    drop public synonym EXA$METRIC_HISTORY_1D;
    drop public synonym EXA$METRIC_HISTORY_10D;
    drop public synonym EXA$METRIC_HISTORY;

    PRO List of EXA$ objects:
    PRO ====================================================
    SET PAGESIZE 99
    COL OWNER for a10
    COL OBJECT_NAME FOR a30
    COL OBJECT_TYPE FOR a11
    SELECT OBJECT_NAME,OBJECT_TYPE
    FROM   USER_OBJECTS
    WHERE  OBJECT_NAME LIKE 'EXA$%'
    AND    SUBOBJECT_NAME IS NULL
    ORDER  BY 1;

    --gather and lock stats
    PRO LAST STEP: Gathering and locking EXA table stats, please make sure the grid user has the access to the target directory ...
    PRO ====================================================
    begin
        for r in(select * from user_tables where table_name like 'EXA$%') loop
            dbms_stats.gather_table_stats(user,r.table_name,degree=>16);
            dbms_stats.lock_table_stats(user,r.table_name);
        end loop;
    end;
/

EOF