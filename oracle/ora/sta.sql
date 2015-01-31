/*[[Run SQL Tuning Advisor on target SQL. Usage: sta <sql_id> [run-as user] [time limit] 
--[[
     &exe_mode: async={0}, sync={1}
--]]
]]*/
set feed off
SET printvar OFF
VAR RES CLOB;

DECLARE
    l_task    VARCHAR2(32) := 'DBCLI_STA';
    l_task_id VARCHAR2(20);
    l_sql     CLOB;
BEGIN
    l_sql := :V1;
    IF nvl(INSTR(:V1, ' '), 0) = 0 THEN
        SELECT text
        INTO   l_sql
        FROM   (SELECT sql_fulltext text
                FROM   gv$sqlarea
                WHERE  sql_id = :V1
                AND    ROWNUM < 2
                UNION ALL
                SELECT sql_text
                FROM   Dba_Hist_Sqltext
                WHERE  sql_id = :V1
                AND    ROWNUM < 2)
        WHERE  ROWNUM < 2;
    END IF;
    BEGIN
        dbms_sqltune.drop_tuning_task(l_task);
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;
    l_task_id := dbms_sqltune.create_tuning_task(sql_text   => l_sql,
                                                 user_name  => NVL(:V2, SYS_CONTEXT('USERENV','CURRENT_SCHEMA')),
                                                 scope      => 'COMPREHENSIVE',
                                                 time_limit => nvl(0+:V3,120),
                                                 task_name  => l_task);
    IF &exe_mode=0 then
        dbms_job.submit(l_task_id,'dbms_sqltune.execute_tuning_task('''||l_task||''');',sysdate);
        commit;
        l_sql := 'STA is running in async mode with job id as '||l_task_id||', run dbms_sqltune.report_tuning_task('''||l_task||''') after its completion.';
    else
        dbms_sqltune.execute_tuning_task(l_task);
        l_sql := dbms_sqltune.report_tuning_task (l_task);
    END IF;
    :RES := l_sql;
EXCEPTION WHEN NO_DATA_FOUND THEN 
    :RES := 'Target sql text does not exist!';  
END;
/
print RES