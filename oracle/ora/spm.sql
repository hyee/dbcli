/*[[
    View/Create/Modify SQL Profile/Patch/SPM. Usage: @@NAME [sql|load|drop|enable|disable|fix|unfix <keyword> [<phv>]] | [<keyword>|-f"<filter>"]
        * List existing SPMs: @@NAME [<keyword>|<sql_id> [<plan_hash>]|-f"<filter>"]
        * Load SPM from cursor/awr/sqlset: @@NAME load <sql_id> [<new_sql_id>|<plan_hash>]
        * View SQL Id: @@NAME sql <sql_handle>|<plan_name>|<signature>
        * View the envolve detail of a existing SPM: @@NAME view <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]}
        * View the execution plan of a existing SPM: @@NAME <sql_handle>|<plan_name> [<plan_hash>]
        * Change category of SQL Profile/Patch: @@NAME CATEGORY <name> <category>
        * Accept a existing SPM without running envolve task to verify the performance: @@NAME accept <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]} 
        * Envolve a existing SPM: @@NAME envolve <sql_handle>|<plan_name>|<signature>|<sql_id> [<plan_hash>|<seconds>]
        * Other SPM Operations: @@NAME {drop|enable|disable|fix|unfix} <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]}
    
    Relative Parameters:
        * _sql_plan_management_control:
            4 : diagnose issues with SQL plan baselines of why it fails to use
            16: Allow SPM on the SQLs start with "/* SQL Analyze("
    --[[
       
        &filter: default={1=1} f={}
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select /*+PRECOMPUTE_SUBQUERY*/ dbid from v$database)}
        @org : 23.1={origin} default={'MANUAL'}
        @sig : 23.1={EXACT_MATCHING_SIGNATURE} default={NULL}
        @check_access_sq: SYS.DBMS_SQLTUNE_UTIL0={1} DEFAULT={0}
    --]]
]]*/

set feed off printsize 10000


grid {[[SELECT /*grid={topic='DBA_SQL_MANAGEMENT_CONFIG'}*/  PARAMETER_NAME,PARAMETER_VALUE FROM DBA_SQL_MANAGEMENT_CONFIG ORDER BY 1]],
      '|',
      [[SELECT /*grid={topic='SYS_AUTO_SPM_EVOLVE_TASK Parameters'}*/  
              PARAMETER_NAME,PARAMETER_VALUE,PARAMETER_TYPE type,DESCRIPTION
        FROM dba_advisor_parameters 
        WHERE task_name='SYS_AUTO_SPM_EVOLVE_TASK' AND PARAMETER_VALUE!='UNUSED'
        ORDER BY 1]]
};

col ela,avg_ela for usmhd2
col execs for tmb2
VAR c REFCURSOR;
DECLARE
    V1       VARCHAR2(4000):=UPPER(:V1);
    V2       VARCHAR2(4000):=:V2;
    V3       VARCHAR2(4000):=:V3;
    PHV      INT := regexp_substr(V3,'^\d+$');
    new_sql  VARCHAR2(20);
    new_phv  INT;
    tmp_now  DATE;
    c        SYS_REFCURSOR;
    cnt      PLS_INTEGER := 0;
    tmp      PLS_INTEGER := 0;
    type     T_PHV IS TABLE OF VARCHAR2(30) INDEX BY VARCHAR2(30);
    phvs     T_PHV;
    sql_text CLOB;
    names    DBMS_SPM.NAME_LIST := DBMS_SPM.NAME_LIST();
    CURSOR finder(V2 VARCHAR2,V3 VARCHAR2) IS
        SELECT sql_handle,plan_name 
        FROM   dba_sql_plan_baselines
        WHERE  upper(V2) IN (upper(sql_handle),upper(plan_name),
                             upper(regexp_substr(plan_name,'PLAN_(.{13})',1,1,'i',1)),
                             ''||signature,
                             ''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx'))
        AND   (V3 IS NULL OR V3=''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx'))
        UNION ALL
        SELECT 'SQL Profile',NAME
        FROM  dba_sql_profiles
        WHERE  upper(V2) IN (upper(name),''||signature)
        UNION ALL
        SELECT 'SQL Patch',NAME
        FROM  dba_sql_patches
        WHERE  upper(V2) IN (upper(name),''||signature); 
    CURSOR get_sql(V2 VARCHAR2,PHV INT) IS
        SELECT 'cursor' grp,
            sql_id,
            plan_hash_value phv,
            sql_fulltext sql_text,
            cast(null as varchar2(128)) key1,
            cast(null as varchar2(128)) key2
        FROM   v$sqlarea
        WHERE  sql_id=V2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    plan_hash_value>0
        UNION  ALL 
        SELECT 'AWR',
            sql_id,
            plan_hash_value,
            sql_text,
            ''||:dbid,
            ''||(select MAX(snap_id) from dba_hist_sqlstat WHERE sql_id=V2 AND plan_hash_value=a.plan_hash_value AND DBID=:dbid)
        FROM   dba_hist_sql_plan a
        JOIN   dba_hist_sqltext USING(dbid,sql_id)
        WHERE  sql_id=V2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    dbid=:dbid
        AND    plan_hash_value>0
        UNION  ALL 
        SELECT 'sqlset',
            sql_id,
            plan_hash_value,
            sql_text,
            sqlset_name,
            sqlset_owner
        FROM   dba_sqlset_statements
        WHERE  sql_id=V2
        AND    plan_hash_value=nvl(phv,plan_hash_value)
        AND    plan_hash_value>0;

    PROCEDURE pr(sql_handle VARCHAR2,plan_name VARCHAR2,op VARCHAR, done PLS_INTEGER) IS
    BEGIN
        dbms_output.put_line(utl_lms.format_message('Target is %s%s (SQL_ID = %s / PLAN_HASH_VALUE = %s / SQL_HANDLE = %s / PLAN_NAME = %s).',
                        CASE WHEN done=0 THEN 'not ' END,
                        replace(op,'eed','ed'),
                        CASE WHEN sql_handle IN('SQL Profile','SQL Patch') THEN '' ELSE regexp_substr(plan_name,'PLAN_(.{13})',1,1,'i',1) END,
                        CASE WHEN sql_handle IN('SQL Profile','SQL Patch') THEN '' ELSE ''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx') END,
                        sql_handle,plan_name));
        cnt := cnt + done;
    END;

    PROCEDURE total(v1 VARCHAR2) IS
    BEGIN
        dbms_output.put_line('Totally '||cnt||' SPMs are '||replace(lower(V1),'eed','ed')||'.');
    END;
BEGIN
    dbms_output.enable(null);
    IF V1 IN('DROP','FIX','UNFIX','ENABLE','DISABLE','LOAD','VIEW','ACCEPT','ENVOLVE','CATEGORY') AND V2 IS NULL THEN
        raise_application_error(-20001,'Please input more parameters to specify the target.');
    END IF;
    IF V1='SQL' THEN
        BEGIN
            SELECT sql_text
            INTO   sql_text
            FROM (
                SELECT sql_text
                FROM   dba_sql_plan_baselines
                WHERE  :v2 in(PLAN_NAME,SQL_HANDLE,''||signature)
                AND    rownum<2
                UNION ALL
                SELECT sql_text
                FROM   dba_sql_profiles
                WHERE  :v2 in(NAME,''||signature)
                AND    rownum<2
                UNION ALL
                SELECT sql_text
                FROM   dba_sql_patches
                WHERE  :v2 in(NAME,''||signature)
                AND    rownum<2)
            WHERE rownum<2;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            raise_application_error(-20001,'No such SPM/Profile/Patch: '||:v1);
        END;
        $IF DBMS_DB_VERSION.VERSION>11 $THEN
            V2 := dbms_sql_translator.sql_id(sql_text);
        $END

        $IF &check_access_sq = 1 AND DBMS_DB_VERSION.VERSION=11 $THEN
            V2 := SYS.DBMS_SQLTUNE_UTIL0.SQLTEXT_TO_SQLID(sql_text);
            sql_text := null;
        $END
        dbms_output.put_line('SQL Id: '||v2);
        return;
    ELSIF V1 IN('FIX','UNFIX','ENABLE','DISABLE','CATEGORY') THEN
        tmp_now := SYSDATE;
        FOR r IN finder(v2,v3) LOOP
            IF r.sql_handle='SQL Profile' THEN
                IF V1 IN('ENABLE','DISABLE') THEN
                    sys.dbms_sqltune.alter_sql_profile(r.plan_name,'STATUS',V1||'D');
                    tmp := 1;
                ELSIF V1 IN('CATEGORY') THEN
                    sys.dbms_sqltune.alter_sql_profile(r.plan_name,'CATEGORY',NVL(V3,'DEFAULT'));
                    tmp := 1;
                END IF;
            ELSIF r.sql_handle='SQL Patch' THEN
                IF V1 IN('ENABLE','DISABLE') THEN
                    sys.dbms_sqldiag.alter_sql_patch(r.plan_name,'STATUS',V1||'D');
                    tmp := 1;
                ELSIF V1 IN('CATEGORY') THEN
                    sys.dbms_sqldiag.alter_sql_patch(r.plan_name,'CATEGORY',NVL(V3,'DEFAULT'));
                    tmp := 1;
                END IF;
            ELSIF V1 NOT IN('CATEGORY') THEN
                tmp := sys.dbms_spm.alter_sql_plan_baseline(
                        sql_handle      => r.sql_handle,
                        plan_name       => r.plan_name,
                        attribute_name  => CASE WHEN V1 IN('FIX','UNFIX') THEN 'fixed' ELSE 'enabled' END,
                        attribute_value => CASE WHEN V1 IN('FIX','ENABLE') THEN 'YES' ELSE 'NO' END);
            END IF;
            pr(r.sql_handle,r.plan_name,lower(V1)||'ed',tmp);
        END LOOP;
        total(lower(V1)||'ed');
    ELSIF V1 IN('VIEW','ACCEPT','ENVOLVE') THEN
        tmp_now := SYSDATE;
        FOR r IN finder(v2,CASE WHEN phv<86400 THEN null ELSE v3 END) LOOP
            IF r.sql_handle NOT IN('SQL Profile','SQL Patch') THEN
                names.extend;
                names(names.count) := r.plan_name;
            END IF;
        END LOOP;
        IF names.count>0 THEN
            dbms_output.put_line(
                SYS.DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(
                    plan_list  => names,
                    time_limit => CASE WHEN phv<86400 THEN phv WHEN V1='VIEW' THEN 30 ELSE 3600 END,
                    verify     => CASE WHEN V1='ACCEPT' THEN 'NO' ELSE 'YES' END,
                    commit     => CASE WHEN V1='VIEW' THEN 'NO' ELSE 'YES' END));
        END IF;
    ELSIF V1='LOAD' THEN
        tmp_now := SYSDATE;
        IF V3 IS NOT NULL THEN
            SELECT MAX(sql_id),MAX(plan_hash_value)
            INTO   new_sql,new_phv
            FROM (
                SELECT sql_id,plan_hash_value 
                FROM   v$sqlarea
                WHERE  phv IS NULL
                AND    sql_id=V3
                AND    plan_hash_value=nvl(regexp_substr(:V4,'^\d+$')+0,plan_hash_value)
                AND    plan_hash_value>0
                AND    rownum<2
                UNION  ALL
                SELECT sql_id,plan_hash_value 
                FROM   v$sqlarea
                WHERE  phv IS NOT NULL
                AND    plan_hash_value=phv
                AND    plan_hash_value>0
                AND    rownum<2)
            WHERE rownum<2;
            IF new_sql IS NOT NULL THEN
                phv := null;
            END IF;
        END IF;

        FOR R IN GET_SQL(V2,PHV)
        LOOP
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
                $IF DBMS_DB_VERSION.RELEASE>12 OR DBMS_DB_VERSION.RELEASE=12 AND DBMS_DB_VERSION.VERSION>1 $THEN
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

    IF V1='DROP' THEN
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
            v1 := null;
            v2 := null;
        ELSIF length(v1)=13 AND regexp_like(v1,'^[0-9A-Z]+$') THEN
            BEGIN
                SELECT *
                INTO   v1,v2,sql_text
                FROM (
                    SELECT EXACT_MATCHING_SIGNATURE,FORCE_MATCHING_SIGNATURE,SQL_FULLTEXT
                    FROM   GV$SQLSTATS
                    WHERE  SQL_ID=lower(v1)
                    AND    ROWNUM<2
                    UNION ALL
                    SELECT &sig,FORCE_MATCHING_SIGNATURE,SQL_TEXT
                    FROM   DBA_SQLSET_STATEMENTS
                    WHERE  SQL_ID=lower(v1)
                    AND    ROWNUM<2
                    UNION ALL
                    SELECT NULL,NULL,SQL_TEXT
                    FROM   DBA_HIST_SQLTEXT
                    WHERE  SQL_ID=lower(v1)
                    AND    dbid=:dbid
                    AND    ROWNUM<2
                    UNION ALL
                    SELECT NULL,NULL,TO_CLOB(SQL_TEXT)
                    FROM   GV$SQL_MONITOR
                    WHERE  SQL_ID=lower(v1)
                    AND    SQL_TEXT IS NOT NULL
                    AND    IS_FULL_SQLTEXT='Y'
                    AND    ROWNUM<2
                ) WHERE ROWNUM<2;
                v3 := chr(0);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            IF v1 IS NULL AND sql_text IS NOT NULL THEN
                v1 :=  dbms_sqltune.SQLTEXT_TO_SIGNATURE(sql_text,false);
            ELSIF v2 IS NULL AND sql_text IS NOT NULL THEN
                v2 :=  dbms_sqltune.SQLTEXT_TO_SIGNATURE(sql_text,true);
            END IF;
        ELSE
            SELECT count(1),max(plan_name)
            INTO   cnt,v3
            FROM   dba_sql_plan_baselines
            WHERE  :v1 in(PLAN_NAME,SQL_HANDLE)
            AND   (regexp_substr(:v2,'^\d+$') is null or :v2 in(to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx'),signature));

            IF cnt = 0 THEN
                v3 := chr(1);
            END IF;
        END IF;

        IF cnt > 0 THEN
            SELECT SQL_TEXT
            INTO   SQL_TEXT
            FROM   dba_sql_plan_baselines
            WHERE  PLAN_NAME=v3;

            $IF DBMS_DB_VERSION.VERSION>11 $THEN
                V2 := dbms_sql_translator.sql_id(sql_text);
                sql_text := null;
            $END

            $IF &check_access_sq = 1 AND DBMS_DB_VERSION.VERSION=11 $THEN
                V2 := SYS.DBMS_SQLTUNE_UTIL0.SQLTEXT_TO_SQLID(sql_text);
                sql_text := null;
            $END

            IF v2 IS NOT NULL AND sql_text IS NULL THEN
                sql_text := 'SQL Id: ' || V2;
            ELSE
                sql_text := '';
            END IF;

            
            FOR r IN (SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_SQL_PLAN_BASELINE (CASE WHEN cnt>1 THEN :v1 END,CASE WHEN cnt=1 THEN v3 END,'ALL -PROJECTION'))) LOOP
                sql_text := sql_text || r.PLAN_TABLE_OUTPUT||chr(10);
            END LOOP;

            sql_text := sql_text|| 'SQL Id: ' || V2;

            OPEN c FOR SELECT sql_text PLAN_TABLE_OUTPUT FROM dual;
        ELSE
            OPEN c FOR
                SELECT /*+opt_param('DYNAMIC_SAMPLING' 7)*/ * FROM (
                    SELECT /*+NO_EXPAND*/ sql_handle,
                        ''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx') plan_hash_2,
                        signature,
                        attrs,
                        origin,
                        nvl(last_modified+0,created+0) updated,          
                        schema,
                        substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (select a.*,
                                   trim(',' FROM CASE WHEN enabled='YES' THEN 'ENABLED,' END
                                        ||CASE WHEN fixed='YES' THEN 'FIXED,' END
                                        ||CASE WHEN accepted='YES' THEN 'ACCEPTED,' END
                                        ||CASE WHEN autopurge='YES' THEN 'AUTOPURGE,' END
                                        ||CASE WHEN reproduced='NO' THEN 'NON-REPRODUCED,' END
                                    $IF DBMS_DB_VERSION.VERSION > 11 $THEN
                                        ||CASE WHEN adaptive='YES' THEN 'ADAPTIVE,' END
                                    $END
                                    $IF DBMS_DB_VERSION.VERSION > 23 $THEN
                                        ||nvl2(foreground_last_verified,'FG-VERIFIED,','')
                                        --||decode(bitand(flags, 1024), 0, '', 'REALTIME,')
                                        --||decode(bitand(flags, 2048), 0, '', 'REVERSE,')
                                        --||n.status
                                    $END
                                    ) attrs,
                            parsing_schema_name schema from dba_sql_plan_baselines a) a
                        $IF DBMS_DB_VERSION.VERSION > 22 $THEN
                            ,XMLTABLE('/notes'
                                    passing xmltype(a.notes)
                                    columns
                                        sql_id          VARCHAR2(20)   path '//sql_id',
                                        plan_id         NUMBER         path 'plan_id',
                                        flags           NUMBER         path 'flags',
                                        ref_phv         NUMBER         path '//ref_phv',
                                        test_phv        NUMBER         path '//test_phv',
                                        ver             VARCHAR2(8)    path '//ver',
                                        comp_time       VARCHAR2(20)   path '//comp_time',
                                        ver_time        VARCHAR2(20)   path '//ver_time',
                                        status          VARCHAR2(8)    path '//status') n
                        $END    
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND  signature IN(V1,V2) OR
                            v3=chr(1) AND (V1 IS NULL OR upper(sql_handle||','||plan_name||','
                                                ||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx')||','
                                                ||signature||','
                                                ||attrs||','
                                                ||parsing_schema_name||','
                                                ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%')
                            AND    (V2 IS NULL OR v2=''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx')))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    UNION ALL
                    SELECT  /*+NO_EXPAND*/ NAME,
                            'SQL Profile',
                            signature,
                            attrs,
                            origin,
                            nvl(last_modified+0,created+0) updated,
                            schema,
                            substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (select a.*,
                                   trim(',' FROM status||','
                                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                                    ) attrs,
                                   category schema,
                                   category parsing_schema_name,
                                   type||nvl2(task_id,'(task_id='||task_id||')','') origin 
                            from dba_sql_profiles a)
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND  signature IN(V1,V2) OR
                            v3=chr(1) AND (V1 IS NULL OR upper('SQL Profile'||','||name||','
                                                ||signature||','||category||','||attrs||','
                                                ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%'))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    UNION ALL
                    SELECT  /*+NO_EXPAND*/ NAME,
                            'SQL Patch',
                            signature,
                            attrs,
                            org,
                            nvl(last_modified+0,created+0) updated,
                            schema,
                            substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                    FROM   (select a.*,
                                   trim(',' FROM status||','
                                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                                    ) attrs,
                                   category schema,
                                   category parsing_schema_name,
                                   &org||nvl2(task_id,'(task_id='||task_id||')','') org 
                            from dba_sql_patches a)
                    WHERE  (&filter)
                    AND    (v3=chr(0) AND signature IN(V1,V2) OR
                            v3=chr(1) 
                            AND    (V1 IS NULL OR upper('SQL Patch'||','||name||','
                                                ||signature||','||category||','
                                                ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%'))
                    AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                    ORDER BY updated DESC NULLS LAST)
                WHERE ROWNUM<=50;
        END IF;
    END IF;
    :c := c;
END;
/

