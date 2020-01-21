/*[[
  Show top objects in flashcache contents based on external table EXA$CACHED_OBJECTS. Usage: @@NAME [hits|misses|cachesize|<keyword>] [-detail|-group]
	This script relies on external table EXA$CACHED_OBJECTS which is created by shell script "oracle/shell/create_exa_external_tables.sh" with the oracle user
	
	Parameters:
		* hits|misses|cachedsize: order by column, defaults as order by hits desc
		* -detail: don't group the data,instead, show the details of each cell
    * -group : group the data by object name

	Sample output:
	==============
    SQL> @@NAME SYS
    OWNER      OBJECT_NAME       SUBOBJECT_NAME    OBJECT_TYPE     OBJECT_ID DATA_OBJECT_ID RECS CELLS Reqs Hits Hit% Misses CachedSize ColumnarCache ColumnarCache% CachedWrite CachedKeep ColumnarKeep
    ----- ---------------------- -------------- ------------------ --------- -------------- ---- ----- ---- ---- ---- ------ ---------- ------------- -------------- ----------- ---------- ------------
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP2301   TABLE SUBPARTITION    106117        1022957    3     3  0    0           0      6.44 MB       6.44 MB        100.00%        0  B       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6496   TABLE SUBPARTITION    117210        1022956    4     4  0    0           0      5.19 MB       5.19 MB        100.00%        0  B       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6421   TABLE SUBPARTITION    117002        1022960    4     4  0    0           0      5.00 MB       5.00 MB        100.00%        0  B       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6645   TABLE SUBPARTITION    117537        1022959    5     5  0    0           0      4.87 MB       4.87 MB        100.00%        0  B       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6653   TABLE SUBPARTITION    117545        1022958    5     5  0    0           0      4.81 MB       4.81 MB        100.00%        0  B       0  B         0  B
    
  --[[
      @check_access_obj: EXA$CACHED_OBJECTS={}
  		&grp1: default={COUNT(1) recs,COUNT(DISTINCT CELLNODE) cells} detail={cellnode,TABLESPACENUMBER TS#} 
  		&grp2: default={} detail={,CELLNODE,TABLESPACENUMBER}
      &grp3: {
            default={owner, nvl(object_name,'DB: '||dbuniquename) object_name, subobject_name, object_type, object_id, b.*} 
            group={owner,nvl(object_name,'DB: '||dbuniquename) object_name,regexp_substr(object_type,'^\S+') object_type,
                   count(1)    "SEGS",
                   SUM("RECS") "RECS",
                   MAX("CELLS") "CELLS",
                   SUM("Reqs") "Reqs",
                   SUM("Hits") "Hits",
                   SUM("Hits")/NULLIF(SUM("Reqs"),0) "Hit%",
                   SUM("Misses") "Misses",
                   SUM("CachedSize") "CachedSize",
                   SUM("ColumnarCache") "ColumnarCache",
                   SUM("ColumnarCache")/NULLIF(SUM("CachedSize"),0) "ColumnarCache%",
                   SUM("CachedWrite") "CachedWrite",
                   SUM("CachedKeep") "CachedKeep",
                   SUM("ColumnarKeep") "ColumnarKeep"
            }
      }
      &grp4: {
          default={}
          group={group by type,owner,nvl(object_name,'DB: '||dbuniquename),regexp_substr(object_type,'^\S+') }
      }
	--]]
]]*/

col CACHEDSIZE,cachedwrite,cachedkeep,columnarkeep,columnarcache for kmg
col Reqs,hits,misses for tmb
col hit%,ColumnarCache% for pct
set printsize 50

SELECT /*+opt_param('parallel_force_local' 'true')*/ type,&grp3
FROM   (SELECT type,objectnumber data_object_id,dbuniquename,
               &grp1,
               SUM(hitcount+misscount) "Reqs",
               SUM(hitcount) "Hits",
               SUM(hitcount)/nullif(sum(hitcount+misscount),0) "Hit%",
               SUM(misscount) "Misses",
               SUM(CACHEDSIZE) "CachedSize",
               SUM(COLUMNARCACHESIZE) "ColumnarCache",
               SUM(COLUMNARCACHESIZE)/nullif(SUM(CACHEDSIZE),0) "ColumnarCache%",
               SUM(CACHEDWRITESIZE) "CachedWrite",
               SUM(CACHEDKEEPSIZE) "CachedKeep",
               SUM(COLUMNARKEEPSIZE) "ColumnarKeep"
        FROM   (SELECT 'FLASHCAHE' type, a.* from EXA$CACHED_OBJECTS a union all SELECT 'PMEM' type, a.* from EXA$PMEM_OBJECTS a)
        GROUP  BY type,objectnumber,dbuniquename &grp2) b
LEFT JOIN dba_objects a 
ON   (b.data_object_id = a.data_object_id and regexp_replace(upper(dbuniquename),'[:\.].*')= upper(sys_context('userenv','db_unique_name')))
WHERE nvl(lower(:V1), ' ') IN (' ', 'hits', 'misses', 'cachedsize', 'cachedwrite', 'columnarcache', 'cachedkeep', 'columnarkeep') 
OR    upper(:V1) IN (owner, object_name,subobject_name, object_type,''||object_id,''||a.data_object_id)
&grp4
ORDER  BY decode(nvl(lower(:V1), 'reqs'),
                 'reqs',"Reqs",
                 'hits',"Hits",
                 'misses',"Misses",
                 'cachedsize',"CachedSize",
                 'cachedwrite',"CachedWrite",
                 'columnarcache',"ColumnarCache",
                 'cachedkeep',"CachedKeep",
                 'columnarkeep',"ColumnarKeep") desc,
          "CachedSize" desc
