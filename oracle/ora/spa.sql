/*[[
    Show SQL Performance Analyzer(SPA) info. Usage: @@NAME [-f"<filter>"] 
    --[[--
        &filter: default={1=1}, f={}
    --]]--
]]*/

set verify off feed off
var c refcursor
declare 
begin
    open :c for
        WITH r AS(
            SELECT A.*,
                   (SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings
            FROM (
                    SELECT /*+materialize*/ 
                           task_id,advisor_name,owner, task_name, execution_start,execution_end,status
                    FROM   dba_advisor_tasks a
                    WHERE  (&FILTER)
                    AND    advisor_name like 'SQL Performance%'
                    ORDER  BY execution_start DESC NULLS LAST
                ) A WHERE ROWNUM<=50),
        r1 as(
            SELECT task_id,
                   MAX(DECODE(parameter_name, 'TEST_EXECUTE_DOP', parameter_value)) DOP,
                   MAX(DECODE(parameter_name, 'EXECUTE_FULLDML', parameter_value)) FULLDML,
                   MAX(DECODE(parameter_name, 'CELL_SIMULATION_ENABLED', parameter_value)) SIM_EXADATA,
                   MAX(DECODE(parameter_name, 'TIME_LIMIT', parameter_value)) TIME_LIMIT
            FROM   (SELECT TASK_ID FROM R) R 
            JOIN   DBA_ADVISOR_PARAMETERS USING(TASK_ID)
            GROUP  BY task_id)
        SELECT TASK_ID,R.OWNER,R.TASK_NAME,R1.DOP "TEST|CONCURRENCY",R1.FULLDML "EXECUTE|FULL DML",R1.SIM_EXADATA "SIMULATE|EXDATA",R1.TIME_LIMIT "TIME|LIMIT",R.findings,r.status,r.execution_start,r.execution_end
        FROM   R LEFT JOIN R1 USING(TASK_ID)
        ORDER  BY execution_start DESC NULLS LAST;
end;
/

print c