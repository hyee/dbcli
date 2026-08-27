/*[[
    Manage SQL Performance Analyzer(SPA). type 'help @@NAME' for more detail.
    Usages:
        @@NAME                                          : show all SPA tasks
        @@NAME -f"<filter>"                             : filter on dba_advisor_tasks
        @@NAME <task>                                   : show details of target task
        @@name -sql  <sql_id>                           : Show sql execution stats
        @@name -sign <sql_id>                           : Show sql execution stats relative to the same force_matching_signature
        @@name -plan <plan_hash_value>                  : Show sql execution stats relative to target plan hash value
        @@NAME <task> create <sqlset> [-f"<filter>"]    : create SPA task from sqlset
        @@NAME <task> alter <param_name> [<param_value>]: alter task parameter
        @@NAME <task> drop                              : drop SPA task
        @@NAME <task> stop   <ename>                    : stop  the running SPA execution
        @@NAME <task> pause  <ename>                    : pause therunning SPA execution
        @@NAME <task> resume <ename>            [-sync] : resume the paused SPA execution
        @@NAME <task> test [<ename>] [<degree>] [-sync] : run new execution task with specific concurrenct degree in async mode
        @@NAME <task> explain|xplan  [<ename>]  [-sync] : run new explain plan task in async mode
        @@NAME <task> diff <exec1> <exec2> [<ename>]    : run new compare task to compare 2 specific executions in async mode
                                                          <exec1>/<exec2>: the pre/post execution names or IDs for the comparison
                                                          <ename>        : the new execution name for the task
        @@NAME <task> <ename> [<parameters>]            : show details of target executions, following with below parameters:
                                                            -diff     : order by abs(diff)
                                                            -regress  : order by regression
                                                            -improve  : order by improvement
                                                            -phv      : compare by plan_hash_value
                                                            <keyword> : filter with specific keyword
                                                            htm|html  : generate HTML report for target comparison analysis report
                                                            txt|text  : generate TEXT report for target comparison analysis report
                                                            active    : generate ACTIVE report for target comparison analysis report
    Variables:
        <task> : can be either task_id or task_name
        <ename>: can be either execution_id or execution_name
        -sync  : run in sync mode instead of the DEFAULT async mode for the execute/explain/resume executions
    --[[--
        &filter: default={1=1}, f={}
        @ver   : 18.1={} default={--}
        @attr17: 12.1={attr17} default={null}
        @attr11: 12.1={attr11} default={null}
        &ord1  : {
            weight={abs(attr9-attr8)*attr10*log(10,greatest(diff,1/diff))} 
            diff={greatest(diff,1/nullif(diff,0))} 
            regress={sign(attr9-attr8)*abs(attr9-attr8)*attr10*diff} 
            improve={sign(attr8-attr9)*abs(attr9-attr8)*attr10/diff}
        }
        &sq    : default={0} sql={1} plan={2} sign={3}
        &phv   : default={0} phv={1}
        &pfilter : default={1=1} regress={s.avg_ela*1.2<a.avg_ela} improve={a.avg_ela*1.2<s.avg_ela}
        &qb    : {
            default={
                SELECT sq sq 
                FROM   dual
                UNION
                SELECT attr1
                FROM   dba_advisor_objects
                WHERE  sid=0
                AND    attr1 IS NOT NULL
                AND    &attr17=sq
                AND    type='SQL'}
            plan={
                SELECT attr1 sq
                FROM   dba_advisor_objects
                WHERE  attr1 IS NOT NULL
                AND    type='SQL'
                AND    attr5=sq
                UNION
                SELECT sql_id
                FROM   dba_advisor_sqlstats
                WHERE  plan_hash_value=sq
            }
            sig={
                SELECT sq sq 
                FROM   dual
                UNION
                SELECT a.sql_id
                FROM   dba_sqlset_statements a,
                       dba_sqlset_statements b
                WHERE  b.sql_id=sq
                AND    a.force_matching_signature=b.force_matching_signature
                AND    a.sqlset_id=b.sqlset_id
                AND    a.sqlset_owner=b.sqlset_owner
                AND    a.sqlset_name=b.sqlset_name
            }
        }
        &sync  : default={0} sync={1}
    --]]--
]]*/

set verify off feed off
col weight,cpu,io for pct3
col ela,avg_ela,prev_cost,post_cost,parse,avg|ela,src_avg,spa_avg for usmhd2
col buffs,exec,avg|fetches,avg|rows#,avg|buffs,avg|reads,direct|writes,read|req,write|req for tmb2
col read|bytes,write|bytes,inter|bytes for kmg2
var m1 VARCHAR2(300)
var m2 VARCHAR2(300)
var c1 refcursor
var c2 refcursor
var fn VARCHAR2(30);
var fc CLOB;
DECLARE
    c1         SYS_REFCURSOR;
    c2         SYS_REFCURSOR;
    rs         CLOB;
    tsk        VARCHAR2(128) := replace(upper(:v1),'"');
    op         VARCHAR2(128) := upper(:v2);
    sq         VARCHAR2(13)  := CASE WHEN &sq=2 THEN  regexp_substr(:v1,'^\d+$') ELSE regexp_substr(:v1,'^.{13}$') END;
    v3         VARCHAR2(128) := replace(upper(:v3),'"');
    v4         VARCHAR2(128) := replace(upper(:v4),'"');
    v5         VARCHAR2(128) := :v5;
    tid        INT := regexp_substr(tsk, '^\d+$');
    sid        INT;
    eid        INT := regexp_substr(op, '^\d+$');
    estatus    VARCHAR2(30);
    fname      VARCHAR2(128) :='spa.txt';
    dop        INT := 1;
    frs        CLOB;
    typ        VARCHAR2(30);
    ord        VARCHAR2(300);
    nam        VARCHAR2(128);
    pre        VARCHAR2(128);
    post       VARCHAR2(128);
    snam       VARCHAR2(128);
    sown       VARCHAR2(128);
    key        VARCHAR2(2000):=upper(:v3);
    m1         VARCHAR2(300);
    m2         VARCHAR2(300);
    fil        VARCHAR2(4000);
    sq_id      VARCHAR2(30);
    sq_txt     VARCHAR2(400);
    sq_nid     VARCHAR2(30);
    usr        VARCHAR2(128):=user;
    fulltask   VARCHAR2(256);
    dyn_lvl    PLS_INTEGER;
    tmp_owner  VARCHAR2(128);
    tmp_name   VARCHAR2(128);
    stmt       VARCHAR2(30000);

    PROCEDURE parse_name(name VARCHAR2,own VARCHAR2:=NULL) IS
    BEGIN
        tmp_owner := nvl(regexp_substr(name,'^([^.]+)\.',1,1,'i',1),own);
        tmp_name  := regexp_substr(name,'[^.]+$');
    END;

    PROCEDURE check_task(own VARCHAR2:=NULL) IS
    BEGIN
        parse_name(tsk,own);
        IF tmp_name IS NULL AND tid IS NULL THEN
            raise_application_error(-20001,'Please specify the SQL Performance Analyzer task name.');
        END IF;

        SELECT task_id,owner,task_name
        INTO   tid,tmp_owner,tmp_name
        FROM (
            SELECT task_id,owner,task_name
            FROM   dba_advisor_tasks
            WHERE  (task_id=tid  OR upper(task_name)=tmp_name)
            AND    advisor_name='SQL Performance Analyzer'
            AND    upper(owner)=upper(nvl(tmp_owner,owner))
            ORDER  BY decode(upper(owner),upper(tmp_owner),1,upper(user),2,3)) a
        WHERE rownum < 2;
        usr     := tmp_owner;
        tsk     := tmp_name;
        fulltask:= usr||'.'||tsk;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            IF own IS NULL THEN
                raise_application_error(-20001,'No such SQL Performance Analyzer task: '||nvl(tsk,tid));
            ELSE
                usr     := tmp_owner;
                tsk     := tmp_name;
                tid     := NULL;
                fulltask:= usr||'.'||tsk;
            END IF;
    END;

    PROCEDURE check_exec(name VARCHAR2,new_name boolean:=false) IS
    BEGIN
        IF name IS NULL THEN
            IF new_name IS NOT NULL THEN
                raise_application_error(-20001,'Please specify the execution name.');
            END IF;
            RETURN;
        END IF;
        SELECT execution_id,execution_name,execution_type,status
        INTO   eid,nam,typ,estatus
        FROM   dba_advisor_executions
        WHERE  task_id=tid
        AND    (execution_id=regexp_substr(name,'^\d+$') or upper(execution_name)=upper(name));
        IF new_name or new_name IS NULL THEN
            raise_application_error(-20001,'Invalid new execution "'||nam||'('||eid||')" in task '||fulltask||', target already exists.');
        END IF;
    EXCEPTION WHEN no_data_found THEN
        IF NOT new_name THEN
            raise_application_error(-20001,'Invalid execution "'||name||'" in task '||fulltask);
        END IF;
    END;

    PROCEDURE report_start IS
    BEGIN
        IF dyn_lvl IS NULL THEN
            SELECT value into dyn_lvl from v$parameter where name='optimizer_dynamic_sampling';
        END IF;
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=5';
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling='||dyn_lvl;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
BEGIN
    IF &sq > 0 THEN
        IF sq IS NULL THEN
            raise_application_error(-20001,'Please input target SQL Id');
        END IF;

        SELECT COUNT(1)
        INTO   sid
        FROM   DBA_ADVISOR_SQLSTATS
        WHERE  sql_id = sq
        AND    rownum < 2;

        OPEN c1 FOR
            WITH s AS(
                SELECT /*+MATERIALIZE CARDINALITY(1)*/ *
                FROM (&qb)
            )
            SELECT 'SQLSET' SOURCE_TYPE,
                   SQLSET_OWNER||'.'||SQLSET_NAME SOURCE_NAME,
                   SQL_ID ACT_SQL,
                   PLAN_HASH_VALUE PLAN_HASH,
                   EXECUTIONS EXEC,
                   ELAPSED_TIME ELA,
                   ROUND(CPU_TIME/NULLIF(ELAPSED_TIME,0),4) "CPU",
                   NULL IO,
                   NULL PARSE,
                   '|' "|",
                   ROUND(ELAPSED_TIME/GREATEST(EXECUTIONS,1),2) "AVG|ELA",
                   ROUND(BUFFER_GETS/GREATEST(EXECUTIONS,1),2) "AVG|BUFFS",
                   ROUND(DISK_READS/GREATEST(EXECUTIONS,1),2) "AVG|READS",
                   ROUND(DIRECT_WRITES/GREATEST(EXECUTIONS,1),2) "Direct|Writes",
                   ROUND(FETCHES/GREATEST(EXECUTIONS,1),2) "AVG|FETCHES",
                   ROUND(ROWS_PROCESSED/GREATEST(EXECUTIONS,1),2) "AVG|ROWS#",
                   NULL "READ|REQ",
                   NULL "WRITE|REQ",
                   NULL "READ|BYTES",
                   NULL "WRITE|BYTES",
                   NULL "INTER|BYTES"
            FROM   s,dba_sqlset_statements
            WHERE  sql_id = s.sq
            UNION ALL
            SELECT 'SPA EXEC' SOURCE_TYPE,
                   t.TASK_ID||'->'||t.EXECUTION_NAME SOURCE_NAME,
                   NVL(&ATTR17,SQL_ID),
                   PLAN_HASH_VALUE PLAN_HASH,
                   NVL(0+o.attr10,TESTEXEC_TOTAL_EXECS) EXEC,
                   ELAPSED_TIME*NVL(0+o.attr10,TESTEXEC_TOTAL_EXECS)/greatest(EXECUTIONS,1) ELA,
                   ROUND(CPU_TIME/NULLIF(ELAPSED_TIME,0),4) CPU,
                   ROUND(USER_IO_TIME/NULLIF(ELAPSED_TIME,0),4) IO,
                   PARSE_TIME PARSE,
                    '|' "|",
                   ROUND(ELAPSED_TIME/GREATEST(EXECUTIONS,1),2) "AVG|ELA",
                   ROUND(BUFFER_GETS/GREATEST(EXECUTIONS,1),2) BUFFS,
                   ROUND(DISK_READS/GREATEST(EXECUTIONS,1),2) READS,
                   ROUND(DIRECT_WRITES/GREATEST(EXECUTIONS,1),2) DXWRITES,
                   ROUND(FETCHES/GREATEST(EXECUTIONS,1),2),
                   ROUND(ROWS_PROCESSED/GREATEST(EXECUTIONS,1),2) ROWS_,
                   ROUND(PHYSICAL_READ_REQUESTS/GREATEST(EXECUTIONS,1),2) READ_REQ,
                   ROUND(PHYSICAL_WRITE_REQUESTS/GREATEST(EXECUTIONS,1),2) WRITE_REQ,
                   ROUND(PHYSICAL_READ_BYTES/GREATEST(EXECUTIONS,1),2) READ_BYTES,
                   ROUND(PHYSICAL_WRITE_BYTES/GREATEST(EXECUTIONS,1),2) WRITE_BYTES,
                   ROUND(IO_INTERCONNECT_BYTES/GREATEST(EXECUTIONS,1),2) INTER_BYTES
            FROM   s,
                   DBA_ADVISOR_SQLSTATS T,
                   DBA_ADVISOR_OBJECTS  O
            WHERE  t.sql_id = s.sq
            AND    t.task_id=o.task_id
            AND    t.execution_name=o.execution_name
            AND    t.object_id=o.object_id
            AND    t.sql_id=o.attr1
            AND    o.type='SQL';
        GOTO END_BLOCK;
    END IF;

    tsk := nullif(tsk,''||tid);
    dbms_output.enable(null);
    IF tid IS NOT NULL OR tsk IS NOT NULL THEN
        check_task(CASE WHEN op='CREATE' THEN usr END);
    END IF;
    IF op = 'CREATE' THEN
        IF tid IS NOT NULL THEN
            raise_application_error(-20001,'Invalid new task name: '||tid);
        END IF;
        
        IF tid IS NOT NULL THEN
            raise_application_error(-20001,'Target task already exists: '||fulltask);
        ELSIF v3 IS NULL THEN
            raise_application_error(-20001,'Please specify the source sqlset name');
        END IF;
        parse_name(v3);
        dbms_output.put_line('SQL Performance Analyzer task is created: '||user||'.'||
            dbms_sqlpa.create_analysis_task(
                sqlset_owner=>tmp_owner,
                sqlset_name =>tmp_name,
                task_name   =>tsk,
                basic_filter=>:filter));
        dbms_sqlpa.execute_analysis_task(
            task_name      => tsk,
            execution_type => 'CONVERT SQLSET',
            execution_name => 'CONVERT_SQLSET');
        dbms_sqlpa.set_analysis_task_parameter(tsk,'COMPARISON_METRIC','COMPARISON_METRIC');
        RETURN;
    ELSIF op = 'DROP' THEN
        sys.dbms_sqlpa.drop_analysis_task(tsk);
        dbms_output.put_line('SQL Performance Analyzer task is dropped: '||fulltask);
        RETURN;
    ELSIF op = 'ALTER' THEN
        IF v3 IS NULL THEN
            dbms_output.put_line('Please specify the parameter name and value.');
        ELSE
            dbms_sqlpa.set_analysis_task_parameter(tsk,v3,v4);
            dbms_output.put_line('Parameter '||v3||' is set as '||v4||'.'||chr(10));
        END IF;
    ELSIF op in ('COMPARE','DIFF') THEN
        IF v3 IS NULL OR V4 IS NULL THEN
            raise_application_error(-20001,'Please specify the pre and post execution name for the comparison.');
        END IF;
        op     := 'COMPARE';
        check_exec(v3);
        sid    := eid;
        pre    := nam;
        check_exec(v4);
        post   := nam;
        nam    := 'DIFF_'||sid||'_'||eid;
        dop    := 1;
        check_exec(v5,NULL);
        nam    := sys.dbms_sqlpa.execute_analysis_task(
            task_name       => tsk,
            execution_type  => op,
            execution_name  => v5,
            execution_params=> sys.dbms_advisor.arglist(
                'execution_name1', pre, 
                'execution_name2', post));
        check_exec(nam);
        key := 'HTML';
        dbms_output.put_line('Execution '||nam||'('||eid||') of task '||tsk||' is completed with default COMPARISON_METRIC.');
    ELSIF op IN ('EXEC','EXECUTE','TEST','XPLAN','EXPLAIN') THEN
        check_exec(trim('.' from v3),null);
        dop := regexp_substr(v4,'^\d+$');
        IF dop IS NOT NULL THEN
            BEGIN
                sys.dbms_sqlpa.set_analysis_task_parameter(tsk,'TEST_EXECUTE_DOP',dop);
            EXCEPTION WHEN OTHERS THEN 
                dbms_output.put_line('Unsupported TEST_EXECUTE_DOP parameter in this Oracle release.');
            END;
        END IF;
        IF op IN ('EXEC','EXECUTE','TEST') THEN
            op := 'EXECUTE';
        ELSIF op IN('XPLAN','EXPLAIN') THEN
            op := 'EXPLAIN';
        END IF;
        stmt := utl_lms.format_message(
                    q'~BEGIN sys.dbms_sqlpa.execute_analysis_task(task_name=>'%s',execution_type=>'%s',execution_name=>'%s'); END;~',
                    tsk,op,nam);
        IF &sync=1 THEN
            execute immediate stmt;
            dbms_output.put_line('Execution '||nam||' of task '||tsk||' is completed.');
        ELSE
            snam := dbms_scheduler.generate_job_name('SPA_EXEC_');
            dbms_scheduler.create_job(
                job_name   => snam,
                job_type   => 'PLSQL_BLOCK',
                job_action => stmt,
                enabled    => true);
            dbms_output.put_line('Execution '||nam||' of task '||tsk||' is running in background job '||snam);
        END IF;
    ELSIF op ='STOP' THEN
        check_exec(v3);
        IF estatus NOT IN('INTERRUPTED','EXECUTING') THEN
            raise_application_error(-20001,'The target execution is not interrupted or executing.');
        END IF;
        sys.dbms_sqlpa.cancel_analysis_task(tsk);
    ELSIF op ='PAUSE' THEN
        check_exec(v3);
        IF estatus NOT IN('EXECUTING') THEN
            raise_application_error(-20001,'The target execution is not executing.');
        END IF;
        sys.dbms_sqlpa.interrupt_analysis_task(tsk);
    ELSIF op='RESUME' THEN
        check_exec(v3);
        IF estatus NOT IN('INTERRUPTED') THEN
            raise_application_error(-20001,'The target execution is not interrupted.');
        END IF;
        stmt := 'BEGIN sys.dbms_sqlpa.resume_analysis_task('''||tsk||'''); END;';
        IF &sync=0 THEN
            snam := dbms_scheduler.generate_job_name('SPA_EXEC_');
            dbms_scheduler.create_job(
                job_name   => snam,
                job_type   => 'PLSQL_BLOCK',
                job_action => stmt,
                enabled    => true);
            dbms_output.put_line('Execution '||nam||' of task '||tsk||' is running in background job '||snam);
        ELSE
            execute immediate stmt;
        END IF;
    END IF;
   
    IF tsk IS NOT NULL THEN
        SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
               MAX(attr3),
               MAX(attr1),
               nvl(MAX(fil),'1=1'),
               max(sq_id),
               max(sq_nid),
               max(sq_txt)
        INTO   sown,snam,fil,sq_id,sq_nid,sq_txt
        FROM (
            SELECT decode(type,'SQLSET',attr3) attr3,
                   decode(type,'SQLSET',attr1) attr1,
                   null fil,
                   decode(type,'SQL',attr1) sq_id,
                   decode(type,'SQL',&attr17) sq_nid,
                   decode(type,'SQL',trim(regexp_replace(to_char(substr(attr4,1,200)),'\s+',' '))) sq_txt
            FROM   dba_advisor_objects 
            WHERE  TASK_ID = tid
            AND    EXECUTION_NAME IS NULL
            AND    TYPE IN('SQLSET','SQL')
            UNION ALL
            SELECT MAX(DECODE(parameter_name,'SQLSET', owner, 'SQLSET_OWNER', parameter_value)),
                   MAX(DECODE(parameter_name,'SQLSET', parameter_value, 'SQLSET_NAME', parameter_value)),
                   MAX(DECODE(parameter_name,'BASIC_FILTER', parameter_value)),
                   null,null,null
            FROM   dba_advisor_exec_parameters
            JOIN   dba_advisor_executions
            USING  (owner,task_id,task_name,execution_name,owner)
            WHERE  TASK_ID = tid
            AND    execution_id=eid
            AND    parameter_value!='UNUSED'
            UNION ALL
            SELECT MAX(DECODE(parameter_name,'SQLSET', owner, 'SQLSET_OWNER', parameter_value)),
                   MAX(DECODE(parameter_name,'SQLSET', parameter_value, 'SQLSET_NAME', parameter_value)),
                   MAX(DECODE(parameter_name, 'BASIC_FILTER', parameter_value)),
                   null,null,null
            FROM   dba_advisor_parameters
            WHERE  TASK_ID = tid
            AND    parameter_value!='UNUSED');
    END IF;

    IF tid IS NULL THEN
        m1 := 'DBA_ADVISOR_TASKS WHERE ADVISOR_NAME=''SQL Performance Analyzer''';
        OPEN c1 FOR
            WITH r AS
             (SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 5)*/ 
                     A.*, 
                     (SELECT COUNT(1) FROM dba_advisor_executions where task_id = a.task_id and owner=a.owner) execs,
                     (SELECT /*+no_unnest outline*/ COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id and owner=a.owner) findings,
                     (SELECT decode(MAX(y.type),
                                'SQL'   ,MAX(y.attr1||' -> '|| nvl(sqln,y.attr3)),
                                'SQLSET',MAX(nullif(y.attr3||'.'||y.attr1,'.')),
                                nullif(MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value)) ||
                                  '.'||MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)) ,'.'))
                      FROM   (
                             SELECT * 
                             FROM   dba_advisor_parameters 
                             WHERE  parameter_name in('SQLSET_OWNER','SQLSET_NAME') 
                             AND    parameter_value!='UNUSED') x
                      FULL JOIN (
                             SELECT y.*,&attr17 sqln 
                             FROM   dba_advisor_objects y 
                             WHERE  type in('SQLSET','SQL') 
                             AND    execution_name IS NULL) y
                      USING (owner,task_id)
                      WHERE  task_id = a.task_id
                      AND    owner = a.owner) SQLSET
              FROM   (SELECT task_id, advisor_name, owner, task_name, execution_start, execution_end, status,DESCRIPTION
                      FROM   dba_advisor_tasks a
                      WHERE  (&FILTER)
                      AND    advisor_name LIKE 'SQL Performance%'
                      ORDER  BY execution_start DESC NULLS LAST) A
              WHERE  ROWNUM <= 50),
            r1 AS
             (SELECT task_id,
                     MAX(DECODE(parameter_name, 'TEST_EXECUTE_DOP', parameter_value)) DOP,
                     MAX(DECODE(parameter_name, 'EXECUTE_FULLDML', parameter_value)) FULLDML,
                     MAX(DECODE(parameter_name, 'COMPARE_RESULTSET', parameter_value)) COMP,
                     MAX(DECODE(parameter_name, 'CELL_SIMULATION_ENABLED', parameter_value)) SIM_EXADATA,
                     MAX(DECODE(parameter_name, 'LOCAL_TIME_LIMIT', parameter_value)) SQL_LIMIT,
                     NULLIF(MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value))||'.'||MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)),'.') SQLSET
              FROM   (SELECT OWNER,TASK_ID FROM R) R
              JOIN   DBA_ADVISOR_PARAMETERS
              USING  (OWNER,TASK_ID)
              GROUP  BY task_id)
            SELECT R.TASK_ID,
                   R.OWNER,
                   R.TASK_NAME,
                   NVL(R.SQLSET,R1.SQLSET) "SQL[SET]",
                   R1.DOP            "TEST|CONCURRENCY",
                   R1.FULLDML        "EXECUTE|FULL DML",
                   R1.COMP           "COMPARE|RESULT",
                   R1.SIM_EXADATA    "SIMULATE|EXDATA",
                   R1.SQL_LIMIT      "SQL|TIMEOUT",
                   r.execs,
                   R.findings,
                   r.status,
                   r.execution_start,
                   (SELECT nvl(to_char(r.execution_end),
                                   decode(count(1),
                                       0,'Not Started',
                                       sum(sofar)||'/'||sum(totalwork)||' ('||round(sum(sofar)*100/greatest(sum(totalwork),1),2)||'%)'))
                    FROM   gv$advisor_progress a
                    WHERE  a.task_id=r.task_id) "EXECUTION_END(PROG)",
                   r.DESCRIPTION
            FROM   R
            LEFT   JOIN R1
            ON     (r.task_id=r1.task_id)
            ORDER  BY execution_start DESC NULLS LAST;
    ELSIF eid IS NULL THEN
        m1 := 'TASK PARAMETERS FOR '||fulltask;
        OPEN c1 FOR
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                   PARAMETER_NAME,
                   regexp_replace(nvl(B.PARAMETER_VALUE, A.PARAMETER_VALUE),'(.{50})','\1'||chr(10)) PARAMETER_VALUE,
                   PARAMETER_TYPE,
                   IS_DEFAULT,
                   IS_OUTPUT,
                   IS_MODIFIABLE_ANYTIME IS_MDF,
                   DESCRIPTION
            FROM   (SELECT * FROM dba_advisor_def_parameters WHERE ADVISOR_NAME = 'SQL Performance Analyzer') a
            FULL   JOIN (SELECT PARAMETER_NAME, PARAMETER_VALUE
                         FROM   DBA_ADVISOR_PARAMETERS
                         WHERE  TASK_ID = tid) b
            USING  (PARAMETER_NAME)
            UNION ALL
            SELECT TYPE,
                   ATTR1,
                   NULL,NULL,NULL,NULL,
                   trim(regexp_replace(to_char(substr(attr4,1,200)),'\s+',' '))
            FROM   dba_advisor_objects
            WHERE  TASK_ID = tid
            AND    EXECUTION_NAME IS NULL
            ORDER  BY PARAMETER_NAME;
        IF nvl(op,'x') !='ALTER' THEN
            m2 := 'EXECUTIONS FOR '||usr||'.'||tsk;
            OPEN c2 FOR
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                       EXECUTION_ID EXEC_ID,
                       EXECUTION_NAME,
                       EXECUTION_TYPE,
                       EXECUTION_START,
                       EXECUTION_END,
                       STATUS,
                       &ver  REQUESTED_DOP "REQ|DOP", ACTUAL_DOP "ACT|DOP",
                       (SELECT parameter_value
                        FROM   DBA_ADVISOR_EXEC_PARAMETERS B
                        WHERE  B.task_id=tid
                        AND    B.owner=a.owner
                        AND    B.execution_name=a.execution_name
                        AND    B.parameter_name='LOCAL_TIME_LIMIT') "SQL|TIMEOUT", 
                       (SELECT /*+outline no_unnest*/ COUNT(1) 
                        FROM  DBA_ADVISOR_FINDINGS
                        WHERE task_id=tid
                        AND   owner=a.owner
                        AND   execution_name=a.execution_name) finds,
                       (SELECT CASE WHEN A.EXECUTION_TYPE LIKE 'COMPARE%' THEN
                                   MAX(DECODE(n,'COMPARISON_METRIC',v||': ')) ||
                                   MAX(DECODE(n,'EXECUTION_NAME1',v||'/')) ||
                                   MAX(DECODE(n,'EXECUTION_NAME2',v))
                               ELSE 
                                   'PLAN_FILTER: '||MAX(DECODE(n,'PLAN_FILTER',v))
                               END
                        FROM  (SELECT TASK_ID,execution_name,parameter_name n,parameter_value v from DBA_ADVISOR_EXEC_PARAMETERS) B 
                        WHERE task_id=tid
                        AND   owner=a.owner
                        AND   execution_name=a.execution_name
                        ) ATTR1,
                       ERROR_MESSAGE
                FROM   DBA_ADVISOR_EXECUTIONS A
                WHERE  task_id = tid
                ORDER  BY EXECUTION_END DESC;
        END IF;
    ELSE
        key := CASE WHEN key IS NULL THEN '%' WHEN KEY IN('HTML','HTM','TEXT','TXT','ACTIVE') THEN KEY ELSE '%'||key||'%' END;

        SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
               MAX(b.EXECUTION_TYPE),
               REPLACE(MAX(decode(parameter_name,'COMPARISON_METRIC',parameter_value)),'UNUSED','ELAPSED_TIME'),
               MAX(b.EXECUTION_NAME),
               MAX(decode(parameter_name,'EXECUTION_NAME1',parameter_value)),
               MAX(decode(parameter_name,'EXECUTION_NAME2',parameter_value))
        INTO   typ,ord,nam,pre,post
        FROM   dba_advisor_exec_parameters A,DBA_ADVISOR_EXECUTIONS b
        WHERE  a.task_id = tid
        AND    b.task_id = tid
        AND    a.owner=b.owner
        AND    a.EXECUTION_NAME=b.EXECUTION_NAME
        AND    b.EXECUTION_ID=eid;

        m1 := 'PARAMETERS FOR TASK PARAMETER '||usr||'.'||tsk|| ' -> '||nam;
        OPEN c1 FOR
            SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
                   PARAMETER_NAME,
                   regexp_replace(nvl(B.PARAMETER_VALUE, A.PARAMETER_VALUE),'(.{50})','\1'||chr(10)) PARAMETER_VALUE,
                   PARAMETER_TYPE,
                   IS_DEFAULT,
                   IS_OUTPUT,
                   IS_MODIFIABLE_ANYTIME IS_MDF,
                   DESCRIPTION
            FROM   (SELECT * FROM dba_advisor_def_parameters WHERE ADVISOR_NAME = 'SQL Performance Analyzer') a
            FULL   JOIN (SELECT PARAMETER_NAME, PARAMETER_VALUE
                         FROM   dba_advisor_exec_parameters
                         WHERE  TASK_ID = tid
                         AND    EXECUTION_NAME=nam) b
            USING  (PARAMETER_NAME)
            ORDER  BY PARAMETER_NAME;

        m2 := 'TYPE: ['||typ||']      SORT: ['||ord||']      TOP: [50]';
        IF typ LIKE 'COMPARE%' THEN
            OPEN c2 FOR
                WITH R AS(
                    SELECT rownum "#",a.*
                    FROM (
                        SELECT f.*,
                               &attr17 sqln,
                               attr5 prev_phv,
                               round(ratio_to_report(&ord1) over(),8) "Weight"
                        FROM (
                            SELECT f.*,nullif(round(f.attr9/nullif(f.attr8,0),8),0) diff
                            FROM   dba_advisor_objects f
                            WHERE  TASK_ID = tid
                            AND    EXECUTION_NAME=nam
                            AND    TYPE='SQL'
                            AND    ATTR1 IS NOT NULL
                            AND   (substr(key,1,1)!='%' OR upper(attr1||'@'||'@'||&attr17||'@'||attr5||'@'||&attr11) LIKE key)
                        ) f 
                        WHERE &ord1>0
                        ORDER BY "Weight" DESC NULLS LAST) a
                    WHERE rownum<=50)
                SELECT /*+outline_leaf leading(f) use_nl(pre post s)
                          push_pred(pre) push_pred(post) push_pred(s)
                          */
                       "#",  
                       attr1 org_sql,
                       coalesce(pre.sqln,sq_nid,attr1) prev_sql,
                       nvl(pre.phv,''||f.attr5) prev_phv,
                       coalesce(post.sqln,sq_nid,attr1) post_sql,
                       nvl(post.phv,''||f.attr5) post_phv,
                       '|' "|",
                       f.attr10 execs,
                       f.attr8 prev_cost,
                       f.attr9 post_cost,
                       round(greatest(f.diff,1/f.diff)*sign(f.attr9-f.attr8),3) diff,
                       f."Weight",
                       '|' "*",
                       nvl(sq_txt,substr(sql_text,1,200)) sql_text
                FROM r f
                LEFT JOIN (SELECT o.*,&attr17 sqln,
                                  case when nvl(s.plan_hash_value,0)=0 and s.elapsed_time is null then 'ERROR' else ''||s.plan_hash_value end phv
                           FROM   dba_advisor_objects o,
                                  dba_advisor_sqlstats s
                           WHERE  o.TASK_ID = tid 
                           AND    o.EXECUTION_NAME=pre
                           AND    o.type='SQL'
                           AND    s.TASK_ID = tid
                           AND    s.EXECUTION_NAME=pre
                           AND    o.object_id=s.object_id
                           AND    o.attr1=s.sql_id
                           ) PRE USING(OWNER,ATTR1)
                LEFT JOIN (SELECT o.*,&attr17 sqln,
                                  case when nvl(s.plan_hash_value,0)=0 and s.elapsed_time is null then 'ERROR' else ''||s.plan_hash_value end phv
                           FROM   dba_advisor_objects o,
                                  dba_advisor_sqlstats s
                           WHERE  o.TASK_ID = tid 
                           AND    o.EXECUTION_NAME=post
                           AND    o.type='SQL'
                           AND    s.TASK_ID = tid
                           AND    s.EXECUTION_NAME=post
                           AND    o.object_id=s.object_id
                           AND    o.attr1=s.sql_id
                           ) POST USING(OWNER,ATTR1)
                LEFT JOIN (SELECT DISTINCT
                                 s.sql_id attr1,
                                 trim(regexp_replace(to_char(substr(sql_text,1,2500)),'\s+',' ')) sql_text
                           FROM  DBA_SQLSET_STATEMENTS s
                           WHERE sqlset_owner=sown
                           AND   sqlset_name=snam) s USING(attr1)
                ORDER BY "#";
        ELSIF typ like 'CONVERT%' THEN
            stmt := replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand outline opt_param('optimizer_dynamic_sampling' 5) leading(a.f a.s a.p)*/ 
                         round(ratio_to_report(@ord@) over(),5) "Weight",
                         sql_id,
                         plan_hash_value plan_hash,
                         '|' "|",
                         executions execs,
                         elapsed_time ela,
                         elapsed_time/GREATEST(EXECUTIONS,1) avg_ela,
                         round(cpu_time/nullif(elapsed_time,0),4) cpu,
                         '|' "*",
                         trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' ')) sql_text
                    FROM  DBA_SQLSET_STATEMENTS a
                    WHERE sqlset_owner=:sown AND sqlset_name=:snam
                    AND   (substr(:1,1,1)!='%' OR upper(sql_id||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1)~'
                    ||' AND ('||fil||')
                    ORDER BY "Weight" DESC NULLS LAST
                ) WHERE ROWNUM<=50','@ord@',ord);
            --dbms_output.put_line(stmt);
            OPEN c2 FOR stmt USING sown,snam,key,key,key;
        ELSIF typ = 'TEST EXECUTE' and &phv=1 THEN
            OPEN c2 FOR
                SELECT /*+outline leading(a) use_nl(s) push_pred(s)*/
                       a.*,
                       '|' "|",
                       s.s.sql_text
                FROM (
                    SELECT /*+outline_leaf use_hash(a s) parallel(8)*/
                           ROUND(ratio_to_report(LOG(2,GREATEST(a.avg_ela/s.avg_ela,s.avg_ela/a.avg_ela))*ABS(a.avg_ela-s.avg_ela)*a.exec) OVER(),5) "Weight",
                           s.signatures,
                           s.sqls,
                           s.top_sql，
                           phv src_phv,
                           a.phv_n spa_phv,
                           '|' "|",
                           a.exec,
                           a.avg_ela*a.exec ela,
                           ROUND(s.avg_ela,3) src_avg,
                           ROUND(a.avg_ela,3) spa_avg,
                           ROUND(GREATEST(a.avg_ela/s.avg_ela,s.avg_ela/a.avg_ela)*sign(a.avg_ela-s.avg_ela),2) diff
                    FROM   (SELECT decode(a.attr5,'0',a.attr1,a.attr5) phv,
                                   b.plan_hash_value phv_n,
                                   SUM(attr10) exec,
                                   SUM(b.elapsed_time) / SUM(GREATEST(b.executions, 1)) avg_ela
                            FROM   dba_advisor_objects a, dba_advisor_sqlstats b
                            WHERE  a.TYPE = 'SQL'
                            AND    a.object_id = b.object_id
                            AND    a.attr1 = b.sql_id
                            AND    a.task_id = tid
                            AND    b.task_id = tid
                            AND    a.execution_name=nam
                            AND    b.execution_name=nam
                            AND  （b.plan_hash_value=0 OR ''||b.plan_hash_value!=a.attr5)
                            AND    a.attr5 is not null
                            GROUP  BY decode(a.attr5,'0',a.attr1,a.attr5),b.plan_hash_value) a
                    JOIN   (SELECT --+outline leading(a.f a.s a.p)
                                   decode(plan_hash_value,0,sql_id,''||plan_hash_value) phv, 
                                   SUM(elapsed_time) / SUM(executions) avg_ela, SUM(executions) EXEC,
                                   MAX(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time) top_sql,
                                   COUNT(DISTINCT sql_id) sqls,
                                   COUNT(DISTINCT force_matching_signature) signatures
                            FROM   dba_sqlset_statements a
                            WHERE  executions > 0
                            AND    sqlset_owner=sown 
                            AND    sqlset_name=snam
                            GROUP  BY decode(plan_hash_value,0,sql_id,''||plan_hash_value)) s
                    USING  (phv)
                    WHERE &pfilter
                    ORDER BY "Weight" DESC NULLS LAST) a
                LEFT JOIN (SELECT DISTINCT
                                 s.sql_id,
                                 trim(regexp_replace(to_char(substr(sql_text,1,2500)),'\s+',' ')) sql_text
                           FROM  DBA_SQLSET_STATEMENTS s
                           WHERE sqlset_owner=sown
                           AND   sqlset_name=snam) s
                ON(a.top_sql=s.sql_id)
                WHERE rownum<=50
                ORDER BY "Weight" DESC NULLS LAST;
        ELSE
            ord := CASE WHEN typ like 'EXPLAIN%' THEN 'ela' ELSE ord end;
            OPEN c2 FOR replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand opt_param('optimizer_dynamic_sampling' 5) outline_leaf use_hash(a b s)*/ 
                         round(ratio_to_report(@ord@) over(),5) "Weight",
                         sql_id org_sql_id,
                         phv org_plan,
                         coalesce(sqln,:sq_id,sql_id) act_sql_id,
                         b.plan_hash_value plan_hash,
                         '|' "|",
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',execs,0+a.attr10) execs,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela,b.elapsed_time*a.attr10/greatest(b.executions,1)) ela,
                         round(decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela/nullif(execs,0),b.elapsed_time/greatest(b.executions,1)),2) avg_ela,
                         round(decode(EXECUTION_TYPE,'EXPLAIN PLAN',cpu/nullif(ela,0),b.cpu_time/nullif(b.elapsed_time,0)),5) cpu,
                         '|' "*",
                         nvl(:sq_txt,trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' '))) sql_text
                    FROM  (
                        SELECT a.*,attr1 sql_id,attr5 phv,&attr17 sqln 
                        FROM  DBA_ADVISOR_OBJECTS A
                        WHERE task_id=:tid
                        AND   EXECUTION_NAME=:nam
                        AND   type='SQL'
                        AND  (substr(:1,1,1)!='%' OR upper(attr1||'@'||'@'||&attr17||'@'||attr5||'@'||&attr11) like :1)
                        ) A
                    LEFT JOIN (
                        SELECT * 
                        FROM   DBA_ADVISOR_SQLSTATS
                        WHERE  task_id=:tid
                        AND    EXECUTION_NAME=:nam)  B
                    USING (sql_id,object_id)
                    LEFT JOIN (
                        SELECT * 
                        FROM  (SELECT /*+outline leading(a.f a.s a.p)*/
                                      sql_id,
                                      plan_hash_value phv,
                                      elapsed_time ela,
                                      executions execs,
                                      cpu_time cpu,
                                      sql_text,
                                      ROW_NUMBER() OVER(PARTITION BY sql_id,plan_hash_value order by elapsed_time desc) seq
                               FROM   DBA_SQLSET_STATEMENTS  
                               WHERE  sqlset_owner=:sown AND sqlset_name=:snam)
                        WHERE seq=1) s USING(sql_id,phv)
                    ORDER BY "Weight" DESC NULLS LAST
                ) WHERE ROWNUM<=50~','@ord@',ord) USING sq_nid,sq_txt,tid,nam,key,key,tid,nam,sown,snam;
        END IF;

        IF KEY IN('HTML','HTM','TEXT','ACTIVE') THEN
            fname := 'spa_'||tid||'_'||eid||'.';
            report_start;
            IF key IN ('TEXT','TXT') or DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.RELEASE<14 THEN
                fname := fname ||'txt';
                key   := 'TEXT';
            ELSE
                fname := fname ||'html';
                key   := regexp_replace(key,'^HTM$','HTML');
            END IF;
            frs := sys.DBMS_SQLPA.REPORT_ANALYSIS_TASK(task_name=>tsk,task_owner=>usr,section=>'ALL',level=>'ALL',type=>key);
            report_end;
        END IF;
    END IF;

    <<END_BLOCK>>
    :c1 := c1;
    :c2 := c2;
    :fn := fname;
    :fc := frs;
    :m1 := m1;
    :m2 := m2;
END;
/

print c1 "&m1"
print c2 "&m2"
save fc fn