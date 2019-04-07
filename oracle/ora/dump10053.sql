/*[[
    Dump the 10053 trace for the specific SQL ID. Usage: @@NAME {<sql_id> [<child_number>|<plan_hash_value>]} [-c]
    Note: In RAC environment, it only supports dumping the SQL ID in local node(view v$sqlarea).
    -c: Generate SQL Compiler trace file, otherwise generate 10053 trace file
    --[[
        @version: 11.0={}
        &opt: default={Optimizer}, c={Compiler}
        @ARGS: 1
    --]]
]]*/
set feed off
DECLARE
    sq_id       VARCHAR2(30) := :V1;
    child_num   INT := regexp_substr(:V2,'^\d+$');
BEGIN
    SELECT /*+no_expand*/ MAX(child_number) KEEP(dense_rank LAST ORDER BY TIMESTAMP)
    INTO   child_num
    FROM   v$sql_plan_statistics_all a
    WHERE  a.sql_id = sq_id
    AND    (child_num IS NULL OR child_num IN (plan_hash_value, child_number));
    dbms_sqldiag.dump_trace(sq_id, child_num, :opt);
END;
/
loadtrace default;