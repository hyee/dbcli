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
echo "">EXA_NULL

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
    set verify off lines 150
	begin
		for r in(select * from user_objects where object_name like 'EXA$%' and object_type in('VIEW','TABLE')) loop
			execute immediate 'drop '||r.object_type||' '||r.object_name;
		end loop;
		
		for r in(select * from dba_synonyms where table_name like 'EXA$%' and owner='PUBLIC') loop
			execute immediate 'drop public synonym '||r.synonym_name;
		end loop;
		
	end;
/
    col cells new_value cells;
    col locations new_value locations;
    col first_cell new_value first_cell;
    
    SELECT case when v.ver >12.1 then 'PARTITION BY LIST(CELLNODE) ('||listagg(replace(q'[PARTITION @ VALUES('@') LOCATION ('@')]','@',b.name),','||chr(10)) WITHIN GROUP(ORDER BY b.name)||')' end cells,
           case when v.ver <12.2 then 'LOCATION ('||listagg(''''||b.name||'''',',') within group(order by b.name)||')' end locations,
           min(b.name) first_cell
    FROM   (select regexp_substr(value,'\d+\.\d+')+0 ver from nls_database_parameters where parameter='NLS_RDBMS_VERSION') v,
           v$cell_config a,
           XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                    NAME VARCHAR2(300) path 'name') b
    WHERE  conftype = 'CELL'
    GROUP  BY v.ver; 
    
	PRO Creating table EXA$ACTIVE_REQUESTS
	PRO =====================================
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
    REJECT LIMIT UNLIMITED PARALLEL &cells;

	PRO Creating table EXA$CACHED_OBJECTS
	PRO =====================================
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
    REJECT LIMIT UNLIMITED PARALLEL &cells;
	
	PRO Creating table EXA$METRIC_DESC
	PRO =====================================
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getmetricdefinition.sh'
        FIELDS TERMINATED BY  whitespace OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
      ) LOCATION('&first_cell')
    )
    REJECT LIMIT UNLIMITED;

	PRO Creating table EXA$METRIC
	PRO =====================================  
    CREATE TABLE EXA$METRIC
    (
        CELLNODE VARCHAR2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getmetriccurrent.sh'
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &cells;
	
	PRO Creating table EXA$METRIC_HISTORY_1H
	PRO =====================================  
    CREATE TABLE EXA$METRIC_HISTORY_1H
    (
        CELLNODE VARCHAR2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 4194304
        PREPROCESSOR 'getmetrichistory_1h.sh'
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &cells;

	PRO Creating table EXA$METRIC_HISTORY_1D
	PRO =====================================  
    CREATE TABLE EXA$METRIC_HISTORY_1D
    (
        CELLNODE VARCHAR2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 8388608
        PREPROCESSOR 'getmetrichistory_1d.sh'
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL  &cells;

	PRO Creating table EXA$METRIC_HISTORY_10D
	PRO =====================================  
    CREATE TABLE EXA$METRIC_HISTORY_10D
    (
        CELLNODE VARCHAR2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 67108864
        PREPROCESSOR 'getmetrichistory_10d.sh'
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &cells;
	
	PRO Creating table EXA$METRIC_HISTORY
	PRO ===================================== 
    CREATE TABLE EXA$METRIC_HISTORY
    (
        CELLNODE VARCHAR2(20),
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
      ( RECORDS DELIMITED BY NEWLINE READSIZE 134217728
        PREPROCESSOR 'getmetrichistory.sh'
        FIELDS TERMINATED BY  '|' OPTIONALLY ENCLOSED BY '"' ldrtrim MISSING FIELD VALUES ARE NULL
        (CELLNODE,objectType,name,alertState,
         collectionTime CHAR(25) date_format  TIMESTAMP WITH TIME ZONE MASK 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM',
         metricObjectName,metricType,metricValue,Unit
         )
      ) &locations
    )
    REJECT LIMIT UNLIMITED PARALLEL &cells;
	CREATE OR REPLACE VIEW EXA$METRIC_VW AS 
	SELECT /*+leading(b) use_hash(b a)*/ A.*,B.DESCRIPTION 
	FROM EXA$METRIC A,EXA$METRIC_DESC B WHERE A.NAME=B.NAME AND A.OBJECTTYPE=B.OBJECTTYPE
/

	DECLARE
		NAME VARCHAR2(30);
		stmt VARCHAR2(32767);
		cols VARCHAR2(32767);
		DATA XMLTYPE;
	BEGIN
		SELECT XMLTYPE(CURSOR
					   (SELECT NAME,
							   objecttype typ,
							   'Type: ' || RPAD(METRICTYPE, 15) || '  Unit: ' || RPAD(UNIT, 15) || '  Desc: ' || DESCRIPTION d
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
					' as select * from (select CELLNODE,name n,METRICVALUE v from EXA$METRIC where objecttype=''' || r.typ ||
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
	END;
	/

	begin
		for r in(select * from user_objects where object_name like 'EXA$%' and object_type in('TABLE','VIEW')) loop
			execute immediate 'create or replace public synonym '||r.object_name||' for '||r.object_name;
			execute immediate 'grant select on '||r.object_name||' to select_catalog_role';
		end loop;
	end;
/
    
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
  if [ -f "$1" ];then
    while IFS= read -r cell; do
      cm=`echo $cmd|sed "s/\\$cell/$cell/"`
      eval ssh $ac@$cell ${cmd} &
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

cat >getfcobjects.cli<<'!'
cellcli -e "list FLASHCACHECONTENT attributes CACHEDKEEPSIZE,CACHEDSIZE,CACHEDWRITESIZE,COLUMNARCACHESIZE,COLUMNARKEEPSIZE,DBID,DBUNIQUENAME,HITCOUNT,MISSCOUNT,OBJECTNUMBER,TABLESPACENUMBER" | awk -v c=$cell '{print c " " $0}'
!

cat >getfcobjects.sh<<'!'
export PATH=$PATH:/usr/bin;cd $(dirname $0)
./cellcli.sh getfcobjects.cli $1
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

chmod +x *.sh

sqlplus / as sysdba <<'!'
    --remove those metric history tables since they could impact the auto stats gathering
    drop table EXA$METRIC_HISTORY_1H;
    drop table EXA$METRIC_HISTORY_1D;
    drop table EXA$METRIC_HISTORY_10D;
    drop table EXA$METRIC_HISTORY;
    --gather and lock stats
	begin
		for r in(select * from user_tables where table_name like 'EXA$%') loop
		    dbms_stats.gather_table_stats(user,r.table_name,degree=>16);
			dbms_stats.lock_table_stats(user,r.table_name);
		end loop;
	end;
/

!
