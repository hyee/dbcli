/*[[Gather object/SQL statistics. Usage: @@NAME {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> <percent|0> ["<method_opt>"] [-async|-trace]
    <percent>: The sample percentage(in %) for gathering stats, 0 as default 
    -async   : Create scheduler job to gather in background.
    -trace   : Trace gather stats
    --[[
        @ARGS: 3
        &async: default={-1} async={0} trace={2}
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
    fmt   VARCHAR2(300) := q'[dbms_stats.gather_%s_stats('%s','%s','%s',%s,degree=>%s%s);]';
    stmt  VARCHAR2(32767);
    function parse(own varchar2,nam varchar2,typ varchar2,part varchar2,pct varchar2,dop varchar2,cascade varchar2:='false') RETURN VARCHAR2 IS
    BEGIN
        return utl_lms.format_message(fmt,
                CASE WHEN typ LIKE 'INDEX%' THEN 'index' else 'table' END,
                own,nam,part,pct,dop,
                CASE when typ NOT LIKE 'INDEX%' THEN 
                    ',block_sample=>true,cascade=>'||cascade||case when opt is not null then ',method_opt=>'''||opt||'''' end
                END
            );
    END;

    procedure submit(cmd VARCHAR2) IS
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
            dbms_output.put_line('Trace Start');
        END IF;
        
    END;
BEGIN
    IF pct IS NULL OR dop IS NULL THEN
        raise_application_error(-20001,msg);
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
                SELECT OBJECT_OWNER OWN,OBJECT_NAME NAM,PARTITION_START ST,PARTITION_STOP ED,OPERATION OP
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
        stmt:=stmt||'BEGIN '||parse(r.own,r.nam,r.typ,'',pct,dop)||'EXCEPTION WHEN OTHERS THEN NULL;END;'||chr(10);
    END LOOP;
    submit(trim(chr(10) from stmt));
END;
/