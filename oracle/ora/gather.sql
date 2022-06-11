/*[[Gather object/SQL statistics. Usage: @@NAME {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> <percent|0> ["<method_opt>"] [-async|-trace]
    @@NAME <owner>.]<name>[.<partition>: Gather Statistics for target object
    @@NAME <SQL Id>                    : Gather statistics of all objects relative to target SQL
    @@NAME [<schema>] <options>        : Database/schema operations, if the schema is null(.) then for the whole database
        -list                   : Only list the stale objects
        -stale <dop> <pct> [...]: Only gather the stale objects, this option is also available to object/sql
        -auto  <dop> <pct> [...]: Auto gather the stale objects, this option is also available to object/sql


    Other Parameters:
    =================
    <percent>            : The sample percentage(in %) for gathering stats, 0 as default 
    -async               : Create scheduler job to gather in background.
    -trace               : Print gather stats traces
    -noinvalid           : Do not auto-invalid the cursors
    -force               : Force gathering stats even the stats is locked
    -t"[<owner>.]<table>": Save stats into target table, instead of updating object stats
    <method_opt>         : Default as "FOR ALL COLUMNS SIZE AUTO"
         -skew           : Same to "FOR ALL COLUMNS SIZE SKEWONLY"
         -repeat         : Same to "FOR ALL COLUMNS SIZE REPEAT"
         <other>         : Refer to documentation of parameter "method_opt"
    --[[
        &async  : default={0} async={1}
        &trace  : default={0} trace={1}
        &invalid: default={} noinvalid={,no_invalidate=>true}
        &force  : defualt={} force={,force=>true}
        &t      : default={} t={}
        &V4     : default={FOR ALL COLUMNS SIZE AUTO} skew={FOR ALL COLUMNS SIZE SKEWONLY} repeat={FOR ALL COLUMNS SIZE REPEAT}
        &stale  : default={0} stale={1} auto={2}
        &list   : default={0} list={1}
    --]]
]]*/

findobj "&V1" 1 1
set feed off
var CUR REFCURSOR;

DECLARE
    sq_id VARCHAR2(128) := :V1;
    own   VARCHAR2(128) := :object_owner;
    nam   VARCHAR2(128) := :object_name;
    typ   VARCHAR2(128) := :object_type;
    part  VARCHAR2(128) := :object_subname;
    pct   NUMBER        := regexp_substr(:V3,'^[\.0-9]+$');
    dop   INT           := regexp_substr(:V2,'^\d+$');
    opt   VARCHAR2(300) := :V4;
    msg   VARCHAR2(300) := 'PARAMETERS: {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> 0|<percent> -async';
    fmt   VARCHAR2(300) := q'[dbms_stats.gather_%s_stats('%s','%s','%s',%s,options=>'%s',statown=>'%s',stattab=>'%s',degree=>%s&invalid.&force.%s);]';
    stmt  VARCHAR2(32767);
    town  VARCHAR2(128);
    tnam  VARCHAR2(256) := replace(trim(upper(:t)),' '); 
    cnt   INT;
    objs  DBMS_STATS.ObjectTab:=DBMS_STATS.ObjectTab();
    tabs  SYS.ODCIARGDESCLIST:=SYS.ODCIARGDESCLIST();
    FUNCTION parse(own varchar2,nam varchar2,typ varchar2,part varchar2,pct varchar2,dop varchar2,cascade varchar2:='false') RETURN VARCHAR2 IS
    BEGIN
        return utl_lms.format_message(fmt,
                CASE WHEN typ LIKE 'INDEX%' THEN 'index' else 'table' END,
                own,nam,part,pct,'GATHER' ||CASE &stale WHEN 1 THEN ' STALE' WHEN 2 THEN ' AUTO' END,town,tnam,dop,
                CASE when typ NOT LIKE 'INDEX%' THEN 
                    ',block_sample=>true,cascade=>'||cascade||case when opt is not null then ',method_opt=>'''||opt||'''' end
                END
            );
    END;

    PROCEDURE submit(cmd VARCHAR2) IS
        ln    VARCHAR2(1):=chr(10);
        job   VARCHAR2(128);
        c     INT;
    BEGIN
        select count(1) into c
        from   v$sysstat
        where  name like 'cell%elig%pred%offload%'
        and    value>0;
        stmt :=replace(ln||cmd,ln,ln||'    ')||ln;
        IF &async=1 THEN
            stmt :=CASE WHEN c>0 then q'[    execute immediate 'alter session set "_serial_direct_read"=always';]' END
                || REPLACE(REPLACE(q'~
                begin 
                    dbms_stats.set_global_prefs('TRACE',@trace);
                exception when others then null;
                end;
                begin
                    execute immediate q'[alter session set "_px_groupby_pushdown"=off tracefile_identifier='gather_stats']';
                    execute immediate q'[alter session set "_fix_control"='25167306:1']';
                exception when others then null;
                end; ~'
                ||stmt,'            '),'@trace',CASE &trace WHEN 0 THEN 0 ELSE 2+4+8+16+64+1024 END);
            job:=dbms_scheduler.generate_job_name('GATHER_STATS_');
            dbms_scheduler.create_job(job_name   => job,
                                      job_type   => 'PLSQL_BLOCK',
                                      job_action => stmt,
                                      enabled    => TRUE);
            dbms_output.put_line('Schedule job '||job||' is created to run the gathering in background mode. Statement:');
            dbms_output.put_line(stmt);
            RETURN;
        END IF;

        IF c>0 THEN
            execute immediate 'alter session set "_serial_direct_read"=always';
        END IF;
        IF &trace=0 THEN
            stmt := 'BEGIN'||stmt||'END;';
            dbms_output.put_line(stmt);
            EXECUTE IMMEDIATE stmt;
        ELSE
            dbms_output.put_line('Trace Start. Statement:');
            stmt := 'BEGIN'||stmt||'END;';
            dbms_output.put_line(stmt);
            dbms_stats.set_global_prefs('TRACE',1+2+4+8+16+64+1024);
            BEGIN
                EXECUTE IMMEDIATE stmt;
                dbms_stats.set_global_prefs('TRACE',0);
                dbms_output.put_line('Trace End');
            EXCEPTION WHEN OTHERS THEN
                dbms_stats.set_global_prefs('TRACE',0);
                dbms_output.put_line('Trace End');
                raise;
            END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        IF c>0 THEN
            execute immediate 'alter session set "_serial_direct_read"=auto';
        END IF;
        RAISE;
    END;
BEGIN
    dbms_output.enable(null);

    IF sq_id IS NOT NULL AND own IS NULL THEN
        SELECT max(username)
        INTO   own
        FROM   ALL_USERS
        WHERE  upper(username)=upper(sq_id);
    END IF; 

    IF &list=1 AND nam IS NULL THEN
        IF sq_id IS NULL OR own IS NOT NULL THEN
            BEGIN
                DBMS_STATS.FLUSH_DATABASE_MONITORING_INFO;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
            FOR j in 1..2 LOOP
                IF own IS NOT NULL THEN
                    dbms_stats.gather_schema_stats(own,options=>'LIST '||CASE j WHEN 1 THEN 'STALE' ELSE 'AUTO' END,objlist=>objs);
                ELSE
                    dbms_stats.gather_database_stats(options=>'LIST '||CASE j WHEN 1 THEN 'STALE' ELSE 'AUTO' END,objlist=>objs);
                END IF;
                IF objs.count+tabs.count>32767 THEN
                    raise_application_error(-20001,'To many staled objects, operation is cancelled.');
                END IF;
                FOR i IN 1..objs.count LOOP
                    tabs.extend;
                    tabs(tabs.count):=SYS.ODCIARGDESC(j,objs(i).OBJNAME,objs(i).OWNNAME,objs(i).OBJTYPE,objs(i).PARTNAME,objs(i).SUBPARTNAME,NULL);
                END LOOP;
                objs.DELETE;
            END LOOP;

            OPEN :cur FOR
                SELECT ROW_NUMBER() OVER(ORDER BY OWNER,OBJECT_NAME,PART_NAME,SUBPART_NAME) "#",
                       A.*
                FROM(SELECT TABLESCHEMA OWNER,
                            TABLENAME OBJECT_NAME,
                            COLNAME TYPE,
                            TABLEPARTITIONLOWER PART_NAME,
                            TABLEPARTITIONUPPER SUBPART_NAME,
                            MAX(DECODE(ARGTYPE,1,'STALE,'))||MAX(DECODE(ARGTYPE,2,'AUTO')) GATHER_OPTIONS
                     FROM   TABLE(tabs)
                     GROUP  BY TABLESCHEMA,TABLENAME,COLNAME,TABLEPARTITIONLOWER,TABLEPARTITIONUPPER) A
                ORDER BY 1;
            RETURN;
        END IF;
    END IF;

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
    ELSIF &stale>0 AND (own IS NOT NULL OR sq_id IS NULL) THEN
        fmt:=q'[dbms_stats.gather_%s_stats(%s%s,options=>'GATHER %s',block_sample=>true,method_opt=>'%s',statown=>'%s',stattab=>'%s',degree=>%s&invalid.&force.);]';
        fmt:=utl_lms.format_message(fmt,
                CASE WHEN own IS NOT NULL THEN 'schema' ELSE 'database' END,
                CASE WHEN own IS NOT NULL THEN ''''||own||''',' END,
                ''||pct,
                CASE &stale WHEN 1 THEN 'STALE' ELSE 'AUTO' END,
                opt,town,tnam,''||dop);
        submit(fmt);
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

    IF stmt IS NULL THEN
        raise_application_error(-20001,'Cannot find execution plan of target SQL: '||sq_id);
    END IF;
    submit(trim(chr(10) from stmt));
END;
/