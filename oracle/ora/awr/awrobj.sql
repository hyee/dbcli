/*[[Search for the SQLs in AWR snapshots that reference the specific object. Usage: @@NAME <name|obj#|dataobj#> [<sort_by>] [yymmddhhmi] [yymmddhhmi] 
    <sort_by>: Sort the records with specific order, available options:
        ela  : elapsed time (default)
        exe  : executions
        id   : sql_id
        text : sql_text
        op   : operation name

    --[[
        @ARGS: 1
        @11G : 11.2={} DEFAULT={--}
        @12c : 19.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        @phf : 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
        &AWR_VIEW        : default={AWR_PDB_} hist={dba_hist_}
        @check_access_pdb: pdb/awr_pdb_snapshot={&AWR_VIEW.} default={DBA_HIST_}
    ]]--
]]*/

set printsize 100 feed off
COL "SEG|SCANS,IM|SCANS,BUFF|READS,BUFF|BUSY,PHY_RD|REQS,PHY_OPT|READS,PHY|READS,PHY_WR|REQS,PHY|WRITES" FOR TMB
COL "BLOCK|CHANGES,BLOCK|IM-CHG,GC-BUF|BUSY,GC-CR|BLKS,GC-CU|BLKS,ITL|WAITS,ROW_LK|WAITS,REMOTE|GRANTS,CHAIN_ROW|EXCESS,EXECS" FOR TMB
COL "SPACE|USED,SPACE|ALLOC,IM|MEM" FOR KMG
COL "PHY_OPT|READS,READS|DIRECT,WRITES|DIRECT,Weight" FOR PCT2
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
SELECT /*+DYNAMIC_SAMPLING(8)*/
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
          FROM   objs 
          JOIN   &check_access_pdb.Seg_stat USING (dbid,obj#,dataobj#)
          JOIN  (select dbid,snap_id,instance_number,begin_interval_time from &check_access_pdb.snapshot) s 
          USING (dbid,instance_number,snap_id)
          WHERE  dbid=:dbid
          AND    s.begin_interval_time BETWEEN st AND ed) A)
GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
--HAVING(COUNT(DISTINCT SUBOBJECT_NAME)>1 OR grouping_id(SUBOBJECT_NAME)=0)
ORDER BY grouping_id(SUBOBJECT_NAME) desc,"BUFF|READS"+"PHY|READS"+"PHY|WRITES" DESC;

WITH segs AS
 (SELECT /*+materialize*/ 
          DISTINCT a.*
  FROM   (SELECT OWNER,OBJECT_NAME,DBID
          FROM   &check_access_pdb.Seg_stat_obj
          WHERE  UPPER(:V1) IN(OBJECT_NAME,OWNER || '.' || OBJECT_NAME ,OWNER || '.' || OBJECT_NAME || '.'||SUBOBJECT_NAME,''||OBJ#,''||DATAOBJ#)
          AND    DBID=:DBID
          ORDER  BY 1) A
  WHERE  ROWNUM < 100),
qry AS(SELECT OWNER,OBJECT_NAME,DBID FROM SEGS 
       UNION ALL 
       SELECT '%',UPPER(:V1),0+:dbid FROM DUAL WHERE (SELECT COUNT(1) FROM SEGS)=0),
plans AS(SELECT /*+use_hash(a) DYNAMIC_SAMPLING(8)*/
               distinct
               a.dbid,
               nvl(lower(:V2),'total') sorttype,
               decode(plan_hash_value,0,sql_id) sq_id,
               plan_hash_value,
               object# obj,
               qry.object_name,
               coalesce( CASE WHEN options LIKE '%INDEX ROWID%' THEN
                             (SELECT /*+no_expand*/ 
                                      MAX(DECODE(b.options,
                                                'FULL SCAN',
                                                'FFS',
                                                'RANGE SCAN',
                                                'RS',
                                                'UNIQUE SCAN',
                                                'US',
                                                'RANGE SCAN DESCENDING',
                                                'RSD',
                                                'TO ROWIDS',
                                                'BITMAP',
                                                options)||'('||NVL(b.SEARCH_COLUMNS,0) || '): ' || object_name)
                              FROM   &check_access_pdb.SQL_PLAN b
                              WHERE  a.dbid = b.dbid
                              AND    a.sql_id = b.sql_id
                              AND    a.plan_hash_value = b.plan_hash_value
                              AND    b.id BETWEEN a.id - 1 AND a.id + 1
                              AND    b.depth=a.depth+1
                              AND   (b.parent_id=a.id or b.parent_id!=b.id-1)
                              AND    b.operation = 'INDEX'
                              AND    a.object# < b.object#)
                    ELSE OPTIONS END,
                   options,
                   operation) OP
        FROM   QRY,&check_access_pdb.SQL_PLAN a
        WHERE  A.OBJECT_NAME=QRY.OBJECT_NAME
        AND    A.OBJECT_OWNER LIKE QRY.OWNER
        AND    QRY.DBID=A.DBID
        AND    A.DBID=:DBID),
Stats AS (
    SELECT plan_hash_value,dbid &con, 
           max(sql_id) keep(dense_rank last order by total_ela) sql_id,
           count(distinct sql_id) ids,
           sum(total_ela) total_ela,
           ratio_to_report(sum(total_ela)) over() weight,
           sum(execs) execs,
           round(sum(total_ela)/greatest(sum(execs),1),2) avg_ela
    FROM (
        SELECT /*+ordered use_hash(hs s) opt_param('_optimizer_cartesian_enabled' 'false')  opt_param('_optimizer_mjc_enabled' 'false') */
               hs.sql_id,dbid &con,
               SUM(elapsed_time_delta) TOTAL_ELA,
               SUM(executions_delta) execs,
               plan_hash_value
        FROM  (
              SELECT b.*
              FROM  (select /*+no_merge*/ distinct dbid,plan_hash_value from plans where plan_hash_value>0) a
              JOIN  &check_access_pdb.Sqlstat b
              ON     a.dbid=b.dbid
              AND    a.plan_hash_value=b.plan_hash_value
              AND    b.dbid=:dbid
              UNION  ALL
              SELECT b.*
              FROM  (select /*+no_merge*/ distinct dbid,sq_id from plans where sq_id IS NOT NULL) a
              JOIN  &check_access_pdb.Sqlstat b
              ON     a.dbid=b.dbid
              AND    a.sq_id=b.sql_id
              AND    b.dbid=:dbid
              AND    b.plan_hash_value=0) hs
        JOIN &check_access_pdb.snapshot s USING(dbid,snap_id,instance_number)
        WHERE s.begin_interval_time BETWEEN to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') 
        AND   to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')
        GROUP  BY hs.sql_id, dbid &con,plan_hash_value)
    GROUP BY plan_hash_value,dbid &con,case when plan_hash_value=0 THEN sql_id END)
SELECT plan_hash_value plan_hash,sql_id top_sql_id,ids "SQLs",obj,object_name,op operation,total_ela,weight,avg_ela,execs,
       substr(regexp_replace(trim(to_char(SUBSTR(sql_text, 1, 500))),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) text
FROM  plans a
JOIN  stats b USING(dbid,plan_hash_value)
LEFT JOIN &check_access_pdb.sqltext USING(dbid &con,sql_id)
WHERE sql_id=nvl(a.sq_id,sql_id)
ORDER  BY 0+decode(sorttype,'total',total_ela,'ela',avg_ela,'exe',execs,0) DESC NULLS LAST,
          decode(sorttype,'sql',sql_id,'text',text);
