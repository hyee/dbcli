/*[[Search for the SQLs in AWR snapshots that reference the specific object. Usage: @@NAME {<[owner.]object_name> [ela|exe|id|text|op] [yymmddhhmi] [yymmddhhmi]} ]]*/


WITH qry AS
 (SELECT /*+materialize*/*
  FROM   (SELECT nvl(lower(:V2),'op') sorttype,
                 to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                 to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE, 'YYMMDDHH24MI')), 'YYMMDDHH24MI') ed
          FROM   dba_hist_Seg_stat_obj
          WHERE  UPPER(OWNER || '.' || OBJECT_NAME || chr(10) || OBJ# || chr(10) ||
                       SUBOBJECT_NAME || chr(10) || DATAOBJ# || chr(10) ) LIKE
                 '%' || NVL(UPPER(:V1), 'x') || '%'
          ORDER  BY 1)
  WHERE  ROWNUM < 100)
SELECT a.sql_id,
       to_char(SUM(elapsed_time_delta) * 1.67e-8 /GREATEST(SUM(nvl(executions_delta, parse_calls_delta)), 1), '999990.0') SQL_ELAP,
       to_char(SUM(nvl(executions_delta, parse_calls_delta)),'99999990') execs,
       op,
       to_char(MAX(TIME) / 60, '999990.0') Minutes,
       obj OBJECT,
       COUNT(DISTINCT plan_hash) Childs,
       --to_char(wmsys.wm_concat(DISTINCT decode(sign(r - 3), -1, plan_hash))) plan_hash,
       substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,20) text
FROM   (SELECT sql_id,
               st,
               ed,
               sorttype,
               plan_hash_value plan_hash,
               dense_rank() over(PARTITION BY sql_id ORDER BY plan_hash_value) r,
               object# obj,
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
        FROM   qry, DBA_HIST_SQL_PLAN a
        WHERE  qry.OBJECT_ID = a.object#
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
GROUP  BY a.sql_id, obj, op, to_char(SUBSTR(sql_text, 1, 500)),sorttype
ORDER  BY decode(sorttype,'id',sql_id,'ela',sql_elap,'exe',execs,'text',text,minutes) DESC NULLS LAST
