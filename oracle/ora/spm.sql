/*[[
    View/Create/Modify SQL Profile/Patch/SPM. Usage: @@NAME [load|drop|enable|disable|fix|unfix <keyword> [<phv>]] | [<keyword>|-f"<filter>"]  
        * List existing SPMs: @@NAME [<keyword>|-f"<filter>"]
        * Load SPM from cursor/awr/sqlset: @@NAME load <sql_id> [<new_sql_id>|<plan_hash>]
        * View the detail of a existing SPM: @@NAME view <sql_handle>|<plan_name>|<signature>|{<sql_id> [<plan_hash>]} 
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
    --]]
]]*/
set feed off
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
    type     T_PHV IS TABLE OF VARCHAR2(1) INDEX BY VARCHAR2(30);
    phvs     T_PHV;
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
    IF V1 IN('FIX','UNFIX','ENABLE','DISABLE','CATEGORY') THEN
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

        FOR R IN(
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
                   ''||dbid,
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
            AND    plan_hash_value>0) 
        LOOP
            IF new_sql IS NOT NULL THEN
                IF cnt=0 THEN
                    tmp := dbms_spm.load_plans_from_cursor_cache(sql_id=>new_sql,
                                                                 plan_hash_value=>new_phv,
                                                                 sql_text=>r.sql_text,
                                                                 fixed=>'YES',
                                                                 enabled=>'YES');
                END IF;
                cnt := 1;
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
        IF tmp_now IS NOT NULL THEN
            v1 := null;
            v2 := null;
            v3 := null;
        END IF;
        OPEN c FOR
            SELECT * FROM (
                SELECT regexp_replace(plan_name,'PLAN_(.{13})','PLAN_$PROMPTCOLOR$\1$NOR$') "PLAN_NAME (SQL_Id:13,PHV:8)",
                       ''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx') plan_hash_2,
                       signature,
                       trim(',' FROM CASE WHEN enabled='YES' THEN 'ENABLED,' END
                           ||CASE WHEN fixed='YES' THEN 'FIXED,' END
                           ||CASE WHEN accepted='YES' THEN 'ACCEPTED,' END
                           ||CASE WHEN autopurge='YES' THEN 'AUTOPURGE,' END
                           ||CASE WHEN reproduced='YES' THEN 'REPRODUCED,' END
                       $IF DBMS_DB_VERSION.VERSION > 11 $THEN
                           ||CASE WHEN adaptive='YES' THEN 'ADAPTIVE,' END
                       $END
                       ) attrs,
                       origin,
                       nvl(last_modified+0,created+0) updated,          
                       schema,
                       substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                FROM   (select a.*,parsing_schema_name schema from dba_sql_plan_baselines a)
                WHERE  (&filter)
                AND    (V1 IS NULL OR upper(sql_handle||','||plan_name||','
                                      ||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx')||','
                                      ||signature||','
                                      ||parsing_schema_name||','
                                      ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%')
                AND    (V2 IS NULL OR v2=''||to_number(regexp_substr(plan_name,'(.{8})$'),'fmxxxxxxxx'))
                AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                UNION ALL
                SELECT NAME,
                       'SQL Profile',
                       signature,
                       trim(',' FROM status||','
                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                       ) attrs,
                       origin,
                       nvl(last_modified+0,created+0) updated,
                       schema,
                       substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                FROM   (select a.*,category schema,category parsing_schema_name,type||nvl2(task_id,'(task_id='||task_id||')','') origin from dba_sql_profiles a)
                WHERE  (&filter)
                AND    (V1 IS NULL OR upper('SQL Profile'||','||name||','
                                      ||signature||','||category||','
                                      ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%')
                AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                UNION ALL
                SELECT NAME,
                       'SQL Patch',
                       signature,
                       trim(',' FROM status||','
                            ||CASE WHEN force_matching='YES' THEN 'FORCE_MATCHING,' END
                       ) attrs,
                       org,
                       nvl(last_modified+0,created+0) updated,
                       schema,
                       substr(trim(regexp_replace(to_char(substr(sql_text,1,1500)),'\s+',' ')),1,200) sql_text
                FROM   (select a.*,category schema,category parsing_schema_name,&org||nvl2(task_id,'(task_id='||task_id||')','') org from dba_sql_patches a)
                WHERE  (&filter)
                AND    (V1 IS NULL OR upper('SQL Patch'||','||name||','
                                      ||signature||','||category||','
                                      ||to_char(substr(sql_text,1,2000))) LIKE '%'||V1||'%')
                AND    (tmp_now IS NULL OR greatest(created,nvl(last_modified+0,sysdate-3650))>=tmp_now)
                ORDER BY updated DESC NULLS LAST)
            WHERE ROWNUM<=50;
    END IF;
    :c := c;
END;
/

