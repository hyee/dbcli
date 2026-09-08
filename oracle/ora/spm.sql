/*[[
    View/Create/Modify SQL Profile/Patch/SPM. Usage: @@NAME [sql|load|drop|enable|disable|fix|unfix <keyword> [<phv>]] | [<keyword>|-f"<filter>"]
        * List existing SPMs: @@NAME [<keyword>|<sql_id> [<plan_hash>]|-f"<filter>"]
        * Load SPM from cursor/awr/sqlset: @@NAME load <sql_id> [<new_sql_id>|<plan_hash>]
        * View SQL Id: @@NAME sql <sql_handle>|<plan_name>|<signature>
        * View the envolve detail of an existing SPM: @@NAME view <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]}
        * View the execution plan of an existing SPM: @@NAME <sql_handle>|<plan_name> [<plan_hash]>
        * Change category of SQL Profile/Patch: @@NAME CATEGORY <name> <category>
        * Accept an existing SPM without running the envolve task to verify the performance: @@NAME accept <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]}
        * Envolve an existing SPM: @@NAME envolve <sql_handle>|<plan_name>|<signature>|<sql_id> [<plan_hash>|<seconds>]
        * Other SPM Operations: @@NAME {drop|enable|disable|fix|unfix} <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]}

    Related Parameters:
        * _sql_plan_management_control:
            4 : Diagnose the issues of why SQL plan baselines fail to be used
            16: Allow SPM for the SQLs starting with "/* SQL Analyze("

    Turn on AUTO SPM:
        exec DBMS_SPM.CONFIGURE('AUTO_SPM_EVOLVE_TASK','ON');  //OR AUTO
        --exec DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK','ALTERNATE_PLAN_SOURCE','SQL_TUNING_SET');
        exec DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK','ACCEPT_PLANS','TRUE');
        --exec DBMS_AUTO_TASK_ADMIN.ENABLE(Client_Name => 'Auto STS Capture Task', Operation => NULL, Window_name => NULL);
        SELECT enabled FROM dba_autotask_schedule_control WHERE dbid=sys_context('userenv','con_dbid') AND task_name IN('Auto SPM Task','Auto STS Capture Task');

    Turn off AUTO SPM:
        exec DBMS_SPM.CONFIGURE('AUTO_SPM_EVOLVE_TASK','OFF');
        exec DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK','ALTERNATE_PLAN_SOURCE','AUTO');
        exec DBMS_SPM.SET_EVOLVE_TASK_PARAMETER('SYS_AUTO_SPM_EVOLVE_TASK','ALTERNATE_PLAN_BASELINE','EXISTING');
    --[[
        &filter: default={1=1} f={}
        @org : 23.1={origin} default={'MANUAL'}
        @sig : 23.1={EXACT_MATCHING_SIGNATURE} default={NULL}
        @check_access_sq: SYS.DBMS_SQLTUNE_UTIL0={1} DEFAULT={0}
    --]]
]]*/

set feed off printsize 10000


grid {[[SELECT /*grid={topic='DBA_SQL_MANAGEMENT_CONFIG'}*/ parameter_name,parameter_value
        FROM   dba_sql_management_config
        ORDER  BY 1]],
      '|',
      [[SELECT /*grid={topic='SYS_AUTO_SPM_EVOLVE_TASK Parameters'}*/
               parameter_name,
               parameter_value,
               parameter_type type,
               description
        FROM   dba_advisor_parameters
        WHERE  task_name='SYS_AUTO_SPM_EVOLVE_TASK'
        AND    parameter_value!='UNUSED'
        ORDER  BY 1]]
};

col ela,avg_ela for usmhd2
col execs for tmb2
var c REFCURSOR;
DECLARE
    v1       VARCHAR2(4000) := upper(:v1);
    v2       VARCHAR2(4000) := :v2;
    v3       VARCHAR2(4000) := :v3;
    key      VARCHAR2(4000) := v1;
    phv      INT := regexp_substr(v3,'^\d+$');
    new_sql  VARCHAR2(20);
    new_phv  INT;
    tmp_now  DATE;
    c        SYS_REFCURSOR;
    flag     PLS_INTEGER := 0;
    cnt      PLS_INTEGER := 0;
    tmp      PLS_INTEGER := 0;
    TYPE     t_phv IS TABLE OF VARCHAR2(30) INDEX BY VARCHAR2(30);
    phvs     t_phv;
    sql_text CLOB;
    names    dbms_spm.name_list := dbms_spm.name_list();
    CURSOR finder(v2 VARCHAR2,v3 VARCHAR2) IS
        SELECT /*+OPT_PARAM('_fix_control' '26552730:0') no_expand*/ sql_handle,plan_name
        FROM   dba_sql_plan_baselines
        WHERE  upper(v2) IN (upper(sql_handle),upper(plan_name),
                             ''||signature,
                             ''||to_number(substr(plan_name,-8),'fmxxxxxxxx'))
        AND   (nvl(phv,0) < 86400 OR to_char(phv,'fmxxxxxxxx')=substr(plan_name,-8))
        UNION  ALL
        SELECT 'SQL Profile',name
        FROM   dba_sql_profiles
        WHERE  upper(v2) IN (upper(name),''||signature)
        UNION  ALL
        SELECT 'SQL Patch',name
        FROM   dba_sql_patches
        WHERE  upper(v2) IN (upper(name),''||signature);
    CURSOR get_sql(v2 VARCHAR2,phv INT) IS
        SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ 'cursor' grp,
               sql_id,
               plan_hash_value phv,
               sql_fulltext sql_text,
               CAST(NULL AS VARCHAR2(128)) key1,
               CAST(NULL AS VARCHAR2(128)) key2
        FROM   v$sqlarea
        WHERE  sql_id=v2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    plan_hash_value>0
        UNION  ALL
        SELECT 'AWR',
               sql_id,
               plan_hash_value,
               sql_text,
               ''||dbid,
               ''||(SELECT MAX(snap_id)
                    FROM   dba_hist_sqlstat
                    WHERE  sql_id=v2
                    AND    plan_hash_value=a.plan_hash_value
                    AND    dbid=:dbid)
        FROM   dba_hist_sql_plan a
        JOIN   dba_hist_sqltext USING(dbid,sql_id)
        WHERE  sql_id=v2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    dbid=:dbid
        AND    plan_hash_value>0
        AND    other_xml IS NOT NULL
        UNION  ALL
        SELECT 'sqlset',
               sql_id,
               plan_hash_value,
               sql_text,
               sqlset_name,
               sqlset_owner
        FROM   dba_sqlset_statements
        WHERE  sql_id=v2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    plan_hash_value>0;

    PROCEDURE pr(sql_handle VARCHAR2,plan_name VARCHAR2,op VARCHAR, done PLS_INTEGER) IS
    BEGIN
        dbms_output.put_line(utl_lms.format_message('Target is %s%s (SQL_ID = %s / PLAN_HASH_VALUE = %s / SQL_HANDLE = %s / PLAN_NAME = %s).',
                                                    CASE WHEN done=0 THEN 'not ' END,
                                                    replace(op,'eed','ed'),
                                                    CASE WHEN sql_handle IN('SQL Profile','SQL Patch') THEN '' ELSE regexp_substr(plan_name,'PLAN_(.{13})',1,1,'i',1) END,
                                                    CASE WHEN sql_handle IN('SQL Profile','SQL Patch') THEN '' ELSE ''||to_number(substr(plan_name,-8),'fmxxxxxxxx') END,
                                                    sql_handle,plan_name));
        cnt := cnt + done;
    END;

    PROCEDURE total(v1 VARCHAR2) IS
    BEGIN
        dbms_output.put_line('Totally '||cnt||' SPMs are '||replace(lower(v1),'eed','ed')||'.');
    END;
BEGIN
    dbms_output.enable(NULL);
    IF v1 IN('DROP','FIX','UNFIX','ENABLE','DISABLE','LOAD','VIEW','ACCEPT','ENVOLVE','CATEGORY') AND v2 IS NULL THEN
        raise_application_error(-20001,'Please input more parameters to specify the target.');
    END IF;
    IF v1='SQL' THEN
        BEGIN
            SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/ sql_text
            INTO   sql_text
            FROM   (
                SELECT sql_text
                FROM   dba_sql_plan_baselines
                WHERE  :v2 IN(plan_name,sql_handle,''||signature)
                AND    rownum<2
                UNION  ALL
                SELECT sql_text
                FROM   dba_sql_profiles
                WHERE  :v2 IN(name,''||signature)
                AND    rownum<2
                UNION  ALL
                SELECT sql_text
                FROM   dba_sql_patches
                WHERE  :v2 IN(name,''||signature)
                AND    rownum<2)
            WHERE  rownum<2;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            raise_application_error(-20001,'No such SPM/Profile/Patch: '||:v1);
        END;
        $IF dbms_db_version.version>11 $THEN
            v2 := dbms_sql_translator.sql_id(sql_text);
        $END

        $IF &check_access_sq = 1 AND dbms_db_version.version=11 $THEN
            v2 := sys.dbms_sqltune_util0.sqltext_to_sqlid(sql_text);
            sql_text := NULL;
        $END
        dbms_output.put_line('SQL Id: '||v2);
        RETURN;
    ELSIF v1 IN('FIX','UNFIX','ENABLE','DISABLE','CATEGORY') THEN
        tmp_now := sysdate;

        FOR r IN finder(v2,v3) LOOP
            tmp := 0;
            IF r.sql_handle='SQL Profile' THEN
                IF v1 IN('ENABLE','DISABLE') THEN
                    sys.dbms_sqltune.alter_sql_profile(r.plan_name,'STATUS',v1||'D');
                    tmp := 1;
                ELSIF v1 IN('CATEGORY') THEN
                    sys.dbms_sqltune.alter_sql_profile(r.plan_name,'CATEGORY',nvl(v3,'DEFAULT'));
                    tmp := 1;
                END IF;
            ELSIF r.sql_handle='SQL Patch' THEN
                IF v1 IN('ENABLE','DISABLE') THEN
                    sys.dbms_sqldiag.alter_sql_patch(r.plan_name,'STATUS',v1||'D');
                    tmp := 1;
                ELSIF v1 IN('CATEGORY') THEN
                    sys.dbms_sqldiag.alter_sql_patch(r.plan_name,'CATEGORY',nvl(v3,'DEFAULT'));
                    tmp := 1;
                END IF;
            ELSIF v1 NOT IN('CATEGORY') THEN
                tmp := sys.dbms_spm.alter_sql_plan_baseline(
                        sql_handle      => r.sql_handle,
                        plan_name       => r.plan_name,
                        attribute_name  => CASE WHEN v1 IN('FIX','UNFIX') THEN 'fixed'
                                                WHEN v1 IN('ACCEPT','UNACCEPT') THEN 'accepted'
                                                ELSE 'enabled' END,
                        attribute_value => CASE WHEN v1 IN('FIX','ACCEPT','ENABLE') THEN 'YES' ELSE 'NO' END);
            END IF;
            pr(r.sql_handle,r.plan_name,lower(v1)||'ed',tmp);
        END LOOP;
        total(lower(v1)||'ed');
    ELSIF v1 IN('VIEW','ACCEPT','ENVOLVE') THEN
        tmp_now := sysdate;
        FOR r IN finder(v2,CASE WHEN phv<86400 THEN NULL ELSE v3 END) LOOP
            IF r.sql_handle NOT IN('SQL Profile','SQL Patch') THEN
                names.extend;
                names(names.count) := r.plan_name;
            END IF;
        END LOOP;
        IF names.count>0 THEN
            dbms_output.put_line(
                sys.dbms_spm.evolve_sql_plan_baseline(
                    plan_list  => names,
                    time_limit => CASE WHEN phv<86400 THEN phv WHEN v1='VIEW' THEN 30 ELSE 3600 END,
                    verify     => CASE WHEN v1='ACCEPT' THEN 'NO' ELSE 'YES' END,
                    commit     => CASE WHEN v1='VIEW' THEN 'NO' ELSE 'YES' END));
        END IF;
    ELSIF v1='LOAD' THEN
        tmp_now := sysdate;
        IF v3 IS NOT NULL THEN
            SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/
                   MAX(sql_id),MAX(plan_hash_value)
            INTO   new_sql,new_phv
            FROM   (
                SELECT sql_id,plan_hash_value
                FROM   v$sqlarea
                WHERE  phv IS NULL
                AND    sql_id=v3
                AND    plan_hash_value=nvl(regexp_substr(:v4,'^\d+$')+0,plan_hash_value)
                AND    plan_hash_value>0
                AND    rownum<2
                UNION  ALL
                SELECT sql_id,plan_hash_value
                FROM   v$sqlarea
                WHERE  phv IS NOT NULL
                AND    plan_hash_value=phv
                AND    plan_hash_value>0
                AND    rownum<2)
            WHERE  rownum<2;
            IF new_sql IS NOT NULL THEN
                phv := NULL;
            END IF;
        END IF;

        FOR r IN get_sql(v2,phv) LOOP
            IF new_sql IS NOT NULL THEN
                cnt := dbms_spm.load_plans_from_cursor_cache(sql_id=>new_sql,
                                                             plan_hash_value=>new_phv,
                                                             sql_text=>r.sql_text,
                                                             fixed=>'YES',
                                                             enabled=>'YES');
                EXIT;
            ELSIF NOT phvs.exists(''||r.phv) THEN
                IF r.grp = 'cursor' THEN
                    tmp := dbms_spm.load_plans_from_cursor_cache(sql_id=>r.sql_id,
                                                                 plan_hash_value=>r.phv,
                                                                 fixed=>'NO',
                                                                 enabled=>'YES');
                $IF dbms_db_version.version>12 OR dbms_db_version.version=12 AND dbms_db_version.release>1 $THEN
                ELSIF r.grp = 'AWR' THEN
                    tmp := dbms_spm.load_plans_from_awr(dbid=>r.key1,
                                                        begin_snap=>r.key2-1,
                                                        end_snap=>r.key2,
                                                        basic_filter=>utl_lms.format_message(q'[sql_id='%s' and plan_hash_value=%s]',r.sql_id,''||r.phv),
                                                        fixed=>'NO',
                                                        enabled=>'YES');
                $END
                ELSIF r.grp = 'sqlset' THEN
                    tmp := dbms_spm.load_plans_from_sqlset(sqlset_name=>r.key1,
                                                           sqlset_owner=>r.key2,
                                                           basic_filter=>utl_lms.format_message(q'[sql_id='%s' and plan_hash_value=%s]',r.sql_id,''||r.phv),
                                                           fixed=>'NO',
                                                           enabled=>'YES');
                END IF;
                IF tmp > 0 THEN
                    phvs(''||r.phv) := 'Y';
                    cnt := cnt + tmp;
                END IF;
            END IF;
        END LOOP;
        total('loaded');
    END IF;

    IF v1='DROP' THEN
        FOR r IN finder(v2,v3) LOOP
            tmp := 1;
            IF r.sql_handle='SQL Profile' THEN
                dbms_sqltune.drop_sql_profile(r.plan_name);
            ELSIF r.sql_handle='SQL Patch' THEN
                dbms_sqldiag.drop_sql_patch(r.plan_name);
            ELSE
                tmp := sys.dbms_spm.drop_sql_plan_baseline(r.sql_handle,r.plan_name);
            END IF;
            pr(r.sql_handle,r.plan_name,'dropped',tmp);
        END LOOP;
        total('dropped');
    ELSE
        cnt := 0;
        v3 := chr(1);
        IF tmp_now IS NOT NULL THEN
            v1 := NULL;
            v2 := NULL;
        ELSIF length(v1)=13 AND regexp_like(v1,'^[0-9A-Z]+$') THEN
            BEGIN
                SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/*
                INTO   v1,v2,sql_text
                FROM   (
                    SELECT exact_matching_signature,force_matching_signature,sql_fulltext
                    FROM   gv$sqlstats
                    WHERE  sql_id=lower(v1)
                    AND    rownum<2
                    UNION  ALL
                    SELECT &sig,force_matching_signature,sql_text
                    FROM   dba_sqlset_statements
                    WHERE  sql_id=lower(v1)
                    AND    rownum<2
                    UNION  ALL
                    SELECT NULL,NULL,sql_text
                    FROM   dba_hist_sqltext
                    WHERE  sql_id=lower(v1)
                    AND    dbid=:dbid
                    AND    rownum<2
                    UNION  ALL
                    SELECT NULL,NULL,to_clob(sql_text)
                    FROM   gv$sql_monitor
                    WHERE  sql_id=lower(v1)
                    AND    sql_text IS NOT NULL
                    AND    is_full_sqltext='Y'
                    AND    rownum<2)
                WHERE  rownum<2;
                v3 := chr(0);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            IF v1 IS NULL AND sql_text IS NOT NULL THEN
                v1 := dbms_sqltune.sqltext_to_signature(sql_text,false);
            END IF;
            IF v2 IS NULL AND sql_text IS NOT NULL THEN
                v2 := dbms_sqltune.sqltext_to_signature(sql_text,true);
            END IF;
        ELSE
            BEGIN
                SELECT /*+OPT_PARAM('_fix_control' '26552730:0')*/flag,1,plan_name,sql_text
                INTO   flag,cnt,v3,sql_text
                FROM   (
                    SELECT 1 flag,plan_name,created,sql_text
                    FROM   dba_sql_plan_baselines
                    WHERE  :v1 IN(plan_name,sql_handle)
                    AND    nvl(0+regexp_substr(:v2,'^\d+$'),-1) IN(to_number(substr(plan_name,-8),'fmxxxxxxxx'),signature,-1)
                    UNION  ALL
                    SELECT 2,name,created,sql_text
                    FROM   dba_sql_profiles
                    WHERE  :v1 = name
                    AND    nvl(0+regexp_substr(:v2,'^\d+$'),-1) IN(signature,-1)
                    UNION  ALL
                    SELECT 3,name,created,sql_text
                    FROM   dba_sql_patches
                    WHERE  :v1 = name
                    AND    nvl(0+regexp_substr(:v2,'^\d+$'),-1) IN(signature,-1)
                    ORDER  BY created DESC)
                WHERE  rownum < 2;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                v3  := chr(1);
                cnt := 0;
            END;
        END IF;

        IF cnt > 0 THEN
            $IF dbms_db_version.version>11 $THEN
                v2 := dbms_sql_translator.sql_id(sql_text);
                sql_text := NULL;
            $END

            $IF &check_access_sq = 1 AND dbms_db_version.version=11 $THEN
                v2 := sys.dbms_sqltune_util0.sqltext_to_sqlid(sql_text);
                sql_text := NULL;
            $END

            IF v2 IS NOT NULL AND sql_text IS NULL THEN
                sql_text := 'SQL Id: ' || v2;
            ELSE
                sql_text := '';
            END IF;

            IF flag=1 THEN
                FOR r IN (SELECT * FROM table(dbms_xplan.display_sql_plan_baseline(NULL,v3,'ALL -PROJECTION'))) LOOP
                    sql_text := sql_text || r.plan_table_output||chr(10);
                END LOOP;
            ELSIF flag=2 THEN
                FOR r IN (SELECT * FROM table(dbms_xplan.display_sql_profile_plan(v3,'ALL -PROJECTION'))) LOOP
                    sql_text := sql_text || r.plan_table_output||chr(10);
                END LOOP;
            ELSE
                FOR r IN (SELECT * FROM table(dbms_xplan.display_sql_patch_plan(v3,'ALL -PROJECTION'))) LOOP
                    sql_text := sql_text || r.plan_table_output||chr(10);
                END LOOP;
            END IF;

            sql_text := sql_text|| 'SQL Id: ' || v2;

            OPEN c FOR SELECT sql_text plan_table_output FROM dual;
        ELSE
            OPEN c FOR
                SELECT /*+opt_param('optimizer_dynamic_sampling' 7) opt_param('_fix_control' '26552730:0')*/ *
                FROM   (
                    SELECT /*+NO_EXPAND*/ plan_name,sql_handle handle,
                           to_number(substr(plan_name,-8),'fmxxxxxxxx') plan_hash_2,
                           signature,
                           attrs,
                           origin,
                           nvl(last_modified+0,created+0) updated,
                           schema,
                           substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (
                        SELECT a.*,
                               trim(',' FROM CASE WHEN enabled='YES' THEN 'ENABLED,' END
                                    ||CASE WHEN fixed='YES' THEN 'FIXED,' END
                                    ||CASE WHEN accepted='YES' THEN 'ACCEPTED,' END
                                    ||CASE WHEN autopurge='YES' THEN 'AUTOPURGE,' END
                                    ||CASE WHEN reproduced='NO' THEN 'NON-REPRODUCED,' END
                                $IF dbms_db_version.version > 11 $THEN
                                    ||CASE WHEN adaptive='YES' THEN 'ADAPTIVE,' END
                                $END
                                $IF dbms_db_version.version > 22 $THEN
                                    ||nvl2(foreground_last_verified,'FG-VERIFIED,','')
                                    ||decode(bitand(flags, 1024), 0, '', 'REALTIME,')
                                    ||decode(bitand(flags, 2048), 0, '', 'REVERSE,')
                                    ||n.status
                                $END
                                ) attrs,
                               parsing_schema_name schema
                        FROM   dba_sql_plan_baselines a
                        $IF dbms_db_version.version > 22 $THEN
                             ,xmltable('/notes'
                                passing xmltype(a.notes)
                                columns
                                    sql_id    VARCHAR2(20) PATH '//sql_id',
                                    plan_id   NUMBER       PATH 'plan_id',
                                    flags     NUMBER       PATH 'flags',
                                    ref_phv   NUMBER       PATH '//ref_phv',
                                    test_phv  NUMBER       PATH '//test_phv',
                                    ver       VARCHAR2(8)  PATH '//ver',
                                    comp_time VARCHAR2(20) PATH '//comp_time',
                                    ver_time  VARCHAR2(20) PATH '//ver_time',
                                    status    VARCHAR2(8)  PATH '//status') n
                        $END
                        ) a
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND (signature IN(v1,v2) OR instr(plan_name,key)>0) OR
                            v3=chr(1) AND (v1 IS NULL OR upper(sql_handle||','||plan_name||','
                                                               ||to_number(substr(plan_name,-8),'fmxxxxxxxx')||','
                                                               ||signature||','
                                                               ||attrs||','
                                                               ||parsing_schema_name||','
                                                               ||to_char(substr(sql_text,1,2000))) LIKE '%'||v1||'%')
                            AND    (v2 IS NULL OR v2=''||to_number(substr(plan_name,-8),'fmxxxxxxxx')))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    UNION  ALL
                    SELECT /*+NO_EXPAND*/ plan_name,
                           'SQL Profile',
                           NULL,
                           signature,
                           attrs,
                           origin,
                           nvl(last_modified+0,created+0) updated,
                           schema,
                           substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (SELECT a.*,name plan_name,
                                   trim(',' FROM status||','
                                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                                    ) attrs,
                                   category schema,
                                   category parsing_schema_name,
                                   type||nvl2(task_id,'(task_id='||task_id||')','') origin
                            FROM   dba_sql_profiles a)
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND (signature IN(v1,v2) OR instr(plan_name,key)>0) OR
                            v3=chr(1) AND (v1 IS NULL OR upper('SQL Profile'||','||name||','
                                                               ||signature||','||category||','||attrs||','
                                                               ||to_char(substr(sql_text,1,2000))) LIKE '%'||v1||'%'))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    UNION  ALL
                    SELECT /*+NO_EXPAND*/ plan_name,
                           'SQL Patch',
                           NULL,
                           signature,
                           attrs,
                           org,
                           nvl(last_modified+0,created+0) updated,
                           schema,
                           substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (SELECT a.*,name plan_name,
                                   trim(',' FROM status||','
                                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                                    ) attrs,
                                   category schema,
                                   category parsing_schema_name,
                                   &org||nvl2(task_id,'(task_id='||task_id||')','') org
                            FROM   dba_sql_patches a)
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND (signature IN(v1,v2) OR instr(plan_name,key)>0) OR
                            v3=chr(1) AND (v1 IS NULL OR upper('SQL Patch'||','||name||','
                                                               ||signature||','||category||','
                                                               ||to_char(substr(sql_text,1,2000))) LIKE '%'||v1||'%'))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    ORDER  BY updated DESC NULLS LAST)
                WHERE  rownum<=50;
        END IF;
    END IF;
    :c := c;
END;
/
