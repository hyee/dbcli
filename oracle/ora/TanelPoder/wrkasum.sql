/*[[Show top allocation for PGA and temp space. Usage: @@NAME [sql_id|sid] ]]*/
set feed off
PROMPT Top allocation reason by PGA memory usage:
PROMPT ==========================================

 SELECT /*+no_expand*/
     operation_type
   , policy
   , ROUND(SUM(actual_mem_used)/1048576) actual_pga_mb
   , ROUND(SUM(work_area_size)/1048576)  allowed_pga_mb
   , ROUND(SUM(tempseg_size)/1048576)    temp_mb
   , MAX(number_passes)                  num_passes
   , COUNT(DISTINCT qcinst_id||','||qcsid)   num_qc
   , COUNT(DISTINCT inst_id||','||sid)   num_sessions
 FROM
     gv$sql_workarea_active
 WHERE (:V1 IS NULL OR :V1 in(''||qcsid,''||sid,sql_id))
 GROUP BY
     operation_type
   , policy
 ORDER BY
     actual_pga_mb DESC NULLS LAST
/

VAR WRKSQL REFCURSOR "Top SQL_ID by TEMP Usage"
DECLARE
    sqls sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll();
BEGIN
    --use loop instead of join to avoid full scan on gv$sqlarea
    FOR r IN (SELECT DISTINCT sql_id FROM gv$sql_workarea_active WHERE sql_id IS NOT NULL) LOOP
        IF sqls.count = 0 OR sqls(sqls.count) IS NOT NULL THEN
            sqls.extend;
        END IF;
        SELECT MAX(sql_id || ':'||substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,150))
        INTO   sqls(sqls.count)
        FROM   gv$sqlarea
        WHERE  sql_id = r.sql_id
        AND    ROWNUM < 2;
    END LOOP;

    OPEN :WRKSQL FOR
        SELECT /*+no_expand*/
             sql_id
           , policy
           , ROUND(SUM(actual_mem_used)/1048576) actual_pga_mb
           , ROUND(SUM(work_area_size)/1048576)  allowed_pga_mb
           , ROUND(SUM(tempseg_size)/1048576)    temp_mb
           , MAX(number_passes)                  num_passes
           , COUNT(DISTINCT qcinst_id||','||qcsid)   num_qc
           , COUNT(DISTINCT inst_id||','||sid)   num_sessions
           , regexp_replace(b.column_value,'^[^:]+:') sql_text
         FROM
             gv$sql_workarea_active a,TABLE(sqls) b
         WHERE b.column_value(+) like a.sql_id||':%'
         AND   (:V1 IS NULL OR :V1 in(''||qcsid,''||sid,a.sql_id))
         GROUP BY
             sql_id
           , policy
           , b.column_value
         ORDER BY
             temp_mb DESC NULLS LAST;
END;
/
