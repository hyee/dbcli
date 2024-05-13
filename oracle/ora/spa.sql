/*[[
    Manage SQL Performance Analyzer(SPA). type 'help @@NAME' for more detail.
    Usages:
        @@NAME                                          : show all SPA tasks
        @@NAME -f"<filter>"                             : filter on dba_advisor_tasks
        @@NAME <task>                                   : show details of target task
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
        @@NAME <task> <ename>  [<parameters>]           : show details of target executions, following with below parameters:
                                                            -diff     : order by abs(diff)
                                                            -regress  : order by regression
                                                            -improve  : order by improvement
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
        &ord1  : default={"Weight"} diff={greatest(diff,1/nullif(diff,0))} regress={diff} improve={1/nullif(diff,0)}
        &sync  : default={0} sync={1}
    --]]--
]]*/

set verify off feed off
col prev_cost,post_cost,sort_value for K0
col weight,cpu for pct2
col ela,avg_ela for usmhd2
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
               MAX(attr3),MAX(attr1),nvl(MAX(fil),'1=1'),max(sq_id)，max(sq_nid),max(sq_txt)
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
            SELECT MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value)),
                   MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)),
                   MAX(DECODE(parameter_name, 'BASIC_FILTER', parameter_value)),
                   null,null,null
            FROM   dba_advisor_exec_parameters
            JOIN   dba_advisor_executions
            USING  (task_id,task_name,execution_name)
            WHERE  TASK_ID = tid
            AND    execution_id=eid
            AND    parameter_value!='UNUSED'
            UNION ALL
            SELECT MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value)),
                   MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)),
                   MAX(DECODE(parameter_name, 'BASIC_FILTER', parameter_value))，
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
                     (SELECT COUNT(1) FROM dba_advisor_executions where task_id = a.task_id) execs,
                     (SELECT COUNT(1) FROM dba_advisor_findings WHERE task_id = a.task_id) findings,
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
                      USING (task_id)
                      WHERE  task_id = a.task_id) SQLSET
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
                     MAX(DECODE(parameter_name, 'TIME_LIMIT', parameter_value)) TIME_LIMIT,
                     NULLIF(MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value))||'.'||MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)),'.') SQLSET
              FROM   (SELECT TASK_ID FROM R) R
              JOIN   DBA_ADVISOR_PARAMETERS
              USING  (TASK_ID)
              WHERE  PARAMETER_VALUE != 'UNUSED'
              GROUP  BY task_id)
            SELECT TASK_ID,
                   R.OWNER,
                   R.TASK_NAME,
                   NVL(R.SQLSET,R1.SQLSET) "SQL[SET]",
                   R1.DOP            "TEST|CONCURRENCY",
                   R1.FULLDML        "EXECUTE|FULL DML",
                   R1.COMP           "COMPARE|RESULT",
                   R1.SIM_EXADATA    "SIMULATE|EXDATA",
                   R1.TIME_LIMIT     "TIME|LIMIT",
                   r.execs,
                   R.findings,
                   r.status,
                   r.execution_start,
                   r.execution_end,
                   r.DESCRIPTION
            FROM   R
            LEFT   JOIN R1
            USING  (TASK_ID)
            ORDER  BY execution_start DESC NULLS LAST;
    ELSIF eid IS NULL THEN
        m1 := 'TASK PARAMETERS FOR '||fulltask;
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
            LEFT   JOIN (SELECT PARAMETER_NAME, PARAMETER_VALUE
                         FROM   DBA_ADVISOR_PARAMETERS
                         WHERE  TASK_ID = tid
                         AND    PARAMETER_VALUE != 'UNUSED') b
            USING  (PARAMETER_NAME)
            WHERE  A.ADVISOR_NAME = 'SQL Performance Analyzer'
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
                       &ver  REQUESTED_DOP REQ_DOP, ACTUAL_DOP ACT_DOP,
                       DECODE(
                        EXECUTION_TYPE,'CONVERT SQLSET',
                        EXTRACTVALUE(dbms_xmlgen.getxmltype(
                             'SELECT COUNT(1) X
                              FROM   DBA_SQLSET_STATEMENTS
                              WHERE  sqlset_owner='''||sown||'''
                              AND    sqlset_name='''||snam||'''
                              AND    ('||fil||')'),'//X')+0,
                       (SELECT COUNT(1) 
                        FROM  DBA_ADVISOR_OBJECTS 
                        WHERE task_id=tid 
                        AND   execution_name=a.execution_name)) objs,
                       (SELECT COUNT(1) 
                        FROM  DBA_ADVISOR_FINDINGS
                        WHERE task_id=tid 
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
                        AND   execution_name=a.execution_name
                        AND   v!='UNUSED') ATTR1,
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
        AND    a.EXECUTION_NAME=b.EXECUTION_NAME
        AND    b.EXECUTION_ID=eid;

        m1 := 'PARAMETERS FOR TASK PARAMETER '||usr||'.'||tsk|| ' -> '||nam;
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
            LEFT   JOIN (SELECT PARAMETER_NAME, PARAMETER_VALUE
                         FROM   dba_advisor_exec_parameters
                         WHERE  TASK_ID = tid
                         AND    PARAMETER_VALUE != 'UNUSED'
                         AND    EXECUTION_NAME=nam) b
            USING  (PARAMETER_NAME)
            WHERE  A.ADVISOR_NAME = 'SQL Performance Analyzer'
            ORDER  BY PARAMETER_NAME;

        m2 := 'TYPE: ['||typ||']      SORT: ['||ord||']      TOP: [50]';
        IF typ LIKE 'COMPARE%' THEN
            OPEN c2 FOR
                WITH R AS(
                    SELECT /*+materialize*/ *
                    FROM   dba_advisor_objects A
                    WHERE  TASK_ID = tid
                    AND    EXECUTION_NAME in(nam,pre,post)
                    AND    ATTR1 IS NOT NULL),
                S AS(
                    SELECT /*+materialize*/ EXECUTION_NAME,sql_id attr1,
                           case when nvl(plan_hash_value,0)=0 and elapsed_time is null then 
                              'ERROR' 
                            else ''||PLAN_HASH_VALUE end phv
                    FROM   dba_advisor_sqlstats A
                    WHERE  TASK_ID = tid
                    AND    EXECUTION_NAME in(pre,post)),
                F AS(
                    SELECT attr1 org_sql,
                           coalesce(pre.sqln,sq_nid,attr1) prev_sql,
                           nvl(p1.phv,''||f.attr5) prev_phv,
                           coalesce(post.sqln,sq_nid,attr1) post_sql,
                           nvl(p2.phv,''||f.attr5) post_phv,
                           '|' "|",
                           f.attr10 execs,
                           f.attr8 prev_cost,
                           f.attr9 post_cost,
                           round(f.attr9/nullif(f.attr8,0),2) diff,
                           round(ratio_to_report(NVL(F.ATTR9,0)-NVL(f.attr8,0)) over(),8) "Weight",
                           '|' "*",
                           nvl(sq_txt,substr(sql_text,1,200)) sql_text
                    FROM (SELECT * FROM R WHERE EXECUTION_NAME=nam) F
                    LEFT JOIN (SELECT R.*,&attr17 sqln FROM R WHERE EXECUTION_NAME=pre) PRE USING(ATTR1)
                    LEFT JOIN (SELECT R.*,&attr17 sqln FROM R WHERE EXECUTION_NAME=post) POST USING(ATTR1)
                    LEFT JOIN (SELECT S.* FROM S WHERE EXECUTION_NAME=pre) p1 USING(ATTR1)
                    LEFT JOIN (SELECT S.* FROM S WHERE EXECUTION_NAME=post) p2 USING(ATTR1)
                    LEFT JOIN (SELECT /*+no_merge*/ DISTINCT
                                     sql_id attr1,
                                     trim(regexp_replace(to_char(substr(sql_text,1,2500)),'\s+',' ')) sql_text
                               FROM  DBA_SQLSET_STATEMENTS 
                               WHERE sqlset_owner=sown
                               AND   sqlset_name=snam) s USING(attr1)
                    WHERE substr(key,1,1)!='%' 
                    OR    upper(attr1||'~'||pre.sqln||'~'||post.sqln||
                                f.attr5||'~'||p1.phv||'~'||p2.phv||'~'||sql_text)
                    LIKE  key
                    ORDER BY &ord1 DESC NULLS LAST)
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ * FROM F WHERE ROWNUM<=50;
        ELSIF typ like 'CONVERT%' THEN
            stmt := replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand opt_param('optimizer_dynamic_sampling' 5)*/ 
                         round(ratio_to_report(@ord@) over(),4) "Weight",
                         sql_id,
                         plan_hash_value plan_hash,
                         '|' "|",
                         @ord@ sort_value,
                         executions execs,
                         elapsed_time ela,
                         elapsed_time/nullif(executions,0) avg_ela,
                         round(cpu_time/nullif(elapsed_time,0),4) cpu,
                         '|' "*",
                         trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' ')) sql_text
                    FROM  DBA_SQLSET_STATEMENTS 
                    WHERE sqlset_owner=:sown AND sqlset_name=:snam
                    AND   (substr(:1,1,1)!='%' OR upper(sql_id||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1)~'
                    ||' AND ('||fil||')
                    ORDER BY sort_value DESC NULLS LAST
                ) WHERE ROWNUM<=50','@ord@',ord);
            --dbms_output.put_line(stmt);
            OPEN c2 FOR stmt USING sown,snam,key,key,key;
        ELSE
            ord := CASE WHEN typ like 'EXPLAIN%' THEN 'ela' ELSE ord end;
            OPEN c2 FOR replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand opt_param('optimizer_dynamic_sampling' 5)*/ 
                         round(ratio_to_report(@ord@) over(),4) "Weight",
                         sql_id org_sql_id,
                         phv org_plan,
                         coalesce(sqln,:sq_id,sql_id) act_sql_id,
                         plan_hash_value plan_hash,
                         '|' "|",
                         @ord@ sort_value,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',execs,executions) execs,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela,elapsed_time) ela,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela/nullif(execs,0),elapsed_time/nullif(executions,0)) avg_ela,
                         round(decode(EXECUTION_TYPE,'EXPLAIN PLAN',cpu/nullif(ela,0),cpu_time/nullif(elapsed_time,0)),4) cpu,
                         '|' "*",
                         nvl(:sq_txt,trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' '))) sql_text
                    FROM  (select a.*,attr1 sql_id,&attr17 sqln FROM DBA_ADVISOR_OBJECTS A) A
                    RIGHT JOIN  DBA_ADVISOR_SQLSTATS B
                    USING (task_id,execution_name,sql_id)
                    LEFT JOIN (
                        SELECT * FROM 
                             (SELECT /*+no_merge*/
                                     sql_id,
                                     plan_hash_value phv,
                                     elapsed_time ela,
                                     executions execs,
                                     cpu_time cpu,
                                     sql_text,
                                     ROW_NUMBER() OVER(PARTITION BY sql_id order by elapsed_time desc) seq
                               FROM  DBA_SQLSET_STATEMENTS 
                               WHERE sqlset_owner=:sown AND sqlset_name=:snam)
                        WHERE seq=1) s USING(sql_id)
                    WHERE task_id=:tid
                    AND   EXECUTION_NAME=:nam
                    AND   (substr(:1,1,1)!='%' OR upper(sql_id||'/'||sqln||'/'||phv||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1)
                    ORDER BY sort_value DESC NULLS LAST
                ) WHERE ROWNUM<=50~','@ord@',ord) USING sq_nid,sq_txt,sown,snam,tid,nam,key,key,key;
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