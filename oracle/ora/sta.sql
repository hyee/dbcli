/*[[Run SQL Tuning Advisor on target SQL. Usage: @@NAME [-f"<filter>"]|<task_id>|<sql_text>|{<sql_id> [<phv>|<child_num>|<snap_id>|<sqlset_id>|<schema>]} [time limit]
    <sql_id>|<sql_text>: if specify then run STA on target SQL
    -sync              : run in sync mode, otherwise run with dbms_scheduler
    <schema>           : target run-as-user, can be a number which points to specific child_number/snap_id/sqlset_id/plan_hash_value
    <time limit>       : maximum run time in seconds, default as 7200
    --[[
        &exe_mode: async={0}, sync={1}
        &filter: default={1=1}, f={}
        @check_access_sqlid: SYS.DBMS_SQLTUNE_UTIL0={1} default={0}
    --]]
]]*/
set feed off
SET VERIFY OFF
VAR RES CLOB;
VAR c1 REFCURSOR;
VAR c2 REFCURSOR;
VAR fn VARCHAR2(128);
VAR txt CLOB;
DECLARE
    tsk     VARCHAR2(128) := 'DBCLI_STA';
    sq_txt  CLOB := :V1;
    sq_id   VARCHAR2(128) := regexp_substr(sq_txt, '^\S+$');
    tid     INT := regexp_substr(sq_id, '^\d+$');
    own     VARCHAR2(128) := regexp_substr(:v2,'^\S+$');
    enam    VARCHAR2(128);
    id      INT := regexp_substr(own, '^\d+$');
    bw      RAW(2000);
    bs      SYS.SQL_BIND_SET;
    bl      SYS.SQL_BINDS;
    c1      SYS_REFCURSOR;
    c2      SYS_REFCURSOR;
    status  VARCHAR2(300);
BEGIN
    own   := REPLACE(own, id);
    sq_id := REPLACE(sq_id, tid);
    IF tid IS NULL AND sq_txt IS NOT NULL THEN 
        IF sq_id IS NOT NULL THEN
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                   nvl(upper(own), nam), txt, br
            INTO   own, sq_txt, bw
            FROM   (SELECT parsing_schema_name nam, sql_fulltext txt, force_matching_signature sig, bind_data br
                    FROM   gv$sql a
                    WHERE  sql_id = sq_id
                    AND    nvl(id, child_number) IN (child_number, plan_hash_value)
                    AND    rownum < 2
                    UNION ALL
                    SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data
                    FROM   all_sqlset_statements a
                    WHERE  sql_id = sq_id
                    AND    nvl(id, sqlset_id) IN (sqlset_id, plan_hash_value)
                    AND    rownum < 2
                    UNION ALL
                    SELECT parsing_schema_name, sql_text, force_matching_signature sig, bind_data
                    FROM   dba_hist_sqltext
                    JOIN  (SELECT *
                           FROM   (SELECT dbid, sql_id, parsing_schema_name, force_matching_signature, bind_data
                                   FROM   dba_hist_sqlstat
                                   WHERE  sql_id = sq_id
                                   AND    nvl(id, snap_id) IN (snap_id, plan_hash_value)
                                   ORDER  BY decode(dbid, sys_context('userenv', 'dbid'), 1, 2), snap_id DESC)
                           WHERE  rownum < 2)
                    USING  (dbid, sql_id)
                    WHERE  sql_id = sq_id
                    UNION ALL
                    SELECT username,to_clob(sql_text),force_matching_signature,null
                    FROM   gv$sql_monitor
                    WHERE  sql_id = sq_id
                    AND    sql_text IS NOT NULL
                    AND    IS_FULL_SQLTEXT='Y'
                    AND    nvl(id,sql_exec_id) in(sql_exec_id,sql_plan_hash_value)
                    AND    rownum < 2)
            WHERE  ROWNUM < 2;
        ELSE
            IF sq_txt LIKE '%/' THEN
                sq_txt := trim(trim('/' from sq_txt));
            ELSIF sq_txt LIKE '%;' AND UPPER(sq_txt) NOT LIKE '%END;' THEN
                sq_txt := trim(trim(';' from sq_txt));
            END IF;

            $IF &check_access_sqlid=1 $THEN
                sq_id := SYS.DBMS_SQLTUNE_UTIL0.SQLTEXT_TO_SQLID(sq_txt);
            $END
        END IF;

        IF sq_id IS NOT NULL THEN
        BEGIN
            tsk :='STA_'||sq_id;
            dbms_sqltune.drop_tuning_task(tsk);
        EXCEPTION WHEN OTHERS THEN NULL;END;
        BEGIN
            dbms_scheduler.drop_job(upper(tsk),true);
        EXCEPTION WHEN OTHERS THEN NULL;END;
        END IF;

        IF bw IS NOT NULL THEN 
            SELECT VALUE_ANYDATA
            BULK COLLECT INTO bl
            FROM  TABLE(DBMS_SQLTUNE.EXTRACT_BINDS(BW));
        END IF; 
        tsk := dbms_sqltune.create_tuning_task(
                   sql_text   => sq_txt, 
                   bind_list  => bl,
                   user_name  => NVL(upper(own), SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')), 
                   scope      => 'COMPREHENSIVE', 
                   time_limit => nvl(0 + :V3,7200),
                   task_name  => tsk);
        IF &exe_mode = 0 THEN
            sq_txt:=q'~
            declare
                c int;
            begin
                execute immediate q'[alter session set "_fix_control"='25167306:1']';
            exception when others then
                select count(1) into c
                from   v$sysstat
                where  name like 'cell%elig%pred%offload%'
                and    value>0;
                if c>0 then
                    execute immediate 'alter session set "_serial_direct_read"=always';
                end if;
            end;
            dbms_sqltune.execute_tuning_task('~' || tsk || ''');';
            dbms_scheduler.create_job(job_name => tsk,
                                      job_type => 'PLSQL_BLOCK',
                                      job_action => sq_txt,
                                      enabled => TRUE);
            sq_txt := 'STA is running in async mode with job id as ' || tsk 
                      || ', run dbms_sqltune.report_tuning_task(''' || tsk ||''') after its completion.';
        ELSE
            dbms_sqltune.execute_tuning_task(tsk);
            sq_txt := dbms_sqltune.report_tuning_task(tsk);
        END IF;
    ELSIF tid IS NULL THEN
        sq_txt := null;
        OPEN c1 FOR
            WITH r AS
             (SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 5)*/ 
                     A.*, 
                     (SELECT COUNT(1) FROM dba_advisor_executions where task_id = a.task_id) execs,
                     (SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings,
                     (SELECT decode(type,'SQL',attr3||' => '||attr1,nullif(attr3||'.'||attr1,'.')) 
                      FROM   dba_advisor_objects b
                      WHERE  task_id = a.task_id
                      AND    EXECUTION_NAME IS NULL
                      AND    TYPE IN('SQLSET','SQL')
                      AND    ROWNUM<2) SQLSET
              FROM   (SELECT task_id, advisor_name, owner, task_name, execution_start, execution_end, status,DESCRIPTION
                      FROM   dba_advisor_tasks a
                      WHERE  advisor_name LIKE 'SQL Tuning%'
                      AND   (&FILTER)
                      ORDER  BY execution_start DESC NULLS LAST) A
              WHERE  ROWNUM <= 50),
            r1 AS
             (SELECT task_id,
                     MAX(DECODE(parameter_name, 'LOCAL_TIME_LIMIT', parameter_value+0,'TIME_LIMIT', parameter_value+0)) TIME_LIMIT,
                     MAX(DECODE(parameter_name, 'DEFAULT_EXECUTION_TYPE', parameter_value)) EXEC_TYPE,
                     MAX(DECODE(parameter_name, 'MODE', parameter_value)) EXEC_MODE
              FROM   (SELECT TASK_ID FROM R) R
              JOIN   DBA_ADVISOR_PARAMETERS
              USING  (TASK_ID)
              WHERE  PARAMETER_VALUE != 'UNUSED'
              GROUP  BY task_id)
            SELECT TASK_ID,
                   R.OWNER,
                   R.TASK_NAME,
                   R.SQLSET "SQL[SET]",
                   r1.exec_type ,
                   r1.EXEC_MODE,
                   r.execs,
                   R.findings,
                   r.status,
                   R1.TIME_LIMIT MAX_SECS,
                   r.execution_start,
                   r.execution_end,
                   r.DESCRIPTION
            FROM   R
            LEFT   JOIN R1
            USING  (TASK_ID)
            ORDER  BY execution_start DESC NULLS LAST;
    ELSE
        sq_txt := null;
        OPEN c1 FOR
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                   PARAMETER_NAME,
                   nvl(B.PARAMETER_VALUE, A.PARAMETER_VALUE) PARAMETER_VALUE,
                   PARAMETER_TYPE,
                   IS_DEFAULT,
                   IS_OUTPUT,
                   IS_MODIFIABLE_ANYTIME IS_MDF,
                   DESCRIPTION
            FROM   dba_advisor_def_parameters a
            LEFT   JOIN (
                SELECT * FROM (
                    SELECT A.*,ROW_NUMBER() OVER(PARTITION BY PARAMETER_NAME ORDER BY SEQ DESC) R
                    FROM (
                         SELECT PARAMETER_NAME, PARAMETER_VALUE,tid+regexp_substr(execution_name,'\d+$') seq
                         FROM   DBA_ADVISOR_EXEC_PARAMETERS
                         WHERE  TASK_ID = tid
                         AND    PARAMETER_VALUE != 'UNUSED'
                         UNION ALL
                         SELECT PARAMETER_NAME, PARAMETER_VALUE,tid
                         FROM   DBA_ADVISOR_PARAMETERS
                         WHERE  TASK_ID = tid
                         AND    PARAMETER_VALUE != 'UNUSED') A)
                WHERE R=1) b
            USING  (PARAMETER_NAME)
            WHERE  A.ADVISOR_NAME = 'SQL Tuning Advisor'
            UNION ALL
            SELECT TYPE,
                   ATTR1,
                   NULL,NULL,NULL,NULL,
                   trim(regexp_replace(to_char(substr(attr4,1,200)),'\s+',' '))
            FROM   dba_advisor_objects
            WHERE  TASK_ID = tid
            AND    EXECUTION_NAME IS NULL
            ORDER  BY PARAMETER_NAME;

        SELECT max(STATUS),max(TASK_NAME),max(OWNER)
        INTO   STATUS,TSK,OWN
        FROM   DBA_ADVISOR_TASKS 
        WHERE  task_id=tid;

        IF STATUS='COMPLETED' THEN
            SELECT MAX(EXECUTION_NAME) KEEP(DENSE_RANK LAST ORDER BY EXECUTION_END)
            INTO   enam
            FROM   DBA_ADVISOR_EXECUTIONS
            WHERE  task_id=tid
            AND    status='COMPLETED';

            :fn := tsk||'.txt';
            :txt :=sys.DBMS_SQLTUNE.REPORT_TUNING_TASK(task_name=>tsk,execution_name=>enam,owner_name=>own,level=>'ALL',section=>'ALL');
            OPEN c2 FOR
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                       DISTINCT
                       EXECUTION_NAME EXEC_NAME,
                       OBJECT_ID obj#,
                       REC_ID rec#,
                       '|' "|",
                       decode(r,1,COMMAND) command,
                       decode(nvl(r,1),1,plan_attribute) plan_attribute,
                       decode(nvl(r,1),1,plan_hash_value) plan_hash_value,
                       a.r "#",
                       a.ATTR1,
                       a.ATTR2,
                       a.ATTR3,
                       a.ATTR4,
                       to_char(substr(a.attr5,1,500)) attr5,
                       to_char(substr(a.attr6,1,500)) attr6,
                       RESULT_STATUS
                FROM   (select a.*,row_number() over(partition by rec_id order by 1) r
                        from   dba_advisor_actions a
                        WHERE  task_id=tid
                        AND    execution_name=enam) a
                JOIN   dba_advisor_rationale
                USING  (task_id,object_id,execution_name,rec_id)
                JOIN    dba_sqltune_rationale_plan
                USING  (task_id,object_id,execution_name,rationale_id)
                FULL JOIN (
                       SELECT /*+no_merge*/
                              DISTINCT task_id,execution_name,attribute plan_attribute,object_id,plan_hash_value
                       FROM   dba_sqltune_plans
                       WHERE  task_id=tid
                       AND    execution_name=enam)
                USING (task_id,object_id,execution_name,plan_attribute)
                WHERE  task_id=tid
                AND    execution_name=enam
                ORDER  BY 1,2,3 NULLS FIRST,a.r;
        END IF;
    END IF;
    :c1  := c1;
    :c2  := c2;
    :RES := sq_txt;
END;
/
print c1
print c2
print RES

save txt fn