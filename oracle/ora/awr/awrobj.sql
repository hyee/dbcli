/*[[Search for the SQLs in AWR snapshots that reference the specific object. Usage: @@NAME <name|obj#|dataobj#> [<sort_by>] [yymmddhhmi] [yymmddhhmi] 
    <keyword>: Used to fussily search over OWNER+OBJECT_NAME+SUBOBJECT_NAME+OBJ#+DATAOBJ#
    <sort_by>: Sort the records with specific order, available options:
        ela  : elapsed time (default)
        exe  : executions
        id   : sql_id
        text : sql_text
        op   : operation name

   Sample Output:
   ==============
       SQL_ID     TOTAL_ELA  AVG_ELA    EXECS                     OP                    MINUTES  OBJECT          OBJECT_NAME          CHILDS TEXT                 
    ------------- --------- --------- --------- -------------------------------------- --------- ------ ----------------------------- ------ ---------------------
    6uxga5vnsgugt      36.3       0.0     59985 STORAGE FULL                                 0.0     14 SEG$                               1  select s.file#, s.bl
    1u8v867f5ys43      14.7       0.0     99975 STORAGE FULL                                 0.0     14 SEG$                               1 select ts#, file#, bl
    6uxga5vnsgugt      12.1       0.0     19995 UNIQUE SCAN                                         727 I_TABCOMPART$                      1  select s.file#, s.bl
    9x2prazfz86dz       5.3       0.0     11811 STORAGE FULL                                 0.0     14 SEG$                               1  select s.file#, s.bl
    cvtv8s2vthrt2       4.6       0.0        98 STORAGE FULL                                 0.0 727556 OBJ$                               2  with r as( SELECT /*
    9sg6u8xys290z       4.0       0.0      2564 RANGE SCAN                                   0.0 727557 I_OBJ1                             1 select count(*) num_e
    cvtv8s2vthrt2       3.9       0.0        84 RANGE SCAN                                   0.0 727557 I_OBJ1                             2  with r as( SELECT /*
    cvtv8s2vthrt2       3.3       0.0        70 BY INDEX ROWID BATCHED                       0.0 727556 OBJ$                               2  with r as( SELECT /*
    9b0n8jufpyqzv       3.0       0.0      1256 RANGE SCAN                                   0.0 727557 I_OBJ1                             1 select /*jskqjobqlod1
    9b0n8jufpyqzv       3.0       0.0      1256 STORAGE FULL                                 0.0 727556 OBJ$                               1 select /*jskqjobqlod1
    3dbzmtf9ahvzt       2.2       0.0    203486 UNIQUE SCAN                                         727 I_TABCOMPART$                      1 merge /* KSXM:OPTIM_D
    b3wn8qaj1r6d3       2.1       0.5         4 STORAGE FAST FULL SCAN                       0.0 727561 I_OBJ5                             1 WITH O AS (SELECT /*+
    b3wn8qaj1r6d3       2.1       0.5         4 RANGE SCAN                                   0.0    610 I_OPT_FINDING_OBJ_ID_OBJ_TYPE      1 WITH O AS (SELECT /*+
    9sg6u8xys290z       2.0       0.0      1282 BY INDEX ROWID BATCHED                       0.0 727556 OBJ$                               1 select count(*) num_e
    9sg6u8xys290z       2.0       0.0      1282 RS-I_OBJ1                                    0.0 727556 OBJ$                               1 select count(*) num_e
    9x2prazfz86dz       1.8       0.0      3937 UNIQUE SCAN                                         727 I_TABCOMPART$                      1  select s.file#, s.bl
    b3wn8qaj1r6d3       1.6       0.5         3 STORAGE FAST FULL SCAN                       0.0    610 I_OPT_FINDING_OBJ_ID_OBJ_TYPE      1 WITH O AS (SELECT /*+

    --[[
        @ARGS: 1
        @11G : 11.2={} DEFAULT={--}
        @12c : 18.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        @phf : 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
        &AWR_VIEW        : default={AWR_PDB_} hist={dba_hist_}
        @check_access_pdb: pdb/awr_pdb_snapshot={&AWR_VIEW.} default={DBA_HIST_}
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
    ]]--
]]*/

set printsize 100 feed off
COL "SEG|SCANS,IM|SCANS,BUFF|READS,BUFF|BUSY,PHY_RD|REQS,PHY_OPT|READS,PHY|READS,PHY_WR|REQS,PHY|WRITES" FOR TMB
COL "BLOCK|CHANGES,BLOCK|IM-CHG,GC-BUF|BUSY,GC-CR|BLKS,GC-CU|BLKS,ITL|WAITS,ROW_LK|WAITS,REMOTE|GRANTS,CHAIN_ROW|EXCESS,EXECS" FOR TMB
COL "SPACE|USED,SPACE|ALLOC,IM|MEM" FOR KMG
COL "PHY_OPT|READS,READS|DIRECT,WRITES|DIRECT" FOR PCT2
COL TIME smhd2
COL TOTAL_ELA,AVG_ELA FOR usmhd2
WITH objs AS
 (SELECT /*+materialize*/*
  FROM   (SELECT to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                 to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') ed,
                 A.*
          FROM   &check_access_pdb.Seg_stat_obj A
          WHERE  UPPER(:V1) IN(OBJECT_NAME,OWNER || '.' || OBJECT_NAME ,OWNER || '.' || OBJECT_NAME || '.'||SUBOBJECT_NAME,''||OBJ#,''||DATAOBJ#)
          )
  WHERE  ROWNUM < 100)
SELECT /*+ordered*/
       owner,object_name "SEG STATS|OBJECT NAME",
       decode(grouping_id(SUBOBJECT_NAME),0,SUBOBJECT_NAME,'All:'||COUNT(DISTINCT dataobj#)) "SEG|NAME",
       '|' "|",
       SUM(TABLE_SCANS_DELTA) "SEG|SCANS",
       &12c SUM(IM_SCANS_DELTA) "IM|SCANS",
       SUM(LOGICAL_READS_DELTA) "BUFF|READS",
       SUM(BUFFER_BUSY_WAITS_DELTA) "BUFF|BUSY",
       SUM(GC_BUFFER_BUSY_DELTA) "GC-BUF|BUSY",
       '|' "|",
       SUM(PHYSICAL_READ_REQUESTS_DELTA) "PHY_RD|REQS",
       &11G ROUND(SUM(OPTIMIZED_PHYSICAL_READS_DELTA)/NULLIF(SUM(PHYSICAL_READ_REQUESTS_DELTA),0),4) "PHY_OPT|READS",
       SUM(PHYSICAL_READS_DELTA) "PHY|READS",
       ROUND(SUM(PHYSICAL_READS_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_READS_DELTA),0),4) "READS|DIRECT",
       SUM(GC_CR_BLOCKS_RECEIVED_DELTA) "GC-CR|BLKS",
       '|' "|",
       SUM(DB_BLOCK_CHANGES_DELTA) "BLOCK|CHANGES",
       &12c SUM(IM_DB_BLOCK_CHANGES_DELTA) "BLOCK|IM-CHG",
       SUM(PHYSICAL_WRITE_REQUESTS_DELTA) "PHY_WR|REQS",
       SUM(PHYSICAL_WRITES_DELTA) "PHY|WRITES",
       ROUND(SUM(PHYSICAL_WRITES_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_WRITES_DELTA),0),4) "WRITES|DIRECT",
       SUM(GC_CU_BLOCKS_RECEIVED_DELTA) "GC-CU|BLKS",
        '|' "|",
       SUM(decode(r,1,SPACE_USED_TOTAL)) "SPACE|USED",
       SUM(decode(r,1,SPACE_ALLOCATED_TOTAL)) "SPACE|ALLOC",
       &12c SUM(decode(r,1,IM_MEMBYTES)) "IM|MEM",
       SUM(ITL_WAITS_DELTA) "ITL|WAITS",
       SUM(ROW_LOCK_WAITS_DELTA) "ROW_LK|WAITS",
       &12c  SUM(GC_REMOTE_GRANTS_DELTA) "REMOTE|GRANTS",
       SUM(CHAIN_ROW_EXCESS_DELTA) "CHAIN_ROW|EXCESS"
FROM (SELECT A.*, row_number() over(PARTITION BY dbid, obj#, dataobj# ORDER BY SPACE_USED_TOTAL DESC) r 
      FROM (
          SELECT * 
          FROM objs 
          JOIN &check_access_pdb.Seg_stat USING (dbid,obj#,dataobj#)
          JOIN (select dbid,snap_id,instance_number,begin_interval_time from &check_access_pdb.snapshot) s USING(dbid,instance_number,snap_id)
          WHERE s.begin_interval_time BETWEEN st AND ed) A)
GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
--HAVING(COUNT(DISTINCT SUBOBJECT_NAME)>1 OR grouping_id(SUBOBJECT_NAME)=0)
ORDER BY grouping_id(SUBOBJECT_NAME) desc,"BUFF|READS"+"PHY|READS"+"PHY|WRITES" DESC;

WITH segs AS
 (SELECT /*+materialize*/ DISTINCT a.*
  FROM   (SELECT OWNER,OBJECT_NAME,DBID
          FROM   &check_access_pdb.Seg_stat_obj
          WHERE  UPPER(:V1) IN(OBJECT_NAME,OWNER || '.' || OBJECT_NAME ,OWNER || '.' || OBJECT_NAME || '.'||SUBOBJECT_NAME,''||OBJ#,''||DATAOBJ#)
          ORDER  BY 1) A
  WHERE  ROWNUM < 100),
qry AS(SELECT OWNER,OBJECT_NAME,DBID FROM SEGS 
       UNION ALL 
       SELECT '%',UPPER(:V1),NVL(:DBID+0,&did) FROM DUAL WHERE (SELECT COUNT(1) FROM SEGS)=0),
Stats AS (
    SELECT /*+ordered use_hash(a hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
           hs.sql_id,dbid &con,sorttype,
           SUM(elapsed_time_delta) TOTAL_ELA,
           SUM(nvl(executions_delta, parse_calls_delta)) execs,
           op,obj,object_name,
           MAX(TIME) TIME,
           plan_hash_value plan_hash
    FROM   (SELECT /*+use_hash(a) no_merge*/
                   distinct
                   a.dbid,
                   nvl(lower(:V2),'total') sorttype,
                   plan_hash_value,
                   object# obj,
                   qry.object_name,
                   nvl( CASE WHEN options LIKE '%INDEX ROWID%' THEN
                                 (SELECT /*+no_expand*/ 
                                          MAX(DECODE(options,
                                                    'FULL SCAN',
                                                    'FFS',
                                                    'RANGE SCAN',
                                                    'RS',
                                                    'UNIQUE SCAN',
                                                    'US',
                                                    'RANGE SCAN DESCENDING',
                                                    'RSD',
                                                    options)||'('||NVL(SEARCH_COLUMNS,0) || '): ' || object_name)
                                  FROM   &check_access_pdb.SQL_PLAN b
                                  WHERE  a.dbid = b.dbid
                                  AND    a.sql_id = b.sql_id
                                  AND    a.plan_hash_value = b.plan_hash_value
                                  AND    b.id BETWEEN a.id - 1 AND a.id + 1
                                  AND    b.depth=a.depth+1
                                  AND   (b.parent_id=a.id or b.parent_id!=b.id-1)
                                  AND    b.operation = 'INDEX'
                                  AND    a.object# < b.object#)
                        ELSE  OPTIONS END,
                       operation) OP,
                   TIME + nvl(CASE WHEN options LIKE '%INDEX ROWID%' THEN
                                     (SELECT /*+no_expand*/ MAX(TIME)
                                      FROM   &check_access_pdb.SQL_PLAN b
                                      WHERE  a.dbid = b.dbid
                                      AND    a.sql_id = b.sql_id
                                      AND    a.plan_hash_value = b.plan_hash_value
                                      AND    b.id BETWEEN a.id - 1 AND a.id + 1
                                      AND    b.depth=a.depth+1
                                      AND   (b.parent_id=a.id or b.parent_id!=b.id-1)
                                      AND    b.operation = 'INDEX'
                                      AND    a.object# < b.object#)
                              END,0) TIME
            FROM   QRY,&check_access_pdb.SQL_PLAN a
            WHERE  A.OBJECT_NAME=QRY.OBJECT_NAME
            AND    A.OBJECT_OWNER LIKE QRY.OWNER
            AND    QRY.DBID=A.DBID
            AND    options != 'SAMPLE') a
    JOIN &check_access_pdb.Sqlstat hs USING(DBID,plan_hash_value)
    JOIN &check_access_pdb.snapshot s USING(DBID,snap_id,instance_number)
    WHERE s.begin_interval_time BETWEEN to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
    AND   to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')
    GROUP  BY hs.sql_id, dbid &con,plan_hash_value,obj,object_name,op, sorttype)
SELECT sql_id top_sql_id,plan_hash,ids,obj,object_name,op,total_ela,avg_ela,time,execs,
       substr(regexp_replace(trim(to_char(SUBSTR(sql_text, 1, 500))),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) text
FROM (select plan_hash,dbid &con, 
             max(sql_id) keep(dense_rank last order by total_ela) sql_id,
             count(distinct sql_id) ids,
             obj,object_name,op,
             sum(total_ela) total_ela,
             sum(execs) execs,
             sorttype,max(time) time,
             round(sum(total_ela)/nullif(sum(execs),0),2) avg_ela
      from   stats
      group  by dbid &con,sorttype,plan_hash,obj,object_name,op)
LEFT JOIN &check_access_pdb.sqltext USING(dbid &con,sql_id)
ORDER  BY 0+decode(sorttype,'total',total_ela,'ela',avg_ela,'exe',execs,0) DESC NULLS LAST,
          decode(sorttype,'sql',sql_id,'text',text);
