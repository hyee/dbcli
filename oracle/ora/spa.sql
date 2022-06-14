/*[[
    Show SQL Performance Analyzer(SPA) info. Usage: @@NAME [-f"<filter>" | {<task_id> [<execution_id> [<keyword>|-improve|R]]}]
    @@NAME                            : show all SPA tasks
    @@NAME -f"<filter>"               : filter on dba_advisor_tasks
    @@NAME <task_id>                  : show details of target task
    @@NAME <task_id> <execution_id>   : show details of target executions 
                         <keyword>           plus filtering with possible keyword
                         -diff               order by abs(diff)
                         -regress            order by regression
                         -improve            order by improvement
    @@NAME <task_id> <execution_id> R : generate report text for target comparison analysis report

    --[[--
        &filter: default={1=1}, f={}
        @ver   : 18.1={} default={--}
        &ord1  : default={"Weight"} diff={greatest(diff,1/nullif(diff,0))} regress={diff} improve={1/nullif(diff,0)}
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
    c1     SYS_REFCURSOR;
    c2     SYS_REFCURSOR;
    rs     CLOB;
    tid    INT := regexp_substr(:v1, '^\d+$');
    eid    INT := regexp_substr(:v2, '^\d+$');
    fname  VARCHAR2(30) :='spa.txt';
    frs    CLOB;
    typ    VARCHAR2(30);
    ord    VARCHAR2(300);
    tsk    VARCHAR2(128);
    own    VARCHAR2(128);
    nam    VARCHAR2(128);
    pre    VARCHAR2(128);
    post   VARCHAR2(128);
    snam   VARCHAR2(128);
    sown   VARCHAR2(128);
    key    VARCHAR2(2000):=upper(:v3);
    m1     VARCHAR2(300);
    m2     VARCHAR2(300);
    fil    VARCHAR2(4000);
    sq_id  VARCHAR2(30);
    sq_txt VARCHAR2(400);
    sq_nid VARCHAR2(30);
    dyn_lvl    PLS_INTEGER;
    PROCEDURE report_start IS
    BEGIN
        IF dyn_lvl IS NULL THEN
            SELECT value into dyn_lvl from v$parameter where name='optimizer_dynamic_sampling';
        END IF;
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling=5';
        END IF;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF dyn_lvl != 5 THEN
            EXECUTE IMMEDIATE 'alter session set optimizer_dynamic_sampling='||dyn_lvl;
        END IF;
    END;
BEGIN
    SELECT MAX(task_name),max(owner),nvl(max(task_id),tid)
    INTO   tsk,own,tid
    FROM   dba_advisor_tasks
    WHERE  (task_id=tid OR upper(task_name)=upper(:V1))
    AND    advisor_name LIKE 'SQL Performance%';

    IF tid IS NOT NULL AND tsk IS NULL THEN
        raise_application_error(-20001,'Target task id is not a valid SPA task!');
    ELSIF tsk IS NOT NULL THEN
        SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ 
               MAX(attr3),MAX(attr1),nvl(MAX(fil),'1=1'),max(sq_id)，max(sq_nid),max(sq_txt)
        INTO   sown,snam,fil,sq_id,sq_nid,sq_txt
        FROM (
            SELECT decode(type,'SQLSET',attr3) attr3,
                   decode(type,'SQLSET',attr1) attr1,
                   null fil,
                   decode(type,'SQL',attr1) sq_id,
                   decode(type,'SQL',attr17) sq_nid,
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
                     (SELECT decode(T,'SQL',attr1||' -> '|| nvl(attr17,attr3),nullif(attr3||'.'||attr1,'.')) FROM 
                         (SELECT TYPE t,attr3,attr1,attr17
                          FROM   dba_advisor_objects b
                          WHERE  task_id = a.task_id
                          AND    EXECUTION_NAME IS NULL
                          AND    TYPE IN('SQLSET','SQL')
                          UNION ALL 
                          SELECT 'SQLSET',
                                 MAX(DECODE(parameter_name, 'SQLSET_OWNER', parameter_value)),
                                 MAX(DECODE(parameter_name, 'SQLSET_NAME', parameter_value)),
                                 ''
                          FROM   dba_advisor_parameters
                          WHERE  TASK_ID = a.task_id
                          AND    parameter_value!='UNUSED')
                     WHERE ROWNUM<2) SQLSET
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
        m1 := 'TASK PARAMETERS FOR '||own||'.'||tsk;
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

        m2 := 'EXECUTIONS FOR '||own||'.'||tsk;
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
    ELSE
        key := CASE WHEN key IS NULL THEN '%' WHEN KEY='R' THEN NULL ELSE '%'||key||'%' END;

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

        m1 := 'PARAMETERS FOR TASK PARAMETER '||own||'.'||tsk|| ' -> '||nam;
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
                           coalesce(pre.attr17,sq_nid,attr1) prev_sql,
                           nvl(p1.phv,''||f.attr5) prev_phv,
                           coalesce(post.attr17,sq_nid,attr1) post_sql,
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
                    LEFT JOIN (SELECT * FROM R WHERE EXECUTION_NAME=pre) PRE USING(ATTR1)
                    LEFT JOIN (SELECT * FROM R WHERE EXECUTION_NAME=post) POST USING(ATTR1)
                    LEFT JOIN (SELECT * FROM S WHERE EXECUTION_NAME=pre) p1 USING(ATTR1)
                    LEFT JOIN (SELECT * FROM S WHERE EXECUTION_NAME=post) p2 USING(ATTR1)
                    LEFT JOIN (SELECT /*+no_merge*/ DISTINCT
                                     sql_id attr1,
                                     trim(regexp_replace(to_char(substr(sql_text,1,2500)),'\s+',' ')) sql_text
                               FROM  DBA_SQLSET_STATEMENTS 
                               WHERE sqlset_owner=sown
                               AND   sqlset_name=snam) s USING(attr1)
                    WHERE key IS NULL 
                    OR    upper(attr1||'~'||pre.attr17||'~'||post.attr17||
                                f.attr5||'~'||p1.phv||'~'||p2.phv||'~'||sql_text)
                    LIKE  key
                    ORDER BY &ord1 DESC NULLS LAST)
                SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/ * FROM F WHERE ROWNUM<=50;
        ELSIF typ like 'CONVERT%' THEN
            OPEN c2 FOR replace(q'~
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
                    AND   (:1 is null OR upper(sql_id||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1)~'
                    ||' AND ('||fil||')
                    ORDER BY sort_value DESC NULLS LAST
                ) WHERE ROWNUM<=50','@ord@',ord) USING sown,snam,key,key,key;
        ELSE
            ord := CASE WHEN typ like 'EXPLAIN%' THEN 'ela' ELSE ord end;
            OPEN c2 FOR replace(q'~
                SELECT * FROM (
                    SELECT /*+no_expand opt_param('optimizer_dynamic_sampling' 5)*/ 
                         round(ratio_to_report(@ord@) over(),4) "Weight",
                         sql_id org_sql_id,
                         phv org_plan,
                         coalesce(attr17,:sq_id,sql_id) act_sql_id,
                         plan_hash_value plan_hash,
                         '|' "|",
                         @ord@ sort_value,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',execs,executions) execs,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela,elapsed_time) ela,
                         decode(EXECUTION_TYPE,'EXPLAIN PLAN',ela/nullif(execs,0),elapsed_time/nullif(executions,0)) avg_ela,
                         round(decode(EXECUTION_TYPE,'EXPLAIN PLAN',cpu/nullif(ela,0),cpu_time/nullif(elapsed_time,0)),4) cpu,
                         '|' "*",
                         nvl(:sq_txt,trim(regexp_replace(to_char(substr(sql_text,1,200)),'\s+',' '))) sql_text
                    FROM  (select a.*,attr1 sql_id FROM DBA_ADVISOR_OBJECTS A) A
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
                    WHERE task_id=:x
                    AND   EXECUTION_NAME=:y
                    AND   (:1 is null OR upper(sql_id||'/'||attr17||'/'||phv||'/'||plan_hash_value) like :1 OR upper(sql_text) like :1)
                    ORDER BY sort_value DESC NULLS LAST
                ) WHERE ROWNUM<=50~','@ord@',ord) USING sq_nid,sq_txt,sown,snam,tid,nam,key,key,key;
        END IF;

        IF KEY IS NULL THEN
            fname := 'spa_'||tid||'_'||eid||'.';
            report_start;
            IF DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.RELEASE>13 THEN
                fname := fname ||'html';
                EXECUTE IMMEDIATE 'BEGIN :rs :=sys.DBMS_SQLPA.REPORT_ANALYSIS_TASK(task_name=>:1,task_owner=>:2,section=>''ALL'',level=>''ALL'',type=>''HTML'');END;' 
                    USING OUT frs,tsk,own;
            ELSE
                fname := fname ||'txt';
                EXECUTE IMMEDIATE 'BEGIN :rs :=sys.DBMS_SQLPA.REPORT_ANALYSIS_TASK(task_name=>:1,task_owner=>:2,section=>''ALL'',level=>''ALL'');END;' 
                    USING OUT frs,tsk,own;
            END IF;
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