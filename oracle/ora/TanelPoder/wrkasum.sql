/*[[
    Show top allocation for PGA and temp space. Usage: @@NAME [<sql_id>|<sid>|-g] 
    -g: Show summary on gv$sql_workarea
    --[[
        &g: default={0} g={1}
        @ver: 18={1} default={1e4}
    --]]
]]*/
set feed off

col "Actual|Mem,Work|Area,Temp|Space,Est-Mem|Optimal,Est-Mem|OnePass,Max|Mem,Max|Temp" for kmg2
col "Max|Active" for usmhd2
VAR WRKOPR REFCURSOR "Top Operations from gv$sql_workarea "
VAR WRKSQL REFCURSOR "Top SQL_ID by Temp Usage from gv$sql_workarea_active"
DECLARE
    sqls sys.dbms_debug_vc2coll := sys.dbms_debug_vc2coll();
    type t0 IS TABLE OF VARCHAR2(13);
    t t0 := t0();
    flag boolean := false;
BEGIN
    IF LENGTH(:V1)=13 THEN
        t := t0(:V1);
        flag := true;
    END IF;
    --use loop instead of join to avoid full scan on gv$sqlarea
    FOR r IN (SELECT /*+no_expand*/ DISTINCT sql_id 
              FROM gv$sql_workarea_active 
              WHERE sql_id IS NOT NULL
              AND  (:V1 IS NULL OR :V1 IN ('' || qcsid, '' || sid, sql_id))) 
    LOOP
        sqls.extend;
        IF flag AND t(1) != r.sql_id THEN
            t.extend;
            t(t.count) := r.sql_id;
        END IF;
        SELECT MAX(sql_id || ':'||substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[' || chr(10) || chr(13) || chr(9) || ' ]+',' '),1,150))
        INTO   sqls(sqls.count)
        FROM   gv$sqlarea
        WHERE  sql_id = r.sql_id
        AND    ROWNUM < 2;
    END LOOP;

    IF flag THEN
        OPEN :WRKOPR FOR
            SELECT OPERATION_TYPE "Oper|Type",
                   MAX(ESTIMATED_OPTIMAL_SIZE) "Est-Mem|Optimal",
                   MAX(ESTIMATED_ONEPASS_SIZE) "Est-Mem|OnePass",
                   MAX(LAST_MEMORY_USED)    "Max|Mem",
                   SUM(TOTAL_EXECUTIONS)    "Total|Execs",
                   SUM(OPTIMAL_EXECUTIONS)  "Optimal|Execs",
                   SUM(ONEPASS_EXECUTIONS)  "OnePass|Execs",
                   SUM(MULTIPASSES_EXECUTIONS) "MutiPass|Execs",
                   MAX(MAX_TEMPSEG_SIZE) "Max|Temp",
                   MAX(ACTIVE_TIME * &ver)   "Max|Active"
            FROM   gv$sql_workarea w
            WHERE  sql_id = t(1)
            GROUP BY OPERATION_TYPE;
    ELSIF &g=1 THEN
        OPEN :WRKOPR FOR
            SELECT *
            FROM   (SELECT dense_rank() OVER (ORDER BY MAX(MAX_TEMPSEG_SIZE) DESC NULLS LAST, 
                                                       nvl(MAX(ESTIMATED_ONEPASS_SIZE),0)+nvl(MAX(ESTIMATED_OPTIMAL_SIZE),0) DESC,
                                                       sql_id) "#",
                           OPERATION_TYPE "Operation|Type",
                           sql_id "SQL|Id",
                           COUNT(DISTINCT CHILD_NUMBER||'.'||INST_ID) "Num|Childs",
                           MAX(ESTIMATED_OPTIMAL_SIZE) "Est-Mem|Optimal",
                           MAX(ESTIMATED_ONEPASS_SIZE) "Est-Mem|OnePass",
                           MAX(LAST_MEMORY_USED) "Max|Mem",
                           SUM(TOTAL_EXECUTIONS) "Total|Execs",
                           SUM(OPTIMAL_EXECUTIONS) "Optimal|Execs",
                           SUM(ONEPASS_EXECUTIONS) "OnePass|Execs",
                           SUM(MULTIPASSES_EXECUTIONS) "MutiPass|Execs",
                           MAX(MAX_TEMPSEG_SIZE) "Max|Temp",
                           MAX(ACTIVE_TIME * &ver) "Max|Active"
                    FROM   gv$sql_workarea
                    GROUP  BY OPERATION_TYPE, sql_id)
            WHERE  "#" <= 30
            ORDER  BY 1;
    END IF;

    OPEN :WRKSQL FOR
        SELECT /*+no_expand*/
                 sql_id,
                 policy,
                 MAX(Operation_type) keep(dense_rank last order by nvl(tempseg_size,0)+nvl(actual_mem_used,0),Active_Time) "Top|Operation",
                 MAX(Active_Time * &ver) "Max|Active",
                 SUM(actual_mem_used) "Actual|Mem",
                 SUM(work_area_size) "Work|Area",
                 SUM(tempseg_size) "Temp|Space",
                 tablespace "Temp|Tbs",
                 MAX(number_passes) "Num|Passes",
                 COUNT(DISTINCT coalesce(0+to_char(sql_exec_start,'yymmddhh24miss'),qcsid,sid)||'.'||coalesce(sql_exec_id,qcinst_id,inst_id)) "Num|Exec",
                 COUNT(DISTINCT nullif(qcinst_id || '.' || qcsid,'.')) "Num|QCs",
                 COUNT(DISTINCT inst_id || '.' || sid) "Num|Sess",
                 regexp_replace(b.column_value, '^[^:]+:') "SQL|Text"
        FROM   gv$sql_workarea_active a, TABLE(sqls) b
        WHERE  b.column_value(+) LIKE a.sql_id || ':%'
        AND    (:V1 IS NULL OR :V1 IN ('' || qcsid, '' || sid, a.sql_id))
        GROUP  BY sql_id, policy, b.column_value,tablespace
        ORDER  BY nvl("Temp|Space",0)+nvl("Actual|Mem",0) DESC;
END;
/
