/*[[
    Manage SQL Performance Analyzer(SPA). type 'help @@NAME' for more detail.
    Usages:
        @@NAME                                          : show all SPA tasks
        @@NAME -f"<filter>"                             : filter on dba_advisor_tasks
        @@NAME <task>                                   : show details of target task
        @@NAME -sql  <sql_id>                           : Show sql execution stats
        @@NAME -sign <sql_id>                           : Show sql execution stats relative to the same force_matching_signature
        @@NAME -plan <plan_hash_value>                  : Show sql execution stats relative to target plan hash value
        @@NAME <task> create <sqlset> [-f"<filter>"]    : create SPA task from sqlset
        @@NAME <task> alter <param_name> [<param_value>]: alter task parameter
        @@NAME <task> drop                              : drop SPA task
        @@NAME <task> stop   <ename>                    : stop  the running SPA execution
        @@NAME <task> pause  <ename>                    : pause therunning SPA execution
        @@NAME <task> resume <ename>            [-sync] : resume the paused SPA execution
        @@NAME <task> test [<ename>] [<degree>] [-sync] : run new execution task with specific concurrenct degree in async mode
        @@NAME <task> explain|xplan  [<ename>]  [-sync] : run new explain plan task in async mode
        @@NAME <task> diff <exec1> <exec2> [<ename>]    : run new compare task to compare 2 specific executions in async mode
                                                              <exec1>/<exec2>   : the pre/post execution names or IDs for the comparison
                                                              <ename>           : the new execution name for the task
                                                              -metric"<formula>": i.e, "disk_reads+buffer_get*3000", "buffer_gets"  
        @@NAME <task> <ename> [<parameters>]            : show details of target executions, following with below options:
                                                              -diff     : order by abs(diff)
                                                              -regress  : order by regression
                                                              -improve  : order by improvement
                                                              -phv      : group by plan_hash_value
                                                              -diffplan : only list the plan change cases
                                                            other parameters:
                                                              <keyword> : filter with specific keyword
                                                              error     : list execution errors
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
            weight={"Total|_Time"} 
            diff={"Total|_Time"*log(2,abs("Metric|Diff"))} 
            regress={sign(-"Metric|Diff")*"Total|Execs"*log(2,abs("Metric|Diff"))} 
            improve={sign("Metric|Diff")*"Total|Execs"*log(2,abs("Metric|Diff"))}
        }
        &rule     : default={1=1} regress={prev_metric*1.2 < post_metric} improve={post_metric*1.2 < prev_metric}
        &sq       : default={0} sql={1} plan={2} sign={3}
        &base     : default={lists} phv={plans}
        &diffplan : default={1=1} diffplan={prev_phv!=post_phv}
        &calc     : default={} metric={}
        &qb       : {
            default={
                SELECT attr1 sq,task_id tid,execution_name ename,object_id oid
                FROM   dba_advisor_objects
                WHERE  sid=1
                AND    attr1=sq
                AND    type='SQL'
                UNION
                SELECT sq,null,null,null FROM DUAL
                UNION
                SELECT attr1,task_id,execution_name,object_id
                FROM   dba_advisor_objects
                WHERE  sid=0
                AND    attr1 IS NOT NULL
                AND    &attr17=sq
                AND    type='SQL'}
            plan={
                SELECT attr1 sq,task_id tid,execution_name ename,object_id oid
                FROM   dba_advisor_objects
                WHERE  attr1 IS NOT NULL
                AND    type='SQL'
                AND    attr5=sq
                UNION
                SELECT sql_id sq,null,null,null
                FROM   dba_advisor_sqlstats
                WHERE  plan_hash_value=sq
            }
            sign={
                SELECT attr1 sq,task_id tid,execution_name ename,object_id oid
                FROM   dba_advisor_objects
                WHERE  sid=1
                AND    attr1=sq
                AND    type='SQL'
                UNION
                SELECT sq,null,null,null FROM DUAL
                UNION
                SELECT a.sql_id,null,null,null
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

set verify off feed off autohide col
col org_sql noprint
col weight,cpu,io for pct3
col ela,avg_ela,pre,post,prev_avg,post_avg,parse,avg|ela,avg1,avg2,src_ela,Prev|_Avg,Post|_Avg,Total|_Time for usmhd2
col metric,Prev|Metric,Post|Metric,Total|Execs,Metric|Diff,cost,diff,buffs,exec,avg|fetches,avg|rows#,avg|buffs,avg|reads,direct|writes,read|req,write|req for tmb2
col read|bytes,write|bytes,inter|bytes for kmg2
var m1 VARCHAR2(300)
var m2 VARCHAR2(300)
var c1 refcursor
var c2 refcursor
var fn VARCHAR2(30);
var fc CLOB;
var metric VARCHAR2(300)
var hide VARCHAR2(2);
DECLARE
    task  VARCHAR2(300) := :v1;
    ename VARCHAR2(300) := :v2;
BEGIN
    SELECT /*+no_merge outline_leaf leading(t tp e) use_nl(e)*/ 
           coalesce(max(nullif(ep.parameter_value,'UNUSED')),upper(max(nullif(tp.parameter_value,'UNUSED'))),'ELAPSED_TIME')
    INTO   :metric
    FROM   DBA_ADVISOR_TASKS t
    JOIN   DBA_ADVISOR_PARAMETERS tp
    ON     t.task_id=tp.task_id
    AND    t.owner=tp.owner
    AND    tp.parameter_name='COMPARISON_METRIC'
    LEFT   JOIN DBA_ADVISOR_EXECUTIONS e
    ON     t.task_id=e.task_id
    AND    t.owner=e.owner
    AND    upper(ename) IN (''||e.execution_id,upper(e.execution_name))
    LEFT   JOIN DBA_ADVISOR_EXEC_PARAMETERS ep
    ON     e.task_id=ep.task_id
    AND    e.owner=ep.owner
    AND    e.execution_name=ep.execution_name
    AND    ep.parameter_name='COMPARISON_METRIC'
    WHERE  upper(task) in(''||t.task_id,upper(t.task_name))
    AND    t.advisor_name='SQL Performance Analyzer';

    :hide := CASE WHEN upper(:metric)='ELAPSED_TIME' THEN '--' ELSE ' ' END;
END;
/
/*
    dba_advisor_objects for type='SQL':
        attr1 : original sql id, same to ADV_SQL_ID
        attr3 : owner
        attr5 : plan_hash_value of pre execution, for TEST EXECUTION, it's the phv from dba_sqlset_statements, for COMPARE performance it's the phv of the first execution set
        attr7 : object flags. 1:improve 2:regress 4:unchanged 8:xpldiff 16:error 32:skipped 64:pending 128:INFOFND 256:unsupported 512:timeout 1024:misssql 2048:newsql 4086:zerorows 8192:diffrows 
        attr8 : availble on COMPARE PERFORMNACE only, the avg metric value of the first set
                  for comparing EXPLAIN plan, it's the optimizer costs
                  otherwise it's the avg SQL execution metric such as elapsed_time based on the COMPARISON_METRIC parameter
        attr9 : availble on COMPARE PERFORMNACE only, the avg metric value of the second set
        attr10: availble on COMPARE PERFORMNACE only, SQL execution count
        attr11: condb_id
        attr16: parsing_schema_name
        attr17: avaible on TEST EXECUTE only, the actually SPA execution SQL id(contains "SQL Analyze(...)")
 */
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
    ename      VARCHAR2(128);
    pre        VARCHAR2(128);
    post       VARCHAR2(128);
    snam       VARCHAR2(128);
    sown       VARCHAR2(128);
    setid      INT;
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
    params     VARCHAR2(2000);
    stmt       VARCHAR2(30000);
    calc       VARCHAR2(2000);

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
        INTO   eid,ename,typ,estatus
        FROM   dba_advisor_executions
        WHERE  task_id=tid
        AND    (execution_id=regexp_substr(name,'^\d+$') or upper(execution_name)=upper(name));
        IF new_name or new_name IS NULL THEN
            raise_application_error(-20001,'Invalid new execution "'||ename||'('||eid||')" in task '||fulltask||', target name already exists.');
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
                SELECT /*+MATERIALIZE CARDINALITY(3)*/ *
                FROM (&qb)
            )
            SELECT /*+no_merge(s) merge(t) leading(s t.s) index_ss(t.s)*/
                   'SQLSET' SOURCE_TYPE,
                   SQLSET_OWNER||'.'||SQLSET_NAME SOURCE_NAME,
                   null "OBJ#",
                   SQL_ID ACT_SQL,
                   PLAN_HASH_VALUE PLAN_HASH,
                   OPTIMIZER_COST cost,
                   NULL PARSE,
                   EXECUTIONS EXEC,
                   ELAPSED_TIME ELA,
                   ROUND(CPU_TIME/NULLIF(ELAPSED_TIME,0),4) "CPU",
                   NULL IO,
                   NULL flags,
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
            FROM   (select distinct sq from s) s,dba_sqlset_statements t
            WHERE  sql_id = s.sq
            UNION ALL
            SELECT /*+outline_leaf merge(o) leading(s o.a) use_nl(o.a) no_merge(t) push_pred(t)*/
                   'SPA EXEC' SOURCE_TYPE,
                   o.TASK_ID||'->'||o.EXECUTION_NAME SOURCE_NAME,
                   o.object_id,
                   NVL(&ATTR17,SQL_ID),
                   PLAN_HASH_VALUE PLAN_HASH,
                   OPTIMIZER_COST,
                   PARSE_TIME PARSE,
                   NVL(0+o.attr10,TESTEXEC_TOTAL_EXECS) EXEC,
                   ELAPSED_TIME*NVL(0+o.attr10,TESTEXEC_TOTAL_EXECS)/greatest(EXECUTIONS,1) ELA,
                   ROUND(CPU_TIME/NULLIF(ELAPSED_TIME,0),4) CPU,
                   ROUND(USER_IO_TIME/NULLIF(ELAPSED_TIME,0),4) IO,
                   (SELECT listagg(decode(bitand(o.attr7,power(2,rownum-1)),
                        1,'NONE',
                        2,'IMPROVE',
                        3,'REGRESS',
                        8,'XPLDIFF',
                        16,'ERROR',
                        32,'SKIPPED',
                        64,'PENDING',
                        128,'INFOFND', --such as adaptive plan
                        256,'UNSUPPORT',
                        512,'TIMEOUT',
                        1024,'MISSSQL',
                        2048,'NEWSQL',
                        4096,'ZEROROWS',
                        8192,'DIFFROWS',
                        16384,'ADAPXPL',
                        32768,'DIFFDATA',
                        65536,'MISEST', --misestimate
                        131072,'SPM_CAND', --SPM candidate
                        262144,'PASS_DML_CHECK',
                        524288,'FAIL_DML_CHECK',
                        1048576,'UNKNOWN_DML_COST'
                    ),',') WITHIN GROUP(order by 1) 
                    FROM dual connect by power(2,rownum-1)<=o.attr7) flags,
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
                   DBA_ADVISOR_OBJECTS  O,
                   DBA_ADVISOR_SQLSTATS T
            WHERE  o.type='SQL'
            AND    o.object_id=s.oid
            AND    o.task_id=s.tid
            AND    o.execution_name=s.ename
            AND    t.sql_id(+) = o.attr1
            AND    t.task_id(+)=o.task_id
            AND    t.execution_name(+)=o.execution_name
            AND    t.object_id(+)=o.object_id
            AND    t.sql_id(+)=o.attr1;
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
        dbms_sqlpa.set_analysis_task_parameter(tsk,'COMPARISON_METRIC','ELAPSED_TIME');
        GOTO END_BLOCK;
    ELSIF op = 'DROP' THEN
        sys.dbms_sqlpa.drop_analysis_task(tsk);
        dbms_output.put_line('SQL Performance Analyzer task is dropped: '||fulltask);
        GOTO END_BLOCK;
    ELSIF op = 'ALTER' THEN
        IF v3 IS NULL THEN
            dbms_output.put_line('Please specify the parameter name and value.');
        ELSE
            dbms_sqlpa.set_analysis_task_parameter(tsk,v3,v4);
            dbms_output.put_line('Parameter '||v3||' is set as '||v4||'.'||chr(10));
        END IF;
        GOTO END_BLOCK;
    ELSIF op in ('COMPARE','DIFF') THEN
        IF v3 IS NULL OR V4 IS NULL THEN
            raise_application_error(-20001,'Please specify the pre and post execution name for the comparison.');
        END IF;
        op     := 'COMPARE';
        check_exec(v3);
        sid    := eid;
        pre    := ename;
        check_exec(v4);
        post   := ename;
        ename    := 'DIFF_'||sid||'_'||eid;
        dop    := 1;
        check_exec(v5,NULL);

        calc  := nvl(trim('&calc'),trim('&metric'));

        SELECT nvl(MAX(decode(execution_type,'EXPLAIN PLAN','OPTIMIZER_COST')),calc)
        INTO   calc
        FROM   dba_advisor_executions
        WHERE  task_id=tid
        AND    execution_name in(pre,post);

        BEGIN
            EXECUTE IMMEDIATE '
                SELECT SUM('||CALC||')
                FROM   dba_sqlset_statements
                WHERE  rownum<1';
        EXCEPTION WHEN OTHERS THEN
            raise_application_error(-20001,'Invalid comparison metric formula: '||calc);
        END;
        ename := sys.dbms_sqlpa.execute_analysis_task(
            task_name       => tsk,
            execution_type  => op,
            execution_name  => v5,
            execution_params=> sys.dbms_advisor.arglist(
                'EXECUTION_NAME1', pre, 
                'EXECUTION_NAME2', post,
                'COMPARISON_METRIC',calc));
        check_exec(ename);
        key := 'HTML';
        dbms_output.put_line('Execution '||ename||'('||eid||') of task '||tsk||' is completed with metric "'||calc||'"');
        GOTO END_BLOCK;
    ELSIF op IN ('EXEC','EXECUTE','TEST','XPLAN','EXPLAIN') THEN
        check_exec(trim('.' from v3),null);
        dop := regexp_substr(v4,'^\d+$');
        SELECT 'dbms_advisor.arglist('||listagg(''''||n||''','''||v||'''',',') WITHIN GROUP(ORDER BY 1)||')'
        INTO   params
        FROM (
            SELECT parameter_name N,
                   decode(parameter_name,
                        'TEST_EXECUTE_DOP'，nvl(''||dop,parameter_value),
                        'LOCAL_TIME_LIMIT',replace(parameter_value,'UNUSED','1'),
                        parameter_value) V
            FROM   dba_advisor_parameters
            WHERE  task_id=tid
            AND    parameter_name in('TEST_EXECUTE_DOP','LOCAL_TIME_LIMIT','TIME_LIMIT')
        );
        IF op IN ('EXEC','EXECUTE','TEST') THEN
            op := 'EXECUTE';
        ELSIF op IN('XPLAN','EXPLAIN') THEN
            op := 'EXPLAIN';
        END IF;

        stmt := utl_lms.format_message(
                    q'~BEGIN sys.dbms_sqlpa.execute_analysis_task(task_name=>'%s',execution_type=>'%s',execution_name=>'%s',execution_params=>%s); END;~',
                    tsk,op,v3,params);
        IF &sync=1 THEN
            execute immediate stmt;
            dbms_output.put_line('Execution '||ename||' of task '||tsk||' is completed.');
        ELSE
            snam := dbms_scheduler.generate_job_name('SPA_EXEC_');
            dbms_scheduler.create_job(
                job_name   => snam,
                job_type   => 'PLSQL_BLOCK',
                job_action => stmt,
                enabled    => true);
            dbms_output.put_line('Execution '||ename||' of task '||tsk||' is running in background job '||snam);
        END IF;
        GOTO END_BLOCK;
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
            dbms_output.put_line('Execution '||ename||' of task '||tsk||' is running in background job '||snam);
        ELSE
            execute immediate stmt;
        END IF;
    ELSIF op IS NOT NULL AND eid IS NULL THEN
        check_exec(op);
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

        IF snam IS NOT NULL THEN
            SELECT max(id),max(owner),max(name)
            INTO   setid,sown,snam
            FROM (
                SELECT *
                FROM   dba_sqlset
                WHERE  upper(owner)=upper(sown)
                AND    upper(name)=(snam)
                ORDER  by instr(name,snam) desc,instr(owner,sown) desc
            )
            WHERE rownum<2;

            IF setid IS NULL THEN
                dbms_output.put_line('Cannot find SQLSET '||sown||'.'||snam);
            END IF;
        END IF;
    END IF;

    IF tid IS NULL THEN
        m1 := 'DBA_ADVISOR_TASKS WHERE ADVISOR_NAME=''SQL Performance Analyzer''';
        OPEN c1 FOR
            WITH r AS
             (SELECT /*+materialize opt_param('optimizer_dynamic_sampling' 5)*/ 
                     A.*, 
                     (SELECT COUNT(1) FROM dba_advisor_executions where task_id = a.task_id and owner=a.owner) execs,
                     (SELECT /*+no_unnest outline*/ COUNT(1) FROM dba_advisor_findings WHERE type='ERROR' AND task_id = a.task_id and owner=a.owner) errs,
                     (SELECT decode(MAX(y.type),
                                'SQL'   ,MAX(y.attr1||' -> '|| nvl(sqln,y.attr3)),
                                'SQLSET',MAX(nullif(y.attr3||'.'||y.attr1,'.')),
                                nullif(MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value)) ||
                                  '.'||MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)) ,'.'))
                      FROM  (SELECT * 
                             FROM   dba_advisor_parameters 
                             WHERE  parameter_name in('SQLSET_OWNER','SQLSET_NAME') 
                             AND    parameter_value!='UNUSED') x
                      FULL JOIN (
                             SELECT y.*,nvl(&attr17,attr1) sqln 
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
                   (select attr2 from dba_advisor_objects where task_id=tid and execution_name is null and type='SQLSET') "SQLSET|SQLs",
                   R.execs,
                   R.errs,
                   r.status,
                   r.execution_start,
                   (SELECT nvl(to_char(r.execution_end),
                                   decode(count(1),
                                       0,'Not Started',
                                       sum(sofar)||'/'||sum(totalwork)||' ('||round(sum(sofar)*100/greatest(sum(totalwork),1),2)||'%)'))
                    FROM   gv$advisor_progress a
                    WHERE  a.task_id=r.task_id
                    AND    start_time>=r.execution_start) "EXECUTION_END(PROG)",
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
                       (SELECT nvl(to_char(a.execution_end),
                                   CASE WHEN a.status='EXECUTING' THEN
                                       decode(count(1),
                                           0,'Not Started',
                                           sum(sofar)||'/'||sum(totalwork)||' ('||round(sum(sofar)*100/greatest(sum(totalwork),1),2)||'%)')
                                   END)
                        FROM   gv$advisor_progress r
                        WHERE  a.task_id=r.task_id
                        AND    r.start_time>=a.execution_start) "EXECUTION_END(PROG)",
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
                        WHERE type='ERROR' 
                        AND   task_id=tid
                        AND   owner=a.owner
                        AND   execution_name=a.execution_name) errs,
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
               :metric,
               MAX(b.EXECUTION_NAME),
               NULLIF(MAX(decode(parameter_name,'EXECUTION_NAME1',parameter_value)),'UNUSED'),
               NULLIF(MAX(decode(parameter_name,'EXECUTION_NAME2',parameter_value)),'UNUSED')
        INTO   typ,ord,ename,pre,post
        FROM   dba_advisor_exec_parameters A,DBA_ADVISOR_EXECUTIONS b
        WHERE  a.task_id = tid
        AND    b.task_id = tid
        AND    a.owner=b.owner
        AND    a.EXECUTION_NAME=b.EXECUTION_NAME
        AND    b.EXECUTION_ID=eid;

        IF post IS NULL THEN
            post := ename;
            pre  := 'CONVERT_SQLSET';
        END IF;

        m1 := 'PARAMETERS FOR TASK PARAMETER '||usr||'.'||tsk|| ' -> '||ename;
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
                         AND    EXECUTION_NAME=ename) b
            USING  (PARAMETER_NAME)
            ORDER  BY PARAMETER_NAME;

        m2 := 'TYPE: ['||typ||']      METRIC: [&metric]      TOP: [50]';
        IF key LIKE '%ERROR%' THEN
            OPEN c2 FOR
                SELECT max(cnt) errs,
                       trim(chr(10) from listagg(decode(mod(rnk,4),1,chr(10))||sql_id,',') within group(order by rnk)) sample_sqls,
                       message
                FROM (
                    SELECT /*+outline_leaf leading(f) push_pred(o)*/
                           trim(substr(f.message,1,256)) message,
                           count(1) over(partition by trim(substr(f.message,1,256))) cnt,
                           o.attr1 sql_id,
                           row_number() over(partition by trim(substr(f.message,1,256)) order by o.attr1 nulls last) rnk
                    FROM   dba_advisor_findings f,dba_advisor_objects o
                    WHERE  f.owner=o.owner(+)
                    AND    f.task_id=o.task_id(+)
                    AND    f.execution_name=o.execution_name(+)
                    AND    f.object_id=o.object_id(+)
                    AND    f.type='ERROR')
                WHERE rnk<=12
                GROUP BY message
                ORDER BY errs DESC;
        ELSIF typ like 'CONVERT%' THEN
            stmt := replace(replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand outline opt_param('optimizer_dynamic_sampling' 5) leading(a.f a.s a.p)*/ 
                         round(ratio_to_report(@ord@) over(),5) "Weight",
                         sql_id,
                         plan_hash_value plan_hash,
                         '|' "|",
                         &hide @ord@ metric,
                         executions execs,
                         elapsed_time ela,
                         elapsed_time/GREATEST(EXECUTIONS,1) avg_ela,
                         round(cpu_time/nullif(elapsed_time,0),4) cpu,
                         '|' "*",
                         trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' ')) sql_text
                    FROM  DBA_SQLSET_STATEMENTS a
                    WHERE sqlset_owner=:sown
                    AND   sqlset_name=:snam
                    AND   sqlset_id=:setid
                    AND   (substr(:1,1,1)!='%' OR upper(sql_id||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1) 
                    AND   (@filter@)
                    ORDER BY "Weight" DESC NULLS LAST
                ) WHERE ROWNUM<=50~','@ord@',ord),'@filter@',fil);
            --dbms_output.put_line(stmt);
            OPEN c2 FOR stmt USING sown,snam,setid,key,key,key;
        ELSE
            m2 := m2||'      PREV: ['||pre||']      POST: ['||post||']';
            OPEN c2 FOR
                WITH R AS(
                    SELECT rownum "#",a.*
                    FROM (
                        SELECT f.*,
                               &attr17 sql_nid,
                               attr5 prev_phv
                        FROM (
                            SELECT f.*,nullif(round(f.attr9/nullif(f.attr8,0),8),0) diff
                            FROM   dba_advisor_objects f
                            WHERE  TASK_ID = tid
                            AND    EXECUTION_NAME=ename
                            AND    TYPE='SQL'
                            AND    attr1 IS NOT NULL
                        ) f) a
                    WHERE rownum<=50
                ), detail AS(
                    SELECT /*+outline_leaf leading(f) use_hash(p1 p2 s)*/
                           attr1 org_sql,
                           coalesce(p1.sqln,decode(pre,'CONVERT_SQLSET',attr1),f.sql_nid,attr1) prev_sql,
                           coalesce(''||p1.phv,prev_phv) prev_phv,
                           coalesce(p2.sqln,decode(post,'CONVERT_SQLSET',attr1),f.sql_nid,attr1) post_sql,
                           coalesce(''||p2.phv,prev_phv) post_phv,
                           s.sign,
                           nvl(p2.parse_time,p1.parse_time) parse,
                           nullif(f.attr10,0) execs,
                           round(f.attr10*coalesce(p2.avg_ela,p1.avg_ela,s.avg_ela),2) ela,
                           nvl(p1.avg_ela,decode(pre,'CONVERT_SQLSET',s.avg_ela)) prev_avg,
                           nvl(p2.avg_ela,decode(post,'CONVERT_SQLSET',s.avg_ela)) post_avg,
                           nullif(coalesce(f.attr8,p1.metric,decode(pre,'CONVERT_SQLSET',s.metric)),0) prev_metric,
                           nullif(coalesce(f.attr9,p2.metric,decode(post,'CONVERT_SQLSET',s.metric)),0) post_metric
                    FROM r f
                    LEFT JOIN (SELECT /*+outline outline_leaf use_hash(s) use_hash(o)*/
                                      o.*,nvl(&attr17,o.attr1) sqln,
                                      plan_hash_value phv,
                                      s.parse_time,
                                      nullif(round(elapsed_time/greatest(executions,1),2),0) avg_ela,
                                      nullif(&metric,0) metric
                               FROM   dba_advisor_objects o,
                                      dba_advisor_sqlstats s
                               WHERE  o.TASK_ID = tid
                               AND    pre!='CONVERT_SQLSET'
                               AND    o.EXECUTION_NAME=pre
                               AND    o.type='SQL'
                               AND    s.TASK_ID(+) = tid
                               AND    s.EXECUTION_NAME(+)=pre
                               AND    o.object_id=s.object_id(+)
                               AND    o.attr1=s.sql_id(+)
                               ) p1 
                    USING(OWNER,ATTR1)
                    LEFT JOIN (SELECT /*+outline outline_leaf use_hash(s)  use_hash(o)*/
                                      o.*,nvl(&attr17,o.attr1) sqln,
                                      plan_hash_value phv,
                                      nullif(round(elapsed_time/greatest(executions,1),2),0) avg_ela,
                                      s.parse_time,
                                      nullif(&metric,0) metric
                               FROM   dba_advisor_objects o,
                                      dba_advisor_sqlstats s
                               WHERE  o.TASK_ID = tid
                               AND    post!='CONVERT_SQLSET'
                               AND    o.EXECUTION_NAME=post
                               AND    o.type='SQL'
                               AND    s.TASK_ID(+) = tid
                               AND    s.EXECUTION_NAME(+)=post
                               AND    o.object_id=s.object_id(+)
                               AND    o.attr1=s.sql_id(+)
                               ) p2 
                    USING(OWNER,ATTR1)
                    LEFT JOIN (SELECT --+outline leading(s.f s.s s.p) no_expand
                                     sql_id attr1,
                                     max(force_matching_signature) sign,
                                     nullif(SUM(&metric),0) metric,
                                     plan_hash_value prev_phv,
                                     SUM(elapsed_time) ela,
                                     nullif(round(SUM(elapsed_time)/greatest(SUM(executions),1),2),0) avg_ela,
                                     SUM(executions) execs,
                                     SUM(cpu_time) cpu
                               FROM  DBA_SQLSET_STATEMENTS s
                               WHERE sqlset_owner=sown
                               AND   sqlset_name=snam
                               AND   sqlset_id=setid
                               AND   ('CONVERT_SQLSET' IN (pre,post) OR '&metric'='OPTIMIZER_COST')
                               GROUP BY SQL_ID,plan_hash_value) s 
                    USING(attr1,prev_phv)
                    WHERE key IN('HTML','HTM','TEXT','ACTIVE')
                    OR    upper(attr1||','||f.sql_nid||','||p1.sqln||','||p2.sqln||','||prev_phv||','||f.attr5||','||p1.phv||','||p2.phv) LIKE key
                ), lists AS(
                    SELECT org_sql,
                           prev_sql,
                           prev_phv,
                           post_sql,
                           post_phv,
                           parse,
                           '|' "|",
                           execs "Total|Execs",
                           ela "Total|_Time",
                           prev_avg "Prev|_Avg",
                           post_avg "Post|_Avg",
                           &hide prev_metric "Prev|Metric",
                           &hide post_metric "Post|Metric",
                           round(greatest(post_metric/prev_metric,prev_metric/post_metric),8)*sign(prev_metric-post_metric) "Metric|Diff"
                    FROM   detail
                    WHERE (&rule)
                    AND   (&diffplan)
                ) , plans AS(
                    SELECT max(org_sql) keep(dense_rank last order by execs*prev_avg nulls last) org_sql,
                           count(distinct sign) signs,
                           count(distinct org_sql) sqls,
                           max(prev_sql) keep(dense_rank last order by execs*prev_avg nulls last) prev_top,
                           prev_phv,
                           max(post_sql) keep(dense_rank last order by execs*post_avg nulls last) post_top,
                           post_phv,
                           sum(parse) parse,
                           '|' "|",
                           sum(execs) "Total|Execs",
                           sum(ela)   "Total|_Time",
                           nullif(round(sum(execs*prev_avg)/sum(execs),2),0) "Prev|_Avg",
                           nullif(round(sum(execs*post_avg)/sum(execs),2),0) "Post|_Avg",
                           &hide nullif(round(sum(execs*prev_metric)/sum(execs),2),0) "Prev|Metric",
                           &hide nullif(round(sum(execs*post_metric)/sum(execs),2),0) "Post|Metric",
                           round(greatest(sum(execs*post_metric)/sum(execs*prev_metric),sum(execs*prev_metric)/sum(execs*post_metric)),8)
                            *sign(sum(execs*prev_metric)-sum(execs*post_metric)) "Metric|Diff"
                    FROM detail
                    WHERE (&rule)
                    AND   (&diffplan)
                    GROUP BY prev_phv,post_phv
                ) 
                SELECT /*+outline_leaf leading(a) use_nl(s) push_pred(s)*/
                       a.*,
                       '|' "|",
                       s.sql_text
                FROM (
                    SELECT RATIO_TO_REPORT(&ord1) OVER() "Weight",
                           a.*
                    FROM   &base a
                    ORDER  BY "Weight" DESC NULLS LAST
                ) a, (
                    SELECT sql_id org_sql,
                           max(trim(regexp_replace(to_char(substr(sql_text,1,2000)),'\s+',' '))) sql_text
                    FROM   dba_sqlset_statements s
                    WHERE  sqlset_owner=sown
                    AND    sqlset_name=snam
                    AND    sqlset_id=setid
                    GROUP  BY sql_id
                    ) s
                WHERE a.org_sql=s.org_sql
                AND   rownum <=50
                ORDER BY "Weight" DESC NULLS LAST;
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