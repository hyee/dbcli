/*[[Show SQLs that depend on target object. Usage: @@NAME [owner.]<object_name>
    --[[
        @ARGS: 1
        @VER: 12.1={AND a.con_id=b.con_id} default={}
    --]]
]]*/


ora _find_object &V1 0
col ela,avg_ela for usmhd2
set printsize 50
SELECT /*+ OPT_PARAM('_fix_control' '26552730:0') opt_param('optimizer_dynamic_sampling' 0)*/
     sql_id,
     COUNT(DISTINCT plan_hash) plans,
     SUM(ela) ela,
     SUM(ela) / SUM(execs) avg_ela,
     SUM(EXECUTING) EXECUTING,
     MAX(sql_text) sql_text
FROM   (
    SELECT *
    FROM TABLE(GV$(CURSOR( --
          SELECT /*+outline_leaf leading(a) use_nl(b) push_pred(b) opt_estimate(table b rows=1000000)*/
                b.sql_id,
                plan_hash_value plan_hash,
                elapsed_time ela,
                greatest(executions, 1) execs,
                USERS_EXECUTING EXECUTING,
                TRIM(regexp_replace(substr(b.sql_text, 1, 250), '\s+', ' ')) sql_text
          FROM  v$object_dependency a, v$sql b
          WHERE a.from_hash = b.hash_value
          AND   a.from_address = b.address
          AND   a.to_name = :object_name
          AND   a.to_owner = :object_owner  &ver
          UNION ALL
          SELECT /*+outline_leaf leading(a) use_nl(b) push_pred(b) opt_estimate(table b rows=1000000)*/
                b.sql_id,
                sql_plan_hash_value plan_hash,
                GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME) ela,
                CASE WHEN PX_SERVER# IS NULL AND sql_text IS NOT NULL THEN 1 ELSE 0 END execs,
                0 EXECUTING,
                TRIM(regexp_replace(substr(b.sql_text, 1, 250), '\s+', ' ')) sql_text
          FROM  (SELECT /*+cardinality(1)*/ 
                       DISTINCT key 
                 from  v$sql_plan_monitor 
                 WHERE plan_object_owner = :object_owner 
                 AND plan_object_name = :object_name) a, 
                v$sql_monitor b
          WHERE a.key = b.key
          AND   b.status not like '%EXECUTING%')))
    UNION ALL
    SELECT /*+outline_leaf*/ 
           sql_id,
           plan_hash_value,
           elapsed_time_delta,
           executions_delta,
           0,
           TRIM(regexp_replace(to_char(substr(b.sql_text, 1, 250)), '\s+', ' ')) sql_text
    FROM   (SELECT /*+cardinality(1)*/
                   DISTINCT sql_id, dbid
            FROM   dba_hist_sql_plan
            WHERE  dbid = :dbid
            AND    object_owner = :object_owner
            AND    object_name = :object_name)
    JOIN   dba_hist_sqlstat a
    USING  (dbid, sql_id)
    JOIN   dba_hist_sqltext b
    USING  (dbid, sql_id)
    WHERE  dbid = :dbid)
GROUP  BY sql_id
ORDER  BY EXECUTING DESC, ela DESC;

