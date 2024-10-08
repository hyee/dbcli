/*[[Show resource manager plan and generate the relative SQL scripts. Usage: @@NAME [plan_name|schema_name] [-u]
   -u: When generate the SQL script, use update_xxxx instead of create_xxxx

   Sample Output:
   ==============
   --[[
       @ALIAS: rsrc
       @ver1: 11.2={MGMT_} default={CPU}
       @ver2: 12.1={PARALLEL_SERVER_LIMIT} default={PARALLEL_TARGET_PERCENTAGE}
       @ver4: 12.1={} default={--}
       @con : 12.1={con_id,} default={}
       @ver5: {
            12.1={con_id,decode(con_id,1,'CDB$ROOT',(select name from v$pdbs where con_id=a.con_id and rownum<2)) Container,
                  NAME PLAN,IS_TOP_PLAN IS_TOP, CPU_MANAGED CPU, INSTANCE_CAGING CAGING, PARALLEL_SERVER_LIMIT/100 PX_LIMIT,
                  PARALLEL_SERVERS_ACTIVE PX_ACTIVE,PARALLEL_SERVERS_TOTAL PX_TOTAL,PARALLEL_EXECUTION_MANAGED PX_CTRL, 
                  DIRECTIVE_TYPE DX,SHARES,UTILIZATION_LIMIT/100 max_ut, MEMORY_MIN/100  MEM_MIN, MEMORY_LIMIT/100 MEM_LIMIT,PROFILE}
            default={*}
       }           
       &method: default={create_} u={update_}
       &place:  default={} u={new_}
       @check_access_adb: {
            SYS.CS_RESOURCE_MANAGER={[[SELECT /*grid={topic="CS_RESOURCE_MANAGER.LIST_CURRENT_RULES()"}*/ 
                CONSUMER_GROUP,
                ELAPSED_TIME_LIMIT ELAPSED_LIMIT, 
                IO_MEGABYTES_LIMIT IO_MB_LIMIT, 
                SHARES,
                CONCURRENCY_LIMIT CONCURRENCY,
                DEGREE_OF_PARALLELISM DOP 
            FROM SYS.CS_RESOURCE_MANAGER.LIST_CURRENT_RULES()]],'|',}
             
            default={}
        }
        @check_access_cdb_rsrc: dba_cdb_rsrc_plans={1} default={0}
        @check_access_cdb_plan: {
            dba_cdb_rsrc_plans={'-',[[/*grid={topic="dba_cdb_rsrc_plans",autohide='on'}*/
            select a.* 
            from dba_cdb_rsrc_plans a, (select name from v$rsrc_plan) b 
            where a.plan=b.name(+) order by nvl2(b.name,1,2),a.plan]],}  
            default={}
        }
        @check_access_cdb_dir: {
            dba_cdb_rsrc_plans={,'-',[[/*grid={topic="dba_cdb_rsrc_plan_directives",autohide='on'}*/
            select nvl2(a.name,'$GREPCOLOR$','')||PLAN plan,
                   NVL(PLUGGABLE_DATABASE,PROFILE) PDB_OR_PROFILE,
                   DIRECTIVE_TYPE,
                   SHARES,
                   UTILIZATION_LIMIT/100 MAX_UT,
                   PARALLEL_SERVER_LIMIT/100 PX_LIMIT,
                   MEMORY_MIN/100 MEM_MIN,
                   MEMORY_LIMIT/100 MEM_LIMIT,
                   STATUS,MANDATORY,COMMENTS
            from (select name from v$rsrc_plan) a,
                  dba_cdb_rsrc_plan_directives b
            where  b.plan=a.name(+)
            ORDER  by nvl2(a.name,1,2),1,2]]}  
            default={}
        }
}
   ]]--
]]*/
set feed off verify off autohide col

col timeout,max_ela,max_idle,max_blkr,CALL_TIME,ALL_TIME for smhd1
col IO_REQs,LIO_req format tmb
col IO_MB format kmg
col CPU_TIME,CPU_WAIT,QUEUED_TM,ACT_TM for usmhd1
col PX_LIMIT,max_ut,MEM_MIN,MEM_LIMIT for pct1
grid {
    [[/*grid={topic="dba_rsrc_plans",autohide='on'}*/ select a.* from dba_rsrc_plans a, (select name from v$rsrc_plan) b where a.plan=b.name(+) order by nvl2(b.name,1,2),a.plan]],
    &check_access_cdb_plan
    '-',
    {
        [[/*grid={topic="dba_rsrc_group_mappings"}*/ select * from dba_rsrc_group_mappings]],
        '|',
        [[/*grid={topic="dba_rsrc_consumer_group_privs"}*/ select * from dba_rsrc_consumer_group_privs]],
        '|',
        [[/*grid={topic="dba_rsrc_manager_system_privs"}*/ select * from dba_rsrc_manager_system_privs]]
    },
    '-',
    [[/*grid={topic="dba_rsrc_plan_directives",autohide='on'}*/ 
      select nvl2(a.name,'$GREPCOLOR$','')||PLAN plan,
             GROUP_OR_SUBPLAN,TYPE,&ver1.p1 p1,&ver1.p2 p2,&ver1.p3 p3,&ver1.p4 p4,&ver1.p5 p5,&ver1.p6 p6,&ver1.p7 p7,&ver1.p8 p8,
             '|' "|",ACTIVE_SESS_POOL_P1 sess,QUEUEING_P1 timeout,
             '|' "|",&ver2 max_px,PARALLEL_DEGREE_LIMIT_P1 max_dop,PARALLEL_QUEUE_TIMEOUT TIMEOUT,
             &ver4 PARALLEL_STMT_CRITICAL critical,
             '|' "|",MAX_EST_EXEC_TIME max_ela,undo_pool undo,MAX_IDLE_TIME max_idle,MAX_IDLE_BLOCKER_TIME max_blkr,
             &ver4 '|' "|",UTILIZATION_LIMIT/100 MAX_UT,
             '|' "|",SWITCH_GROUP SWITCH_TO, SWITCH_FOR_CALL FOR_CALL,SWITCH_TIME CALL_TIME,
             &ver4 SWITCH_ELAPSED_TIME ALL_TIME,
             SWITCH_IO_MEGABYTES*1024*1024 IO_MB, 
             SWITCH_IO_REQS IO_REQs
             &ver4 ,SWITCH_IO_LOGICAL LIO_req
             ,b.status
      FROM   (select name from v$rsrc_plan) a,dba_rsrc_plan_directives b
      where  b.plan=a.name(+)
      ORDER  by nvl2(a.name,1,2),1,2]]
    &check_access_cdb_dir
};


grid {
&check_access_adb
[[/*grid={topic="V$RSRC_PLANS"}*/ select &ver5 from v$rsrc_plan a ORDER BY 1,2]]
}

PRO
PRO V$RSRC_CONSUMER_GROUP
PRO =======================
SELECT &con REPLACE(NAME,'_ORACLE_BACKGROUND_GROUP_','BACKGROUND@') RSRC_GROUP,ACTIVE_SESSIONS ACT_SSS, EXECUTION_WAITERS WAITERS,
       REQUESTS REQS,QUEUE_LENGTH QUEUES,QUEUED_TIME QUEUED_TM,ACTIVE_SESSIONS_KILLED ACT_KILLS,
       IDLE_SESSIONS_KILLED IDLE_KILLS,IDLE_BLKR_SESSIONS_KILLED BLKR_KILLS,
       '|' "|",
       CONSUMED_CPU_TIME CPU_TIME,CPU_WAIT_TIME CPU_WAIT,CPU_WAITs WAITS, YIELDS ,
       CPU_DECISIONS DECISIONS,CPU_DECISIONS_EXCLUSIVE EXCLUDES, CPU_DECISIONS_WON WONS,
       '|' "|",
       CURRENT_PQS_ACTIVE PX_ACT_STMT,CURRENT_PQ_SERVERS_ACTIVE ACT_SVRS,PQ_ACTIVE_TIME ACT_TM,PQ_SERVERS_USED USED,
       PQS_QUEUED QUEUED,PQ_QUEUED_TIME QUEUED_TM,PQS_COMPLETED COMPLETED
FROM v$rsrc_consumer_group
ORDER BY 1,2,3;

var output clob;
var fname  VARCHAR2(128);
DECLARE
    v_plan VARCHAR2(128) := :V1;
    output CLOB;
    --Doc ID 1388634.1
    PROCEDURE get_plan_v2(A_PLAN_NAME IN VARCHAR2, output OUT CLOB) IS
        method  VARCHAR2(30) := '&method';
        v_plan  VARCHAR2(128) := UPPER(A_PLAN_NAME);
        v_stmt  VARCHAR2(32767) := '';
        v_ver   NUMBER := 0;
        v_val   VARCHAR2(500);
        v_xml   XMLTYPE;
        v_field VARCHAR2(128);
        t       BINARY_INTEGER := 1;
        TYPE list_tab IS TABLE OF VARCHAR2(2000) INDEX BY BINARY_INTEGER;
        plan_list     list_tab;
        plan_man      list_tab;
        cons_grp_list list_tab;
        cons_man      list_tab;
        fields        list_tab;
        dtypes        list_tab;
        descs         list_tab;
        is_cdb        BOOLEAN:=FALSE;
        CURSOR c_cons_grp IS
            WITH plans AS (SELECT PLAN, group_or_subplan FROM DBA_RSRC_PLAN_DIRECTIVES WHERE upper(plan) = v_plan)
            SELECT group_or_subplan, TYPE, b.MANDATORY cons_man, c.MANDATORY plan_man
            FROM   DBA_RSRC_PLAN_DIRECTIVES A
            LEFT   JOIN dba_rsrc_consumer_groups b
            ON     (a.group_or_subplan = b.CONSUMER_GROUP)
            LEFT   JOIN dba_rsrc_plans c
            ON     (a.group_or_subplan = c.plan)
            WHERE  a.PLAN IN (SELECT PLAN FROM plans UNION SELECT group_or_subplan FROM plans)
            AND    NVL(A.STATUS, ' ') != 'PENDING'
            AND    NVL(B.STATUS, ' ') != 'PENDING'
            AND    NVL(C.STATUS, ' ') != 'PENDING'
            ORDER  BY 1;
    
        CURSOR c_cons_grp_map(V_CONS_GRP IN VARCHAR2) IS
            SELECT attribute, VALUE
            FROM   DBA_RSRC_GROUP_MAPPINGS
            WHERE  consumer_group = V_CONS_GRP
            AND    NVL(STATUS, ' ') != 'PENDING';
        CURSOR c_cons_grp_privs(V_CONS_GRP IN VARCHAR2) IS
            SELECT grantee,
                   CASE WHEN grant_option = 'YES' THEN 'TRUE' ELSE 'FALSE' END grant_option
            FROM   DBA_RSRC_CONSUMER_GROUP_PRIVS
            WHERE  granted_group = V_CONS_GRP;
    
        PROCEDURE wr(msg VARCHAR2, proc VARCHAR2 := '0') IS
            v_padding VARCHAR2(100) := chr(10) || lpad(' ', LENGTH(proc) + 5, ' ');
            v_msg VARCHAR2(32767) := CASE
                                         WHEN proc IS NOT NULL THEN
                                          '    '
                                     END || REPLACE(msg, CHR(10), v_padding) || CHR(10);
        BEGIN
            dbms_lob.writeappend(output, LENGTH(v_msg), v_msg);
        END;

        FUNCTION trans(plan VARCHAR2) RETURN VARCHAR2 is
        BEGIN
            RETURN case when upper(plan)=v_plan then 'v_plan' else ''''||plan||'''' end;
        END;
    BEGIN
        SELECT to_number(substr(version, 1, 2)) INTO v_ver FROM v$instance;
    
        IF v_ver < 11 THEN
            raise_application_error(-20001, 'Please use the correct version-script');
        END IF;
    
        DBMS_LOB.CREATETEMPORARY(output, TRUE);
    
        -- Build lists with related plans and consumer groups...
        plan_list(1) := v_plan;
        plan_man(1)  := 'NO';
        FOR i IN 1 .. plan_list.COUNT LOOP
            FOR r_cons_grp IN c_cons_grp LOOP
                IF r_cons_grp.type = 'CONSUMER_GROUP' THEN
                    cons_grp_list(cons_grp_list.count+1) := r_cons_grp.group_or_subplan;
                    cons_man(cons_man.count+1) := r_cons_grp.cons_man;
                    t := t + 1;
                ELSIF r_cons_grp.type = 'PLAN' THEN
                    plan_list(plan_list.count+1) := r_cons_grp.group_or_subplan;
                    plan_man(plan_man.count+1)   := r_cons_grp.plan_man;
                END IF;
            END LOOP;
        END LOOP;
        IF cons_grp_list.count=0 THEN
            $IF &check_access_cdb_rsrc=1 $THEN
                SELECT COUNT(1) 
                INTO   v_ver
                FROM   dba_cdb_rsrc_plans
                WHERE  upper(plan)=v_plan; 
                IF v_ver>0 THEN
                    is_cdb := TRUE;
                END IF;
            $END
            IF NOT is_cdb THEN 
                raise_application_error(-20001,'No such Resource Manager Plan: '||A_PLAN_NAME);
            END IF;
        END IF;

        wr('declare', '');
        wr('v_plan varchar2(128);');
        wr('begin', '');
        wr('--clear pending area, if trigger ORA-29370 then query gv$lock.type=''KM'' and then kill relative sessions');
        wr('dbms_resource_manager.clear_pending_area;');
        wr('dbms_resource_manager.create_pending_area;');
        wr('v_plan :=''' || v_plan || ''';');

        IF is_cdb THEN   
        $IF &check_access_cdb_rsrc=1 $THEN
            FOR r IN(select * from dba_cdb_rsrc_plans where upper(plan)=v_plan and nvl(status,' ')!='PENDING') LOOP
                IF r.mandatory = 'YES' THEN
                    wr('/* -- This is an Oracle mandatory plan');
                END IF;
                IF method != 'update_' THEN
                     wr('BEGIN dbms_resource_manager.delete_cdb_plan(plan => v_plan); EXCEPTION WHEN OTHERS THEN NULL;END;');
                END IF;
                wr('dbms_resource_manager.&method.cdb_plan(plan => v_plan,&place.comment=>q''['||r.comments||']'');');
                IF r.mandatory = 'YES' THEN
                    wr('*/');
                END IF;
            END LOOP;
            FOR r IN(select * from dba_cdb_rsrc_plan_directives where upper(plan)=v_plan and nvl(status,' ')!='PENDING') LOOP
                IF r.mandatory = 'YES' AND method != 'update_' THEN
                    wr('/* -- This is an Oracle mandatory plan directive');
                END IF;
                
                IF method = 'update_' AND r.directive_type='AUTOTASK' THEN
                    v_stmt := 'dbms_resource_manager.update_cdb_autotask_directive('||chr(10);
                ELSIF method = 'update_' AND r.directive_type='DEFAULT_DIRECTIVE' THEN
                    v_stmt := 'dbms_resource_manager.update_cdb_default_directive('||chr(10);
                ELSIF r.pluggable_database IS NOT NULL  THEN
                    v_stmt := 'dbms_resource_manager.&method.cdb_plan_directive('||chr(10);
                    v_stmt := v_stmt ||'pluggable_database     => '''||r.pluggable_database||''','||chr(10);
                ELSE
                    v_stmt := 'dbms_resource_manager.&method.cdb_profile_directive('||chr(10);
                    v_stmt := v_stmt ||'profile                => '''||r.profile||''','||chr(10);
                END IF;
                v_stmt := v_stmt ||'plan                   => v_plan,'||chr(10);
                v_stmt := v_stmt ||'&place.comment                => q''['||r.comments||']'','||chr(10);
                v_stmt := v_stmt ||'&place.shares                 => '||nvl(''||r.shares,'null')||','||chr(10);
                v_stmt := v_stmt ||'&place.utilization_limit      => '||nvl(''||r.utilization_limit,'null')||','||chr(10);
                v_stmt := v_stmt ||'&place.parallel_server_limit  => '||nvl(''||r.parallel_server_limit,'null')||','||chr(10);
                v_stmt := v_stmt ||'&place.memory_min             => '||nvl(''||r.memory_min,'null')||','||chr(10);
                v_stmt := v_stmt ||'&place.memory_limit           => '||nvl(''||r.memory_limit,'null')||');';
                wr(v_stmt);
                IF r.mandatory = 'YES' AND method != 'update_' THEN
                    wr('*/');
                END IF;
            END LOOP;
            is_cdb := TRUE;
        $ELSE
            NULL;
        $END
        ELSE
            IF method != 'update_' THEN
                for i in 1..plan_list.count loop
                    wr(case when plan_man(i)='YES' then '--' end || 'BEGIN dbms_resource_manager.delete_plan_cascade(plan => '||trans(plan_list(i))||'); EXCEPTION WHEN OTHERS THEN NULL;END;');
                    wr(case when plan_man(i)='YES' then '--' end || 'BEGIN dbms_resource_manager.delete_plan(plan => '||trans(plan_list(i))||'); EXCEPTION WHEN OTHERS THEN NULL;END;');
                end loop;
            END IF;
        
            wr('');
            wr('--Create consumer groups');
            FOR i IN 1 .. cons_grp_list.COUNT LOOP
                IF cons_man(i) = 'YES' THEN
                    wr('/* -- This is an Oracle mandatory consumer group');
                END IF;
                
                IF method != 'update_' THEN
                    wr('BEGIN dbms_resource_manager.delete_consumer_group(''' || cons_grp_list(i) || ''');EXCEPTION WHEN OTHERS THEN NULL;END;');
                END IF;
            
                SELECT 'dbms_resource_manager.&method.consumer_group(consumer_group=>''' || cons_grp_list(i) || ''',' || chr(10) || '&place.comment=>''' ||
                       comments || ''',' || chr(10) || '&place.cpu_mth=>''' || cpu_method || ''',' || chr(10) || '&place.mgmt_mth=>''' || mgmt_method ||
                       ''',' || chr(10) || '&place.category=>''' || category || ''');'
                INTO   v_stmt
                FROM   DBA_RSRC_CONSUMER_GROUPS
                WHERE  consumer_group = cons_grp_list(i)
                AND    NVL(STATUS, ' ') != 'PENDING';
            
                wr(v_stmt, 'dbms_resource_manager.create_consumer_group');
                IF cons_man(i) = 'YES' THEN
                    wr('*/');
                END IF;
            END LOOP;
        
            -- Consumer group mappings
            wr('');
            wr('--Create consumer group mappings');
            FOR i IN 1 .. cons_grp_list.COUNT LOOP
                FOR r_cons_grp_map IN c_cons_grp_map(cons_grp_list(i)) LOOP
                    wr('dbms_resource_manager.set_consumer_group_mapping (ATTRIBUTE=>''' || r_cons_grp_map.attribute || ''', VALUE=>''' ||
                       r_cons_grp_map.value || ''', CONSUMER_GROUP=>''' || cons_grp_list(i) || ''');');
                END LOOP;
            END LOOP;
        
            -- consumer group privileges
            wr('');
            wr('--Create consumer group privileges');
            FOR i IN 1 .. cons_grp_list.COUNT LOOP
                FOR r_cons_grp_privs IN c_cons_grp_privs(cons_grp_list(i)) LOOP
                    wr('dbms_resource_manager_privs.grant_switch_consumer_group (GRANTEE_NAME=>''' || r_cons_grp_privs.grantee ||
                       ''', CONSUMER_GROUP=>''' || cons_grp_list(i) || ''', GRANT_OPTION=> ' || r_cons_grp_privs.grant_option || ');');
                END LOOP;
            END LOOP;
        
            -- CREATE_PLAN statements...
            wr('');
            wr('--Create RSRC plan');
            FOR i IN 1 .. plan_list.COUNT LOOP
                v_field := trans(plan_list(i));
                SELECT 'dbms_resource_manager.&method.plan(plan=>' || v_field || ',' || chr(10) || '&place.comment=>''' || comments || ''',' || chr(10) || '&place.cpu_mth=>''' || cpu_method || ''',' ||
                       chr(10) || '&place.active_sess_pool_mth=>''' || active_sess_pool_mth || ''',' || chr(10) || '&place.parallel_degree_limit_mth=>''' ||
                       parallel_degree_limit_mth || ''',' || chr(10) || '&place.queueing_mth=>''' || queueing_mth || ''',' || chr(10) ||
                       '&place.mgmt_mth=>''' || mgmt_method || ''');',
                       mandatory
                INTO   v_stmt, plan_man(i)
                FROM   DBA_RSRC_PLANS
                WHERE  plan = plan_list(i)
                AND    NVL(STATUS, ' ') != 'PENDING';
                IF plan_man(i) = 'YES' THEN
                    wr('/* -- This is an Oracle mandatory plan');
                END IF;
                wr(v_stmt, 'dbms_resource_manager.&method.plan');
                IF plan_man(i) = 'YES' THEN
                    wr('*/');
                END IF;
            END LOOP;
        
            -- CREATE_PLAN_DIRECTIVE statements
            SELECT rpad(argument_name, l), data_type, regexp_replace(comments, '[[:space:][:cntrl:]]+', ' ')
            BULK   COLLECT
            INTO   fields, dtypes, descs
            FROM   (SELECT a.*, MAX(LENGTH(argument_name)) OVER() l
                    FROM   dba_arguments a
                    WHERE  object_name = 'CREATE_PLAN_DIRECTIVE'
                    AND    package_name = 'DBMS_RESOURCE_MANAGER'
                    AND    argument_name IN (SELECT column_name FROM dba_Tab_cols WHERE table_name = 'DBA_RSRC_PLAN_DIRECTIVES')
                    AND    position > 1) a
            LEFT   JOIN (SELECT * FROM dba_col_comments WHERE table_name = 'DBA_RSRC_PLAN_DIRECTIVES') b
            ON     (a.argument_name = b.column_name)
            WHERE  NVL(b.comments, ' ') NOT LIKE '%deprecated%'
            ORDER  BY position;

            IF fields.count = 0 THEN
                raise_application_error(-20001,'Wrong result in dba_arguments where object_name=CREATE_PLAN_DIRECTIVE.');
            END IF;
        
            wr('');
            wr('/* Create RSRC plan directives');
            wr('   Fields:');
            FOR i IN 1 .. fields.count LOOP
                wr('       ' || fields(i) || ': ' || descs(i));
                IF TRIM(fields(i)) = 'GROUP_OR_SUBPLAN' THEN
                    wr('       ' || RPAD('COMMENT', LENGTH(fields(i))) || ': Comment');
                END IF;
            END LOOP;
            wr('*/');
        
            FOR j IN 1 .. plan_list.count LOOP
                IF plan_man(j) = 'YES' THEN
                    wr('/* -- This is an Oracle mandatory plan directive');
                END IF;
                FOR r IN (SELECT /*+opt_param('cursor_sharing' 'force')*/ COLUMN_VALUE c
                          FROM   TABLE(XMLSEQUENCE(extract(dbms_xmlgen.getxmltype('select * from DBA_RSRC_PLAN_DIRECTIVES where upper(plan)=upper(''' ||
                                                                                   plan_list(j) || q'[') and NVL(STATUS,' ')!='PENDING']'),
                                                           '//ROW')))) LOOP
                    v_stmt := 'dbms_resource_manager.&method.plan_directive(' || RPAD('PLAN', length(fields(1))) || ' => ';
                    v_stmt := v_stmt || trans(plan_list(j));
                    FOR i IN 1 .. fields.count LOOP
                        v_field := fields(i);
                        <<ST>>
                    
                        v_xml := r.c.extract('//' || TRIM(v_field) || '/text()');
                        IF v_xml IS NOT NULL THEN
                            v_val := v_xml.getstringval();
                            IF dtypes(i) = 'VARCHAR2' THEN
                                v_val := '''' || v_val || '''';
                            ELSE
                                v_val := NVL(v_val, 'null');
                            END IF;
                            IF method = 'update_' AND TRIM(v_field) != 'GROUP_OR_SUBPLAN' THEN
                                v_field := 'NEW_' || v_field;
                            END IF;
                            v_stmt := v_stmt || ',' || CHR(10) || REPLACE(v_field, 'COMMENTS', 'COMMENT') || ' => ' || v_val;
                        END IF;
                        IF TRIM(v_field) = 'GROUP_OR_SUBPLAN' THEN
                            v_field := RPAD('COMMENTS', LENGTH(v_field));
                            GOTO st;
                        END IF;
                    
                    END LOOP;
                    wr(v_stmt || ');', 'dbms_resource_manager.&method.plan_directive');
                END LOOP;
                IF plan_man(j) = 'YES' THEN
                    wr('*/');
                END IF;
            END LOOP;
        END IF;
        wr('dbms_resource_manager.validate_pending_area;');
        wr('dbms_resource_manager.submit_pending_area;');
        wr('exception when others then', '');
        wr('if v_plan is not null then dbms_resource_manager.clear_pending_area;end if;');
        wr('raise;');
        wr('end;', '');
        wr('/', '');
    END;
BEGIN
    IF v_plan IS NULL THEN
        SELECT NAME
        INTO   v_plan
        FROM   v$rsrc_plan
        WHERE  IS_TOP_PLAN = 'TRUE'
        AND    rownum < 2;
    END IF;
    get_plan_v2(v_plan, output);
    :fname  := lower(v_plan);
    :output := output;
END;
/
save output rsrc_&fname..sql