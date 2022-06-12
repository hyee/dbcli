/*[[Gather object/SQL statistics. Usage: @@NAME {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> <percent|0> ["<method_opt>"] [-async|-trace]
    @@NAME <owner>.]<name>[.<partition>: Gather Statistics for target object
    @@NAME <SQL Id>                    : Gather statistics of all objects relative to target SQL
    @@NAME [<schema>] <options>        : Database/schema operations, if the schema is null(.) then for the whole database
        -list  [-f"<key>"] [-nopart]   : Only list the stale objects, 
                                         -f"<keyword>": used to only list matched objects
                                         -nopart      : don't list partition
        -stale <dop> <pct> [...]       : Only gather the stale objects, this option is also available to object/sql
        -auto  <dop> <pct> [...]       : Auto gather the stale objects, this option is also available to object/sql

    Other Parameters:
    =================
    <percent>            : The sample percentage(in %) for gathering stats, 0 as default 
    -row                 : If sample percentage < 100%, then random sample by row, instead of block
    -async               : Create scheduler job to gather in background.
    -trace               : Print gather stats traces
    -noinvalid           : Do not auto-invalid the cursors
    -force               : Force gathering stats even the stats is locked
    -t"[<owner>.]<table>": Save stats into target table, instead of updating object stats
    <method_opt>         : Default as "FOR ALL COLUMNS SIZE AUTO"
         -skew           : Same to "FOR ALL COLUMNS SIZE SKEWONLY"
         -repeat         : Same to "FOR ALL COLUMNS SIZE REPEAT"
         <other>         : Refer to documentation of parameter "method_opt"
    -print               : Print gather stats command only, don't actually execute

    Examples:
    =========
    @@NAME sys.obj$      1 0            :gather SYS.OBJ$ in sync mode
    @@NAME dd99a44gnta5s 4 100 -async   :gather all objects relative to sql dd99a44gnta5s with dop 4 in background
    @@NAME dd99a44gnta5s 4 100 -stale   :gather all objects relative to sql dd99a44gnta5s with dop 4 with "GATHER STALE" mode
    @@NAME dd99a44gnta5s 4 100 -print   :only print the commands of gathering all objects relative to sql dd99a44gnta5s with dop 4
    @@NAME SYS -list                    :list all stale SYS objects 
    @@NAME -list  -F"O"                 :list all stale database objects whose name/type/partition contains string 'O'
    @@NAME SYS 8 0 -async -auto         :gather all SYS stale object in "GATHER AUTO" mode with dop 8 in background
    @@NAME .   8 0 -async -stale        :gather all stale object in "GATHER STALE" mode with dop 8 in background

    --[[
        &async  : default={0} async={1}
        &trace  : default={0} trace={1}
        &invalid: default={} noinvalid={,no_invalidate=>true}
        &force  : defualt={} force={,force=>true}
        &t      : default={} t={}
        &V4     : default={FOR ALL COLUMNS SIZE AUTO} skew={FOR ALL COLUMNS SIZE SKEWONLY} repeat={FOR ALL COLUMNS SIZE REPEAT}
        &stale  : default={0} stale={1} auto={2}
        &list   : default={0} list={1}
        &filter : default={} f={}
        &exec   : default={true} print={false}
        &nopart : default={0} nopart={1}
        &block  : default={true} row={false}
    --]]
]]*/

findobj "&V1" 1 1
set feed off
COL BYTES FOR KMG2
COL BLOCKS,EXTENTS FOR TMB2
var CUR REFCURSOR;

DECLARE
    sq_id VARCHAR2(128) := :V1;
    own   VARCHAR2(128) := :object_owner;
    nam   VARCHAR2(128) := :object_name;
    typ   VARCHAR2(128) := :object_type;
    part  VARCHAR2(128) := :object_subname;
    key   VARCHAR2(128) := trim('%' from upper(:filter));
    pct   NUMBER        := regexp_substr(:V3,'^[\.0-9]+$');
    dop   INT           := regexp_substr(:V2,'^\d+$');
    opt   VARCHAR2(300) := :V4;
    msg   VARCHAR2(300) := 'PARAMETERS: {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> 0|<percent> -async';
    fmt   VARCHAR2(300) := q'[dbms_stats.gather_%s_stats('%s','%s','%s',%s%s,statown=>'%s',stattab=>'%s',degree=>%s&invalid.&force.%s);]';
    stmt  VARCHAR2(32767);
    town  VARCHAR2(128);
    tnam  VARCHAR2(256) := replace(trim(upper(:t)),' '); 
    cnt   INT:=0;
    val   INT;
    HV    VARCHAR2(30);
    TYPE  T_LIST IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(30);
    lst   T_LIST;
    objs  DBMS_STATS.ObjectTab:=DBMS_STATS.ObjectTab();
    fil   DBMS_STATS.ObjectTab:=DBMS_STATS.ObjectTab();
    tabs  SYS.ODCIARGDESCLIST:=SYS.ODCIARGDESCLIST();
    FUNCTION parse(own varchar2,nam varchar2,typ varchar2,part varchar2,pct varchar2,dop varchar2,cascade varchar2:='false') RETURN VARCHAR2 IS
    BEGIN
        return utl_lms.format_message(fmt,
                CASE WHEN typ LIKE 'INDEX%' THEN 'index' else 'table' END,
                own,nam,part,pct,
                CASE WHEN DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.RELEASE>13 THEN 
                    ',options=>''GATHER' ||CASE &stale WHEN 1 THEN ' STALE''' WHEN 2 THEN ' AUTO''' END 
                END,
                town,tnam,dop,
                CASE when typ NOT LIKE 'INDEX%' THEN 
                    ',block_sample=>&block,cascade=>'||cascade||case when opt is not null then ',method_opt=>'''||opt||'''' end
                END
            );
    END;

    PROCEDURE submit(cmd VARCHAR2) IS
        ln    VARCHAR2(1):=chr(10);
        job   VARCHAR2(128);
        c     INT;
        tim   NUMBER;
    BEGIN
        select count(1) into c
        from   v$sysstat
        where  name like 'cell%elig%pred%offload%'
        and    value>0;
        stmt :=replace(ln||cmd,ln,ln||'    ')||ln;
        IF NOT &exec THEN
            dbms_output.put_line('Print ONLY the statements:');
            dbms_output.put_line('==========================');
        ElSE
            tim:= dbms_utility.get_time;
            dbms_output.put_line('Executed below statements:');
            dbms_output.put_line('==========================');
        END IF;
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
            IF &exec THEN
                job:=dbms_scheduler.generate_job_name('GATHER_STATS_');
                dbms_scheduler.create_job(job_name   => job,
                                          job_type   => 'PLSQL_BLOCK',
                                          job_action => stmt,
                                          enabled    => TRUE);
                dbms_output.put_line('Schedule job '||job||' is created to run the gathering in background mode. Statement:');
            END IF;
            dbms_output.put_line(stmt);
            RETURN;
        END IF;

        IF c>0 THEN
            execute immediate 'alter session set "_serial_direct_read"=always';
        END IF;

        stmt := 'BEGIN'||stmt||'END;';
        IF NOT &exec THEN
            dbms_output.put_line(stmt);
        ELSIF &trace=0 THEN
            dbms_output.put_line(stmt);
            EXECUTE IMMEDIATE stmt;
        ELSE
            dbms_output.put_line('Trace Start. Statement:');
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
        IF c>0 THEN
            execute immediate 'alter session set "_serial_direct_read"=auto';
        END IF;
        IF tim IS NOT NULL THEN
            dbms_output.put_line('==========================');
            DBMS_OUTPUT.PUT_LINE('Operation done in '||round((dbms_utility.get_time-tim)/100,2)||' secs.');
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

            IF key IS NOT NULL THEN
                sq_id := '%'||key||'%';
                fil.extend(4);
                fil(1).ownname:=sq_id;
                fil(2).objname:=sq_id;
                fil(3).partname:=sq_id;
                fil(4).subpartname:=sq_id;
                IF length(key)<6 THEN
                    fil.extend;
                    fil(5).objtype:=key||'%';
                END IF;
            ELSE
                fil:=NULL;
            END IF;
            FOR j in 1..3 LOOP
                IF own IS NOT NULL THEN
                    dbms_stats.gather_schema_stats(own,options=>'LIST '||CASE j WHEN 1 THEN 'AUTO' WHEN 2 THEN 'STALE' ELSE 'EMPTY' END,objlist=>objs,obj_filter_list=>fil);
                ELSE
                    dbms_stats.gather_database_stats(options=>'LIST '||CASE j WHEN 1 THEN 'AUTO' WHEN 2 THEN 'STALE' ELSE 'EMPTY' END,objlist=>objs,obj_filter_list=>fil);
                END IF;
                
                FOR i IN 1..objs.count LOOP
                    SELECT TO_CHAR(SYS_OP_COMBINED_HASH(objs(i).OBJNAME,objs(i).OWNNAME,objs(i).OBJTYPE,
                                       CASE WHEN &nopart=1 then '' ELSE objs(i).PARTNAME END,
                                       CASE WHEN &nopart=1 then '' ELSE objs(i).SUBPARTNAME END),'TM9')
                    INTO   hv
                    FROM   DUAL;
                    IF lst.exists(hv) THEN
                        IF lst(hv)<=1000 THEN
                            val := tabs(lst(hv)).argtype;
                            tabs(lst(hv)).argtype:=val-bitand(val,power(2,j-1))+power(2,j-1);
                            IF (j=1 OR val=1) AND &nopart=1 THEN
                                tabs(lst(hv)).cardinality:=tabs(lst(hv)).cardinality+1;
                                tabs(lst(hv)).TABLEPARTITIONUPPER:=NULL;
                                tabs(lst(hv)).TABLEPARTITIONLOWER:=NULL;
                            END IF;
                        END IF;
                    ELSE
                        cnt := cnt + 1;
                        lst(hv):=cnt;
                        IF cnt<=1000 THEN
                            tabs.extend;
                            tabs(cnt):=SYS.ODCIARGDESC(power(2,j-1),
                                                         objs(i).OBJNAME,
                                                         objs(i).OWNNAME,
                                                         substr(objs(i).OBJTYPE,1,6),
                                                         objs(i).PARTNAME,
                                                         objs(i).SUBPARTNAME,
                                                         1);
                        END IF;
                    END IF;
                END LOOP;
                objs.DELETE;
            END LOOP;

            DBMS_OUTPUT.PUT_LINE('Totally '||cnt||' stale objects found');
            DBMS_OUTPUT.PUT_LINE('===================================');
            OPEN :cur FOR
                SELECT ROW_NUMBER() OVER(ORDER BY OWNER,OBJECT_NAME,PART_NAME,SUBPART) "#",
                       A.*
                FROM(SELECT /*+NO_EXPAND USE_HASH(A B) opt_param('optimizer_dynamic_sampling' 5)*/
                            TABLESCHEMA OWNER,
                            TABLENAME OBJECT_NAME,
                            COLNAME TYPE,
                            NVL(TABLEPARTITIONLOWER,CASE WHEN CARDINALITY>1 THEN CARDINALITY|| ' Segments' ELSE TABLEPARTITIONLOWER END) PART_NAME,
                            TABLEPARTITIONUPPER SUBPART,
                            DECODE(BITAND(ARGTYPE,4),4,'EMPTY,')||
                            DECODE(BITAND(ARGTYPE,2),2,'STALE,')||
                            DECODE(BITAND(ARGTYPE,1),1,'AUTO') GATHER_OPTIONS,
                            SUM(BYTES) BYTES,
                            SUM(BLOCKS) BLOCKS,
                            SUM(EXTENTS) EXTENTS
                     FROM   TABLE(tabs) A
                     LEFT   JOIN  DBA_SEGMENTS B
                     ON     A.TABLESCHEMA=B.OWNER
                     AND    A.TABLENAME=B.SEGMENT_NAME
                     AND    B.SEGMENT_TYPE LIKE A.COLNAME||'%'
                     WHERE  B.OWNER IS NULL OR COALESCE(TABLEPARTITIONUPPER,TABLEPARTITIONLOWER,' ') IN(' ',B.PARTITION_NAME)
                     GROUP BY TABLESCHEMA,TABLENAME,COLNAME,TABLEPARTITIONUPPER,ARGTYPE,
                              NVL(TABLEPARTITIONLOWER,CASE WHEN CARDINALITY>1 THEN CARDINALITY|| ' Segments' ELSE TABLEPARTITIONLOWER END)) A
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
        fmt:=q'[dbms_stats.gather_%s_stats(%s%s,options=>'GATHER %s',gather_fixed=>true,block_sample=>&block,method_opt=>'%s',statown=>'%s',stattab=>'%s',degree=>%s&invalid.&force.);]';
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