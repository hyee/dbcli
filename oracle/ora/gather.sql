/*[[Gather object/SQL statistics. Usage: @@NAME {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> <percent|0> ["<method_opt>"] [-async|-trace]
    <percent>            : The sample percentage(in %) for gathering stats, 0 as default 
    -async               : Create scheduler job to gather in background.
    -trace               : Print gather stats traces
    -noinvalid           : Do not auto-invalid the cursors
    -force               : Force gathering stats even the stats is locked
    -t"[<owner>.]<table>": Save stats into target table, instead of updating object stats
    <method_opt>         : Default as global prefs "METHOD_OPT", which is normally "FOR ALL COLUMNS SIZE AUTO"
         -skew           : Same to "FOR ALL COLUMNS SIZE SKEWONLY"
         -repeat         : Same to "FOR ALL COLUMNS SIZE REPEAT"
         <other>         : Refer to documentation of parameter "method_opt"
    --[[
        @ARGS: 3
        &async  : default={-1} async={0} trace={2}
        &invalid: default={} noinvalid={,no_invalidate=>true}
        &force  : defualt={} force={,force=>true}
        &t      : default={} t={}
        &V4: default={} skew={FOR ALL COLUMNS SIZE SKEWONLY} repeat={FOR ALL COLUMNS SIZE REPEAT}
    --]]
]]*/

findobj "&V1" 1 1
set feed off

DECLARE
    sq_id VARCHAR2(30)  := :V1;
    own   VARCHAR2(128) := :object_owner;
    nam   VARCHAR2(128) := :object_name;
    typ   VARCHAR2(128) := :object_type;
    part  VARCHAR2(128) := :object_subname;
    pct   NUMBER        := regexp_substr(:V3,'^[\.0-9]+$');
    dop   INT           := regexp_substr(:V2,'^\d+$');
    opt   VARCHAR2(300) := :V4;
    msg   VARCHAR2(300) := 'PARAMETERS: {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> 0|<percent> -async';
    fmt   VARCHAR2(300) := q'[dbms_stats.gather_%s_stats('%s','%s','%s',%s,statown=>'%s',stattab=>'%s',degree=>%s&invalid.&force.%s);]';
    stmt  VARCHAR2(32767);
    town  VARCHAR2(128);
    tnam  VARCHAR2(256) := replace(trim(upper(:t)),' '); 
    cnt   INT;
    FUNCTION parse(own varchar2,nam varchar2,typ varchar2,part varchar2,pct varchar2,dop varchar2,cascade varchar2:='false') RETURN VARCHAR2 IS
    BEGIN
        return utl_lms.format_message(fmt,
                CASE WHEN typ LIKE 'INDEX%' THEN 'index' else 'table' END,
                own,nam,part,pct,town,tnam,dop,
                CASE when typ NOT LIKE 'INDEX%' THEN 
                    ',block_sample=>true,cascade=>'||cascade||case when opt is not null then ',method_opt=>'''||opt||'''' end
                END
            );
    END;

    PROCEDURE submit(cmd VARCHAR2) IS
        async INT := '&async';
        ln    VARCHAR2(1):=chr(10);
        job   VARCHAR2(128);
        c     INT;
    BEGIN
        stmt :=replace(ln||cmd,ln,ln||'    ')||ln;
        IF async=-1 THEN
            stmt := 'BEGIN'||stmt||'END;';
            dbms_output.put_line(stmt);
            EXECUTE IMMEDIATE stmt;
        ELSIF async=0 THEN
            select count(1) into c
            from   v$sysstat
            where  name like 'cell%elig%pred%offload%'
            and    value>0;

            stmt :=CASE WHEN c>0 then q'[    execute immediate 'alter session set "_serial_direct_read"=always';]' END
                || replace(q'~
                begin
                    execute immediate q'[alter session set "_fix_control"='25167306:1']';
                exception when others then null;
                end; ~'
                ||stmt,'            ');
            job:=dbms_scheduler.generate_job_name('GATHER_STATS_');
            dbms_scheduler.create_job(job_name   => job,
                                      job_type   => 'PLSQL_BLOCK',
                                      job_action => stmt,
                                      enabled    => TRUE);
            dbms_output.put_line('Schedule job '||job||' is created to run the gathering in background mode. Statement:');
            dbms_output.put_line(stmt);
        ELSE
            dbms_output.put_line('Trace Start. Statement:');
            stmt := 'BEGIN'||stmt||'END;';
            dbms_output.put_line(stmt);
            dbms_stats.set_global_prefs('TRACE',1+2+4+8+16+64+1024);
            BEGIN
                EXECUTE IMMEDIATE stmt;
                dbms_output.put_line('Trace End');
            EXCEPTION WHEN OTHERS THEN
                dbms_stats.set_global_prefs('TRACE',0);
                dbms_output.put_line('Trace End');
            END;
        END IF;
    END;
BEGIN
    dbms_output.enable(null);
    IF pct IS NULL OR dop IS NULL THEN
        raise_application_error(-20001,msg);
    END IF;

    IF tnam IS NOT NULL THEN
        IF tnam='.' THEN
            raise_application_error(-20001,'Invalid stat table: .');
        END IF;

        IF instr(tnam,'.')=0 THEN
            town:=sys_context('userenv','current_schema');
        ELSE
            town:=regexp_substr(tnam,'[^\.]+',1,1);
            tnam:=regexp_substr(tnam,'[^\.]+',1,2);
        END IF;

        BEGIN
            EXECUTE IMMEDIATE 'SELECT 1 FROM '||town||'.'||tnam||' WHERE STATID IS NULL AND C4 IS NOT NULL';
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE=-904 THEN
                raise_application_error(-20001,'Invalid stats table: '||town||'.'||tnam);
            ELSE
                raise_application_error(-20001,'No access to target stats table: &t, consider create it with: exec dbms_stats.create_stat_table('''||town||''','''||tnam||''');');
            END IF;
        END;
    END IF;
    IF nam IS NOT NULL THEN
        submit(parse(own,nam,typ,part,pct,dop,'true'));
        RETURN;
    END IF;

    FOR R IN(
        SELECT /*+NO_MERGE(B) NO_MERGE(A) USE_HASH(A B) opt_param('optimizer_dynamic_sampling' 11)*/ *
        FROM   (SELECT OWNER OWN,OBJECT_NAME NAM,OBJECT_TYPE 
                FROM   ALL_OBJECTS
                WHERE  OBJECT_TYPE IN('INDEX','TABLE','MATERIALIZED VIEW')
                UNION 
                SELECT 'SYS',NAME,TYPE 
                FROM   V$FIXED_TABLE 
                WHERE  TYPE='TABLE') B
        JOIN (
            SELECT OWN,
                   REGEXP_REPLACE(NAM,' .*') NAM,
                   CASE WHEN OP LIKE '%INDEX%' THEN 'INDEX' ELSE 'TABLE' END typ,
                   MIN(nvl(regexp_substr(st,'^\d+$')+0,-1)) pst,
                   MIN(nvl(regexp_substr(ed,'^\d+$')+0,1E8)) ped
            FROM (
                SELECT OBJECT_OWNER OWN,
                       OBJECT_NAME NAM,
                       PARTITION_START ST,
                       PARTITION_STOP ED,
                       OPERATION OP
                FROM   GV$SQL_PLAN
                WHERE  sql_id=sq_id
                AND    OBJECT_OWNER IS NOT NULL
                AND    NVL(OBJECT_NAME,':') NOT LIKE ':%'
                UNION ALL
                SELECT OBJECT_OWNER OWN,OBJECT_NAME NAM,PARTITION_START ST,PARTITION_STOP ED,OPERATION
                FROM   DBA_HIST_SQL_PLAN
                WHERE  sql_id=sq_id
                AND    OBJECT_OWNER IS NOT NULL
                AND    NVL(OBJECT_NAME,':') NOT LIKE ':%'
                UNION ALL
                SELECT OBJECT_OWNER OWN,OBJECT_NAME NAM,PARTITION_START ST,PARTITION_STOP ED,OPERATION
                FROM   ALL_SQLSET_PLANS
                WHERE  sql_id=sq_id
                AND    OBJECT_OWNER IS NOT NULL
                AND    NVL(OBJECT_NAME,':') NOT LIKE ':%')
            GROUP BY OWN,
                     REGEXP_REPLACE(NAM,' .*'),
                     CASE WHEN OP LIKE '%INDEX%' THEN 'INDEX' ELSE 'TABLE' END
        ) A USING(OWN,NAM)) LOOP
        part:=NULL;
        stmt:=stmt||'BEGIN '||parse(r.own,r.nam,r.typ,part,pct,dop)||'EXCEPTION WHEN OTHERS THEN NULL;END;'||chr(10);
    END LOOP;
    submit(trim(chr(10) from stmt));
END;
/