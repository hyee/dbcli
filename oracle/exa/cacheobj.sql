/*[[
  Show top objects in flashcache contents. Usage: @@NAME [hits|misses|cachesize|<keyword>]
	This script relies on external table EXA$CACHED_OBJECTS which is created by shell script <dbcli_home>/oracle/shell/create_exa_external_tables.sh with the oracle user
	
	Parameters:
		* hits|misses|cachesize: order by column, defaults as order by hits desc
		* detail: don't group the data,instead, show the details of each cell

	Sample output:
	==============
    SQL> exa EXTCACHEOBJ SYS
    OWNER      OBJECT_NAME       SUBOBJECT_NAME    OBJECT_TYPE     OBJECT_ID DATA_OBJECT_ID RECS CELLS HITS MISSES CACHEDSIZE CACHEDWRITE COLUMNARCACHE CACHEDKEEP COLUMNARKEEP
    ----- ---------------------- -------------- ------------------ --------- -------------- ---- ----- ---- ------ ---------- ----------- ------------- ---------- ------------
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP2301   TABLE SUBPARTITION    106117        1022957    3     3  0      0      6.44 MB        0  B       6.44 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6496   TABLE SUBPARTITION    117210        1022956    4     4  0      0      5.19 MB        0  B       5.19 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6421   TABLE SUBPARTITION    117002        1022960    4     4  0      0      5.00 MB        0  B       5.00 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6645   TABLE SUBPARTITION    117537        1022959    5     5  0      0      4.87 MB        0  B       4.87 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6653   TABLE SUBPARTITION    117545        1022958    5     5  0      0      4.81 MB        0  B       4.81 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6464   TABLE SUBPARTITION    117177        1022963    5     5  0      0      4.75 MB        0  B       4.75 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6642   TABLE SUBPARTITION    117534        1022965    6     6  0      0      4.69 MB        0  B       4.69 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6311   TABLE SUBPARTITION    115229        1022964    5     5  0      0      4.69 MB        0  B       4.69 MB       0  B         0  B
    SYS   WRI$_OPTSTAT_SYNOPSIS$ SYS_SUBP6505   TABLE SUBPARTITION    117219        1022961    5     5  0      0      4.56 MB        0  B       4.56 MB       0  B         0  B
 	--[[
		@check_access_obj: EXA$CACHED_OBJECTS={}
		&grp1: default={COUNT(1) recs,COUNT(DISTINCT CELLNODE) cells} detail={cellnode,TABLESPACENUMBER TS#}
		&grp2: default={} detail={,CELLNODE,TABLESPACENUMBER}
	--]]
]]*/

col CACHEDSIZE,cachedwrite,cachedkeep,columnarkeep,columnarcache for kmg
col hits,misses for tmb
set printsize 50

SELECT owner, object_name, subobject_name, object_type, object_id, b.*
FROM   (SELECT objectnumber data_object_id,
               &grp1,
               SUM(hitcount) hits,
               SUM(misscount) misses,
               SUM(CACHEDSIZE) CACHEDSIZE,
               SUM(CACHEDWRITESIZE) cachedwrite,
               SUM(COLUMNARCACHESIZE) columnarcache,
               SUM(CACHEDKEEPSIZE) cachedkeep,
               SUM(COLUMNARKEEPSIZE) columnarkeep
        FROM   EXA$CACHED_OBJECTS
        WHERE  upper(dbuniquename) = upper(sys_context('userenv','db_unique_name'))
        GROUP  BY objectnumber &grp2) b,
       dba_objects a
WHERE  b.data_object_id = a.data_object_id
AND   (nvl(lower(:V1), ' ') IN (' ', 'hits', 'misses', 'cachedsize', 'cachedwrite', 'columnarcache', 'cachedkeep', 'columnarkeep') 
	   OR upper(:V1) IN (owner, object_name,subobject_name, object_type,''||object_id,''||a.data_object_id))
ORDER  BY decode(nvl(lower(:V1), 'hits'),
                 'hits',hits,
                 'misses',misses,
                 'cachedsize',cachedsize,
                 'cachedwrite',cachedwrite,
                 'columnarcache',columnarcache,
                 'cachedkeep',cachedkeep,
                 'columnarkeep',columnarkeep) desc,
          cachedsize desc
