/*[[Search for the SQLs in AWR snapshots that reference the specific object. Usage: @@NAME {<keyword> [<sort_by>] [yymmddhhmi] [yymmddhhmi]} 
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
    ]]--
]]*/

set printsize 100 feed off
COL "SEG|SCANS,BUFF|READS,BUFF|BUSY,PHY_RD|REQS,PHY_OPT|READS,PHY|READS,PHY_WR|REQS,PHY|WRITES" FOR TMB
COL "BLOCK|CHANGES,GC_BUFF|BUSY,GC_CR|BLKS,GC_CU|BLKS,ITL|WAITS,ROW_LOCK|WAITS,REMOTE|GRANTS,CHAIN_ROW|EXCESS,EXECS" FOR TMB
COL "SPACE|USED,SPACE|ALLOC" FOR KMG
COL "PHY_OPT|READS,READS|DIRECT,WRITES|DIRECT" FOR PCT2
COL TOTAL_ELA,AVG_ELA FOR usmhd2
WITH objs AS
 (SELECT /*+materialize*/*
  FROM   (SELECT to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                 to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') ed,
                 A.*
          FROM   dba_hist_Seg_stat_obj A
          WHERE  UPPER(:V1) IN(OBJECT_NAME,OWNER || '.' || OBJECT_NAME ,OWNER || '.' || OBJECT_NAME || '.'||SUBOBJECT_NAME,''||OBJ#,''||DATAOBJ#)
          )
  WHERE  ROWNUM < 100)
SELECT /*+ordered*/
       owner,object_name,
       decode(grouping_id(SUBOBJECT_NAME),0,SUBOBJECT_NAME,'All:'||COUNT(DISTINCT dataobj#)) "SEG|NAME",
       SUM(TABLE_SCANS_DELTA) "SEG|SCANS",
       SUM(LOGICAL_READS_DELTA) "BUFF|READS",
       SUM(BUFFER_BUSY_WAITS_DELTA) "BUFF|BUSY",
       SUM(GC_BUFFER_BUSY_DELTA) "GC_BUFF|BUSY",
       '|' "|",
       SUM(PHYSICAL_READ_REQUESTS_DELTA) "PHY_RD|REQS",
       &11G ROUND(SUM(OPTIMIZED_PHYSICAL_READS_DELTA)/NULLIF(SUM(PHYSICAL_READ_REQUESTS_DELTA),0),4) "PHY_OPT|READS",
       SUM(PHYSICAL_READS_DELTA) "PHY|READS",
       ROUND(SUM(PHYSICAL_READS_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_READS_DELTA),0),4) "READS|DIRECT",
       SUM(GC_CR_BLOCKS_RECEIVED_DELTA) "GC_CR|BLKS",
       '|' "|",
       SUM(DB_BLOCK_CHANGES_DELTA) "BLOCK|CHANGES",
       SUM(PHYSICAL_WRITE_REQUESTS_DELTA) "PHY_WR|REQS",
       SUM(PHYSICAL_WRITES_DELTA) "PHY|WRITES",
       ROUND(SUM(PHYSICAL_WRITES_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_WRITES_DELTA),0),4) "WRITES|DIRECT",
       SUM(GC_CU_BLOCKS_RECEIVED_DELTA) "GC_CU|BLKS",
        '|' "|",
       SUM(decode(r,1,SPACE_USED_TOTAL)) "SPACE|USED",
       SUM(decode(r,1,SPACE_ALLOCATED_TOTAL)) "SPACE|ALLOC",
       SUM(ITL_WAITS_DELTA) "ITL|WAITS",
       SUM(ROW_LOCK_WAITS_DELTA) "ROW_LOCK|WAITS",
       SUM(CHAIN_ROW_EXCESS_DELTA) "CHAIN_ROW|EXCESS",
       &11G SUM(GC_REMOTE_GRANTS_DELTA) "REMOTE|GRANTS"
FROM (SELECT A.*, row_number() over(PARTITION BY dbid, obj#, dataobj# ORDER BY SPACE_USED_TOTAL DESC) r 
      FROM (
          SELECT * 
          FROM objs 
          JOIN dba_hist_Seg_stat USING (dbid,obj#,dataobj#)
          JOIN (select dbid,snap_id,instance_number,begin_interval_time from dba_hist_snapshot) s USING(dbid,instance_number,snap_id)
          WHERE s.begin_interval_time BETWEEN st AND ed) A)
GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
--HAVING(COUNT(DISTINCT SUBOBJECT_NAME)>1 OR grouping_id(SUBOBJECT_NAME)=0)
ORDER BY grouping_id(SUBOBJECT_NAME) desc,"BUFF|READS"+"PHY|READS"+"PHY|WRITES" DESC;

WITH qry AS
 (SELECT /*+materialize*/*
  FROM   (SELECT nvl(lower(:V2),'total') sorttype,
                 to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                 to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') ed,
                 OWNER,OBJECT_NAME,dbid
          FROM   dba_hist_Seg_stat_obj
          WHERE  UPPER(:V1) IN(OBJECT_NAME,OWNER || '.' || OBJECT_NAME ,OWNER || '.' || OBJECT_NAME || '.'||SUBOBJECT_NAME,''||OBJ#,''||DATAOBJ#)
          ORDER  BY 1)
  WHERE  ROWNUM < 100)
SELECT /*+ordered use_hash(a hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
       hs.sql_id,
       SUM(elapsed_time_delta) TOTAL_ELA,
       SUM(elapsed_time_delta) /GREATEST(SUM(nvl(executions_delta, parse_calls_delta)), 1) AVG_ELA,
       SUM(nvl(executions_delta, parse_calls_delta)) execs,
       op,
       to_char(MAX(TIME) / 60, '999990.0') TIME,
       obj OBJECT,
       object_name,
       COUNT(DISTINCT plan_hash) Childs,
       --to_char(wmsys.wm_concat(DISTINCT decode(sign(r - 3), -1, plan_hash))) plan_hash,
       substr(regexp_replace(trim(to_char(SUBSTR(sql_text, 1, 500))),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) text
FROM   (SELECT /*+use_hash(a) no_merge*/
               distinct
               st,
               ed,
               a.dbid,
               sorttype,
               plan_hash_value plan_hash,
               object# obj,
               qry.object_name,
               nvl(decode(substr(options,-11),
                          'INDEX ROWID',
                          NVL((SELECT /*+no_expand*/ 
                                      MAX(DECODE(options,
                                                'FULL SCAN',
                                                'FFS',
                                                'RANGE SCAN',
                                                'RS',
                                                'UNIQUE SCAN',
                                                'US',
                                                'RANGE SCAN DESCENDING',
                                                'RSD',
                                                options) || ': ' || object_name)
                              FROM   DBA_HIST_SQL_PLAN b
                              WHERE  a.dbid = b.dbid
                              AND    a.sql_id = b.sql_id
                              AND    a.plan_hash_value = b.plan_hash_value
                              AND    b.id BETWEEN a.id - 1 AND a.id + 1
                              AND    b.depth=a.depth+1
                              AND   (b.parent_id=a.id or b.parent_id!=b.id-1)
                              AND    b.operation = 'INDEX'
                              AND    a.object# < b.object#),
                              options),
                          options),
                   operation) OP,
               TIME + nvl(decode(substr(options,-11),
                                 'INDEX ROWID',
                                 (SELECT /*+no_expand*/ MAX(TIME)
                                  FROM   DBA_HIST_SQL_PLAN b
                                  WHERE  a.dbid = b.dbid
                                  AND    a.sql_id = b.sql_id
                                  AND    a.plan_hash_value = b.plan_hash_value
                                  AND    b.id BETWEEN a.id - 1 AND a.id + 1
                                  AND    b.depth=a.depth+1
                                  AND   (b.parent_id=a.id or b.parent_id!=b.id-1)
                                  AND    b.operation = 'INDEX'
                                  AND    a.object# < b.object#)),
                          0) TIME
        FROM   QRY,DBA_HIST_SQL_PLAN a
        WHERE  A.OBJECT_NAME=QRY.OBJECT_NAME
        AND    QRY.OWNER=A.OBJECT_OWNER
        AND    QRY.DBID=A.DBID
        AND    options != 'SAMPLE') a,
       Dba_Hist_Sqlstat hs,
       dba_hist_snapshot s,
       Dba_Hist_Sqltext b
WHERE  a.dbid=s.dbid
AND    s.snap_id = hs.snap_id
AND    s.instance_number = hs.instance_number
AND    s.dbid = hs.dbid
AND    a.dbid = hs.dbid
AND    a.dbid = b.dbid
AND    b.sql_id = hs.sql_id
AND    a.plan_hash = hs.plan_hash_value
AND    s.begin_interval_time BETWEEN a.st AND a.ed
GROUP  BY hs.sql_id, obj,object_name,op, to_char(SUBSTR(sql_text, 1, 500)),sorttype
ORDER  BY 0+decode(sorttype,'total',total_ela,'ela',avg_ela,'exe',execs,0) DESC NULLS LAST,decode(sorttype,'sql',sql_id,'text',text);
