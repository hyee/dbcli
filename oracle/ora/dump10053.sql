/*[[
    Dump the 10053 trace for the specific SQL ID. Usage dump10053 <sql_id> [<child_number>|<plan_hash_value>] 
    Note: In RAC environment, it only supports dumping the SQL ID in local node(view v$sqlarea).
]]*/
set feed off
DECLARE
    sq_id       VARCHAR2(30) := :V1;
    child_num INT := :V2;
BEGIN
    SELECT /*+no_expand*/ MAX(child_number) KEEP(dense_rank LAST ORDER BY TIMESTAMP)
    INTO   child_num
    FROM   v$sql_plan_statistics_all a
    WHERE  a.sql_id = sq_id
    AND    (child_num IS NULL OR child_num IN (plan_hash_value, child_number));
    dbms_sqldiag.dump_trace(sq_id, child_num);
END;
/
loadtrace default;