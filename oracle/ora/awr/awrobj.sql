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
    ]]--
]]*/

set printsize 100

WITH qry AS
 (SELECT /*+materialize*/*
  FROM   (SELECT nvl(lower(:V2),'total') sorttype,
                 to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                 to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') ed,
                 OWNER,OBJECT_NAME
          FROM   dba_hist_Seg_stat_obj
          WHERE  UPPER(OWNER || '.' || OBJECT_NAME || chr(10) || OBJ# || chr(10) ||
                       SUBOBJECT_NAME || chr(10) || DATAOBJ# || chr(10) ) LIKE
                 '%' || NVL(UPPER(:V1), 'x') || '%'
          ORDER  BY 1)
  WHERE  ROWNUM < 100)
SELECT a.sql_id,
       to_char(SUM(elapsed_time_delta) * 1.67e-8, '999990.0') TOTAL_ELA,
       to_char(SUM(elapsed_time_delta) * 1.67e-8 /GREATEST(SUM(nvl(executions_delta, parse_calls_delta)), 1), '999990.0') AVG_ELA,
       to_char(SUM(nvl(executions_delta, parse_calls_delta)),'99999990') execs,
       op,
       to_char(MAX(TIME) / 60, '999990.0') Minutes,
       obj OBJECT,
       object_name,
       COUNT(DISTINCT plan_hash) Childs,
       --to_char(wmsys.wm_concat(DISTINCT decode(sign(r - 3), -1, plan_hash))) plan_hash,
       substr(regexp_replace(trim(to_char(SUBSTR(sql_text, 1, 500))),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) text
FROM   (SELECT sql_id,
               st,
               ed,
               sorttype,
               plan_hash_value plan_hash,
               dense_rank() over(PARTITION BY sql_id ORDER BY plan_hash_value) r,
               object# obj,
               qry.object_name,
               nvl(decode(options,
                          'BY INDEX ROWID',
                          NVL((SELECT MAX(DECODE(options,
                                                'FULL SCAN',
                                                'FFS',
                                                'RANGE SCAN',
                                                'RS',
                                                'UNIQUE SCAN',
                                                'US',
                                                options) || '-' || object_name)
                              FROM   DBA_HIST_SQL_PLAN b
                              WHERE  a.dbid = b.dbid
                              AND    a.sql_id = b.sql_id
                              AND    a.plan_hash_value = b.plan_hash_value
                              AND    a.id IN (b.id - 1, b.id + 1)
                              AND    b.operation = 'INDEX'
                              AND    a.object# < b.object#),
                              options),
                          options),
                   operation) OP,
               TIME + nvl(decode(options,
                                 'BY INDEX ROWID',
                                 (SELECT MAX(TIME)
                                  FROM   DBA_HIST_SQL_PLAN b
                                  WHERE  a.dbid = b.dbid
                                  AND    a.sql_id = b.sql_id
                                  AND    a.plan_hash_value = b.plan_hash_value
                                  AND    a.id IN (b.id - 1, b.id + 1)
                                  AND    b.operation = 'INDEX'
                                  AND    a.object# < b.object#)),
                          0) TIME
        FROM   QRY,DBA_HIST_SQL_PLAN a
        WHERE  A.OBJECT_NAME=QRY.OBJECT_NAME
        AND    QRY.OWNER=A.OBJECT_OWNER
        AND    options != 'SAMPLE') a,
       dba_hist_snapshot s,
       Dba_Hist_Sqlstat hs,
       Dba_Hist_Sqltext b
WHERE  s.snap_id = hs.snap_id
AND    s.instance_number = hs.instance_number
AND    s.dbid = hs.dbid
AND    a.sql_id = b.sql_id
AND    a.sql_id = hs.sql_id
AND    a.plan_hash = hs.plan_hash_value
AND    s.begin_interval_time BETWEEN a.st AND a.ed
GROUP  BY a.sql_id, obj,object_name,op, to_char(SUBSTR(sql_text, 1, 500)),sorttype
ORDER  BY decode(sorttype,'id',sql_id,'total',total_ela,'ela',avg_ela,'exe',execs,'text',text,minutes) DESC NULLS LAST
