#!/bin/bash
# usage: create_exa_external_tables.sh <dir path to of the extertnal directory>
# Please run "dbcli -g cell_group -l root -k" to setup the ssh authentication before executing this script
dir=$1

if [ "$1" = "" ] ; then
    echo "Please specify the target directory where the external tables link to." 1>&2
    exit 1
fi

mkdir -p $dir

cd $dir
echo "">NULL

cat >get_cell_group.sql<<!
    set feed off pages 0 head off echo off TRIMSPOOL ON
    spool cell_group
    SELECT  trim(b.name)
    FROM    v\$cell_config a,
            XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                    NAME VARCHAR2(300) path 'name') b
    WHERE  conftype = 'CELL'
    ORDER  BY 1;
    spool off
    create or replace directory EXA_SHELL as '`pwd`';
    GRANT READ,WRITE ON DIRECTORY EXA_SHELL to select_catalog_role;
    exit
!

sqlplus / as sysdba @get_cell_group
mv cell_group.lst cell_group
while IFS= read -r cell; do
    echo $cell > $cell
done <cell_group

sqlplus -s / as sysdba <<'EOF'
    set verify off
    drop table EXA$CACHED_OBJECTS;
    drop TABLE EXA$METRIC;
    drop TABLE EXA$ACTIVE_REQUESTS;
    drop TABLE EXA$METRIC_HISTORY;
    drop TABLE EXA$METRIC_HISTORY_1H;
    drop TABLE EXA$METRIC_HISTORY_1D;
    drop TABLE EXA$METRIC_HISTORY_10D;
    col cells new_value cells;
    col degree new_value degree;
	col locations new_value locations;
    
    SELECT case when v.ver >12.1 then 'PARTITION BY LIST(CELLNODE) ('||listagg(replace(q'[PARTITION @ VALUES('@') LOCATION ('@')]','@',b.name),','||chr(10)) WITHIN GROUP(ORDER BY b.name)||')' end cells,
	       case when v.ver <12.2 then 'LOCATION(''NULL'')' end locations,
           '(degree '||count(1)||')' degree
    FROM   (select regexp_substr(value,'\d+\.\d+')+0 ver from nls_database_parameters where parameter='NLS_RDBMS_VERSION') v,
	       v$cell_config a,
           XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                    NAME VARCHAR2(300) path 'name') b
    WHERE  conftype = 'CELL'
	GROUP  BY v.ver; 
    
    CREATE TABLE EXA$ACTIVE_REQUESTS
    (
        CELLNODE varchar2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getactiverequest.sh'
        FIELDS TERMINATED BY whitespace OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;
    
    CREATE TABLE EXA$CACHED_OBJECTS
    (
        CELLNODE VARCHAR2(20),
        CACHEDKEEPSIZE NUMBER,
        CACHEDSIZE NUMBER,
        CACHEDWRITESIZE NUMBER,
        COLUMNARCACHESIZE NUMBER,
        COLUMNARKEEPSIZE NUMBER,
        DBID NUMBER,
        DBUNIQUENAME VARCHAR2(30),
        HITCOUNT NUMBER,
        MISSCOUNT NUMBER,
        OBJECTNUMBER NUMBER,
        TABLESPACENUMBER NUMBER
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getfcobjects.sh'
        FIELDS TERMINATED BY  whitespace ldrtrim
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;
    
    
    CREATE TABLE EXA$METRIC
    (
        CELLNODE VARCHAR2(20),
        objectType VARCHAR2(20),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(15),
        metricValue NUMBER,
        Unit VARCHAR2(15)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getmetriccurrent.sh'
        FIELDS TERMINATED BY  '|' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;
    
    CREATE TABLE EXA$METRIC_HISTORY_1H
    (
        CELLNODE VARCHAR2(20),
        objectType VARCHAR2(20),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(15),
        metricValue NUMBER,
        Unit VARCHAR2(15)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getmetrichistory_1h.sh'
        FIELDS TERMINATED BY  '|' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;

    CREATE TABLE EXA$METRIC_HISTORY_1D
    (
        CELLNODE VARCHAR2(20),
        objectType VARCHAR2(20),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(15),
        metricValue NUMBER,
        Unit VARCHAR2(15)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 8388608
        PREPROCESSOR 'getmetrichistory_1d.sh'
        FIELDS TERMINATED BY  '|' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL  &degree &cells;

    CREATE TABLE EXA$METRIC_HISTORY_10D
    (
        CELLNODE VARCHAR2(20),
        objectType VARCHAR2(20),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(15),
        metricValue NUMBER,
        Unit VARCHAR2(15)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 67108864
        PREPROCESSOR 'getmetrichistory_10d.sh'
        FIELDS TERMINATED BY  '|' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;
    
    CREATE TABLE EXA$METRIC_HISTORY
    (
        CELLNODE VARCHAR2(20),
        objectType VARCHAR2(20),
        name VARCHAR2(40),
        alertState VARCHAR2(10),
        collectionTime TIMESTAMP WITH TIME ZONE,
        metricObjectName VARCHAR2(50),
        metricType VARCHAR2(15),
        metricValue NUMBER,
        Unit VARCHAR2(15)
    )
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_LOADER
      DEFAULT DIRECTORY EXA_SHELL
      ACCESS PARAMETERS
      ( RECORDS DELIMITED BY NEWLINE READSIZE 134217728
        PREPROCESSOR 'getmetrichistory.sh'
        FIELDS TERMINATED BY  '|' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &degree &cells;
    
    create or replace public synonym EXA$CACHED_OBJECTS for EXA$CACHED_OBJECTS;
    create or replace public synonym EXA$ACTIVE_REQUESTS for EXA$ACTIVE_REQUESTS;
    create or replace public synonym EXA$METRIC for EXA$METRIC;
    create or replace public synonym EXA$METRIC_HISTORY for EXA$METRIC_HISTORY;
    create or replace public synonym EXA$METRIC_HISTORY_1H for EXA$METRIC_HISTORY_1H;
    create or replace public synonym EXA$METRIC_HISTORY_1D for EXA$METRIC_HISTORY_1D;
    create or replace public synonym EXA$METRIC_HISTORY_10D for EXA$METRIC_HISTORY_10D;
    
    grant select on  EXA$CACHED_OBJECTS to select_catalog_role;
    grant select on  EXA$METRIC to select_catalog_role;
    grant select on  EXA$ACTIVE_REQUESTS to select_catalog_role;
    grant select on  EXA$METRIC_HISTORY to select_catalog_role;
    grant select on  EXA$METRIC_HISTORY_1H to select_catalog_role;
    grant select on  EXA$METRIC_HISTORY_1D to select_catalog_role;
    grant select on  EXA$METRIC_HISTORY_10D to select_catalog_role;
    
EOF

cat >cellcli.sh<<'!'
#!/bin/bash
ac=root
export PATH=$PATH:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin
. /etc/profile &> /dev/null
. ~/.bash_profile &> /dev/null
cd $(dirname $0)
rm -f *.bad *.log 2>/dev/null
cmd="cellcli -e $*"
cell=""
if [ -f "$1" ];then cmd=`head -1 $1`;fi
if [ -f "$2" ];then
  cell=`head -1 $2`
fi
if [ "$cell" = "" ]; then
  cmd=`echo $cmd|sed "s/|.*//"`
  cmd="dcli -g cell_group -l $ac $cmd"
  eval $cmd | sed 's/:/    /'
else
  cmd=`echo $cmd|sed "s/\\$cell/$cell/"`
  exec ssh $ac@$cell ${cmd}
fi
!

cat >getfcobjects.cli<<'!'
cellcli -e "list FLASHCACHECONTENT attributes CACHEDKEEPSIZE,CACHEDSIZE,CACHEDWRITESIZE,COLUMNARCACHESIZE,COLUMNARKEEPSIZE,DBID,DBUNIQUENAME,HITCOUNT,MISSCOUNT,OBJECTNUMBER,TABLESPACENUMBER" | awk -v c=$cell '{print c " " $0}'
!

cat >getfcobjects.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getfcobjects.cli $1
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

chmod +x *.sh
