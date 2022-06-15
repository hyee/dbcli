/*[[Gather object/SQL/db/schema statistics. Usage: @@NAME {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> [<percent|0>] ["<method_opt>"] [-async|-trace]
    @@NAME <owner>.]<name>[.<partition>]: Gather Statistics for target object
    @@NAME <SQL Id>                     : Gather statistics of all objects relative to target SQL
    @@NAME [<schema>] <options>         : Database/schema operations, if the schema is null(.) then for the whole database.
                                              One of -list/-auto/-stale/-empty must be specified for database/schema mode

    Other Parameters:
    =================
    <percent>            : The sample percentage(in %) for gathering stats, 0 as default 
    -list                : List the empty/stale/auto objects
         -f"<key>"       : Only list matched objects whose name contains <key>, such as owner/name/partition
         -nopart         : Don't list partition, sum up to top object level instead
    -auto                : Gather stats with 'GATHER AUTO'
    -empty               : Gather stats with 'GATHER EMPTY'
    -stale               : Gather stats with 'GATHER STALE'
    -row                 : If sample percentage < 100%, then random sample by row, instead of block
    -async               : Create scheduler job to gather in background.
    -trace               : Print gather stats traces
    -noinvalid           : Do not auto-invalidate the relative cursors
    -force               : Force gathering stats even the stats is locked
    <method_opt>         : Default as "FOR ALL COLUMNS SIZE AUTO"
         -skew           : Same to "FOR ALL COLUMNS SIZE SKEWONLY"
         -repeat         : Same to "FOR ALL COLUMNS SIZE REPEAT"
         <other>         : Refer to documentation of parameter "method_opt"
    -pending             : Gather pending stats. Not avaible to schema/database level
    -publish             : Publish pending stats on target object/SQL
    -unpend              : Clear pending stats
    -print               : Print gather stats command only, don't actually execute
    -t"[<owner>.]<table>": Save stats into target table, instead of updating object stats

    Examples:
    =========
    @@NAME sys.obj$      1 0            :gather SYS.OBJ$ in sync mode
    @@NAME dd99a44gnta5s 4 100 -async   :gather all objects relative to sql dd99a44gnta5s with dop 4 in background
    @@NAME dd99a44gnta5s 4 100 -stale   :gather all objects relative to sql dd99a44gnta5s with dop 4 with "GATHER STALE" mode
    @@NAME dd99a44gnta5s 4 100 -print   :only print the commands of gathering all objects relative to sql dd99a44gnta5s with dop 4
    @@NAME SYS -list                    :list all stale SYS objects 
    @@NAME -list  -F"O"                 :list all stale database objects whose name/type/partition contains string 'O'
    @@NAME SYS 8 0 -async -auto         :gather all SYS empty/stale object in "GATHER AUTO" mode with dop 8 in background
    @@NAME .   8 0 -async -stale        :gather all stale object in "GATHER STALE" mode with dop 8 in background

    --[[
        &async  : default={0} async={1}
        &trace  : default={0} trace={1}
        &invalid: default={} noinvalid={,no_invalidate=>true}
        &force  : defualt={} force={,force=>true}
        &t      : default={} t={}
        &V4     : default={} skew={FOR ALL COLUMNS SIZE SKEWONLY} repeat={FOR ALL COLUMNS SIZE REPEAT}
        &stale  : default={} stale={ STALE} auto={ AUTO} empty={ EMPTY}
        &list   : default={0} list={1}
        &filter : default={} f={}
        &exec   : default={true} print={false}
        &nopart : default={0} nopart={1}
        &block  : default={true} row={false}
        &pending: default={0} pending={1} publish={2} unpend={3}
        @check_access_seg: dba_segments={dba_segments} default={(select user owner,a.* from user_segments a)}
        @check_access_fix: {
            sys.x$kqfdt={sys.x$kqfdt}
            --SELECT REGEXP_REPLACE(REPLACE(DBMS_XMLGEN.GETXMLTYPE('SELECT KQFDTNAM A,KQFDTEQU B FROM sys.x$kqfdt ORDER BY 1'),'ROW>','R>'),'(<R>|</A>|</B>)\s+','\1') FROM DUAL;
            default={(select * FROM XMLTABLE('//R' PASSING XMLTYPE('<ROWSET>
     <R><A>X$KSLLTR_CHILDREN</A><B>X$KSLLTR</B></R>
     <R><A>X$KSLLTR_PARENT</A><B>X$KSLLTR</B></R>
     <R><A>X$KSLLTR_OSP</A><B>X$KSLLTR</B></R>
     <R><A>X$KSLWSC_OSP</A><B>X$KSLWSC</B></R>
     <R><A>X$KCVFHONL</A><B>X$KCVFH</B></R>
     <R><A>X$KCVFHMRR</A><B>X$KCVFH</B></R>
     <R><A>X$KCVFHALL</A><B>X$KCVFH</B></R>
     <R><A>X$KGLTABLE</A><B>X$KGLOB</B></R>
     <R><A>X$KGLBODY</A><B>X$KGLOB</B></R>
     <R><A>X$KGLTRIGGER</A><B>X$KGLOB</B></R>
     <R><A>X$KGLINDEX</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCLUSTER</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCURSOR</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCURSOR_CHILD_SQLID</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCURSOR_CHILD_SQLIDPH</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCURSOR_CHILD</A><B>X$KGLOB</B></R>
     <R><A>X$KGLCURSOR_PARENT</A><B>X$KGLOB</B></R>
     <R><A>X$KGLSQLTXL</A><B>X$KGLOB</B></R>
     <R><A>X$ALL_KQLFXPL</A><B>X$KQLFXPL</B></R>
     <R><A>X$KKSSQLSTAT_PLAN_HASH</A><B>X$KKSSQLSTAT</B></R>
     <R><A>X$ZASAXTD1</A><B>X$ZASAXTAB</B></R>
     <R><A>X$ZASAXTD2</A><B>X$ZASAXTAB</B></R>
     <R><A>X$ZASAXTD3</A><B>X$ZASAXTAB</B></R>
     <R><A>X$JOXFS</A><B>X$JOXFT</B></R>
     <R><A>X$JOXFC</A><B>X$JOXFT</B></R>
     <R><A>X$JOXFR</A><B>X$JOXFT</B></R>
     <R><A>X$JOXFD</A><B>X$JOXFT</B></R>
     <R><A>X$JOXOBJ</A><B>X$JOXFT</B></R>
     <R><A>X$JOXSCD</A><B>X$JOXFT</B></R>
     <R><A>X$JOXRSV</A><B>X$JOXFT</B></R>
     <R><A>X$JOXREF</A><B>X$JOXFT</B></R>
     <R><A>X$JOXDRC</A><B>X$JOXFT</B></R>
     <R><A>X$JOXDRR</A><B>X$JOXFT</B></R>
     <R><A>X$JOXMOB</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMIF</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMIC</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMFD</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMMD</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMAG</A><B>X$JOXFM</B></R>
     <R><A>X$JOXMEX</A><B>X$JOXFM</B></R>
     <R><A>X$ALL_ASH</A><B>X$ASH</B></R>
     <R><A>X$ALL_KESWXMON</A><B>X$KESWXMON</B></R>
     <R><A>X$ALL_KESWXMON_PLAN</A><B>X$KESWXMON_PLAN</B></R>
    </ROWSET>') COLUMNS KQFDTNAM VARCHAR2(50) PATH 'A',KQFDTEQU VARCHAR2(50) PATH 'B'))
    }}
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
    schem VARCHAR2(128);
    typ   VARCHAR2(128) := :object_type;
    part  VARCHAR2(128) := :object_subname;
    key   VARCHAR2(128) := trim('%' from upper(:filter));
    pct   NUMBER        := nvl(0+regexp_substr(:V3,'^[\.0-9]+$'),0);
    dop   INT           := regexp_substr(:V2,'^\d+$');
    opt   VARCHAR2(300) := trim(:V4);
    msg   VARCHAR2(300) := 'PARAMETERS: {{[<owner>.]<name>[.<partition>]} | <SQL Id>} <degree> <percent> -async';
    fmt   VARCHAR2(300) := q'[dbms_stats.gather_%s_stats('%s','%s','%s',%s%s%s,degree=>%s&invalid.&force.%s);]';
    pub   VARCHAR2(300) := q'[dbms_stats.publish_pending_stats('%s','%s'&invalid.);]';
    cls   VARCHAR2(300) := q'[dbms_stats.delete_pending_stats('%s','%s');]';
    stmt  VARCHAR2(32767);
    town  VARCHAR2(128);
    tnam  VARCHAR2(512) := replace(trim(upper(:t)),' '); 
    cnt   INT:=0;
    val   INT;
    cnt1  INT;
    segs  INT;
    HV    VARCHAR2(30);
    TYPE  T_LIST IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(30);
    lst   T_LIST;
    objs  DBMS_STATS.ObjectTab:=DBMS_STATS.ObjectTab();
    fil   DBMS_STATS.ObjectTab:=DBMS_STATS.ObjectTab();
    tabs  SYS.ODCIARGDESCLIST:=SYS.ODCIARGDESCLIST();
    pending VARCHAR2(32767);
    CURSOR cur IS
        SELECT /*+NO_MERGE(B) NO_MERGE(A) USE_HASH(A B) opt_param('optimizer_dynamic_sampling' 11)*/ *
        FROM   (SELECT OWNER OWN,OBJECT_NAME NAM,OBJECT_TYPE,NULL RNAM
                FROM   ALL_OBJECTS
                WHERE  OBJECT_TYPE IN('INDEX','TABLE','MATERIALIZED VIEW')
                UNION 
                SELECT 'SYS',A.NAME,TYPE,B.KQFDTEQU RNAM
                FROM   V$FIXED_TABLE A,&check_access_fix B
                WHERE  A.TYPE='TABLE'
                AND    A.NAME=B.KQFDTNAM(+)) B
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
        ) A USING(OWN,NAM);

    FUNCTION parse(own varchar2,nam varchar2,typ varchar2,part varchar2,pct varchar2,dop varchar2,cascade varchar2:='false') RETURN VARCHAR2 IS
        rtn VARCHAR2(2000);
    BEGIN
        rtn:=utl_lms.format_message(fmt,
                CASE WHEN typ LIKE 'INDEX%' THEN 'index' else 'table' END,
                own,nam,part,pct,
                CASE WHEN typ NOT LIKE 'INDEX%' AND DBMS_DB_VERSION.VERSION+DBMS_DB_VERSION.RELEASE>13 THEN 
                    ',options=>''GATHER&stale'''
                END,
                tnam,dop,
                CASE WHEN typ NOT LIKE 'INDEX%' THEN 
                    ',block_sample=>&block,cascade=>'||cascade||opt
                END);
        IF &pending=1 AND typ NOT LIKE 'INDEX%' AND NOT(own='SYS' AND nam LIKE 'X$%') THEN
            pending:=pending||utl_lms.format_message(q'[dbms_stats.set_table_prefs('%s','%s','publish','false');]',own,nam)||chr(10);
        END IF;
        RETURN rtn;
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
        stmt :=pending||cmd;
        IF pending IS NOT NULL THEN 
            stmt:='BEGIN'||ln||stmt||ln||'EXCEPTION WHEN OTHERS THEN err:=SQLERRM; END;';
            stmt:=stmt||ln||replace(pending,q'['false');]',q'['true');]')||ln
                  ||'IF err IS NOT NULL THEN raise_application_error(-20001,err); END IF;';
        END IF;
        stmt :=replace(ln||stmt,ln,ln||'    ')||ln;
        IF NOT &exec THEN
            dbms_output.put_line('Print ONLY the statements:');
            dbms_output.put_line('==========================');
        ElSE
            tim:= dbms_utility.get_time;
            dbms_output.put_line('Executed below statements:');
            dbms_output.put_line('==========================');
        END IF;
        IF &async=1 THEN
            stmt :=REPLACE(REPLACE(q'~
                declare err VARCHAR2(500); begin
                begin 
                    dbms_stats.set_global_prefs('TRACE',@trace);
                exception when others then null;
                end;
                begin
                    execute immediate q'[alter session set tracefile_identifier='gather_stats']';
                    execute immediate q'[alter session set "_fix_control"='25167306:1']';
                exception when others then null;
                end; ~'
                ||CASE WHEN c>0 then ln||q'[    execute immediate 'alter session set "_serial_direct_read"=always';]' END
                ||stmt||ln||'    end;','            '),'@trace',CASE &trace WHEN 0 THEN 0 ELSE 2+4+8+16+64+1024 END);
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

        stmt := 'DECLARE err VARCHAR2(500);BEGIN'||stmt||'END;';
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
            dbms_output.put_line('Operation done in '||round((dbms_utility.get_time-tim)/100,2)||' secs.');
            IF &pending=1 THEN
                dbms_output.put_line('Consider set optimizer_use_pending_statistics=true to test pending stats');
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        IF c>0 THEN
            execute immediate 'alter session set "_serial_direct_read"=auto';
        END IF;
        RAISE;
    END;
BEGIN
    dbms_output.enable(null);
    IF opt is not null then 
        opt := ',method_opt=>'''||opt||'''';
    END IF;
    IF sq_id IS NOT NULL AND own IS NULL THEN
        SELECT max(username)
        INTO   schem
        FROM   ALL_USERS
        WHERE  upper(username)=upper(sq_id);
    END IF; 

    IF &list=1 THEN
        BEGIN
            DBMS_STATS.FLUSH_DATABASE_MONITORING_INFO;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        IF schem IS NULL AND sq_id IS NOT NULL THEN
            IF nam IS NOT NULL THEN
                fil.extend;
                fil(1).ownname     := own;
                fil(1).objname     := nam;
                fil(1).objtype     := regexp_substr(typ,'\S+');
                fil(1).partname    := CASE WHEN typ LIKE '%SUBPART%' THEN '' ELSE PART END;
                fil(1).subpartname := CASE WHEN typ LIKE '%SUBPART%' THEN PART END;
            ELSE
                FOR r IN cur LOOP
                    fil.extend;
                    fil(fil.count).ownname     := r.own;
                    fil(fil.count).objname     := nvl(r.rnam,r.nam);
                    fil(fil.count).objtype     := CASE WHEN r.typ LIKE 'INDEX%' THEN 'INDEX' ELSE 'TABLE' END;
                END LOOP;
                IF fil.count=0 THEN
                    raise_application_error(-20001,'Cannot find matched objects for SQL: '||sq_id);
                END IF;
            END IF;
        ELSIF key IS NOT NULL THEN
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
            IF schem IS NOT NULL THEN
                dbms_stats.gather_schema_stats(schem,options=>'LIST '||CASE j WHEN 1 THEN 'AUTO' WHEN 2 THEN 'STALE' ELSE 'EMPTY' END,objlist=>objs,obj_filter_list=>fil);
            ELSE
                dbms_stats.gather_database_stats(options=>'LIST '||CASE j WHEN 1 THEN 'AUTO' WHEN 2 THEN 'STALE' ELSE 'EMPTY' END,objlist=>objs,obj_filter_list=>fil);
            END IF;
            
            cnt1:=objs.count;
            IF j=1 THEN
                segs:=cnt1;
            END IF;
            FOR i IN 1..cnt1 LOOP
                SELECT TO_CHAR(SYS_OP_COMBINED_HASH(objs(i).OBJNAME,objs(i).OWNNAME,objs(i).OBJTYPE,
                                   CASE WHEN &nopart=1 then '' ELSE objs(i).PARTNAME END,
                                   CASE WHEN &nopart=1 then '' ELSE objs(i).SUBPARTNAME END),'TM9')
                INTO   hv
                FROM   DUAL;
                IF lst.exists(hv) THEN
                    IF lst(hv)<=1000 THEN
                        val := tabs(lst(hv)).argtype;
                        val := val-bitand(val,power(2,j-1))+power(2,j-1);
                        tabs(lst(hv)).argtype:=val;
                        IF &nopart=1 AND val=bitand(val,power(2,j-1)) THEN
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

        DBMS_OUTPUT.PUT_LINE(cnt||' empty/stale objects('||segs||' segments) found');
        DBMS_OUTPUT.PUT_LINE('===============================================');
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
                 LEFT   JOIN  &check_access_seg B
                 ON     A.TABLESCHEMA=B.OWNER
                 AND    A.TABLENAME=B.SEGMENT_NAME
                 AND    B.SEGMENT_TYPE LIKE A.COLNAME||'%'
                 WHERE  B.OWNER IS NULL OR COALESCE(TABLEPARTITIONUPPER,TABLEPARTITIONLOWER,' ') IN(' ',B.PARTITION_NAME)
                 GROUP BY TABLESCHEMA,TABLENAME,COLNAME,TABLEPARTITIONUPPER,ARGTYPE,
                          NVL(TABLEPARTITIONLOWER,CASE WHEN CARDINALITY>1 THEN CARDINALITY|| ' Segments' ELSE TABLEPARTITIONLOWER END)) A
            ORDER BY 1;
        RETURN;
    END IF;

    IF (pct=0 AND :V3 IS NOT NULL OR dop IS NULL) and &pending!=2 THEN
        raise_application_error(-20001,msg);
    ELSIF key IS NOT NULL THEN
        raise_application_error(-20001,'Option -f"<filter>" is only used to list database/schema stale stats');
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
        tnam := utl_lms.format_message(q'[,statown=>'%s',stattab=>'%s']',town,tnam);
    END IF;

    IF nam IS NOT NULL THEN
        IF own='SYS' AND nam LIKE 'X$%' THEN
            SELECT NVL(MAX(KQFDTEQU),nam) INTO nam
            FROM   &check_access_fix
            WHERE  KQFDTNAM=nam;
        END IF;
        IF &pending<2 THEN
            submit(parse(own,nam,typ,part,pct,dop,'true'));
        ELSIF typ NOT LIKE 'INDEX%' THEN
            submit(utl_lms.format_message(CASE &pending WHEN 2 THEN pub ELSE cls END,own,nam));
        END IF;
        RETURN;
    ELSIF :stale IS NOT NULL AND (schem IS NOT NULL OR sq_id IS NULL) THEN
        IF &pending>0 THEN
            raise_application_error(-20001,'Option -pending/-publish is not available to gathering database/schema stats');
        END IF;
        fmt:=q'[dbms_stats.gather_%s_stats(%s%s,options=>'GATHER&stale',gather_fixed=>true,block_sample=>&block%s%s,degree=>%s&invalid.&force.);]';
        fmt:=utl_lms.format_message(fmt,
                CASE WHEN schem IS NOT NULL THEN 'schema' ELSE 'database' END,
                CASE WHEN schem IS NOT NULL THEN ''''||schem||''',' END,
                ''||pct,
                opt,
                tnam,''||dop);
        submit(fmt);
        RETURN;
    END IF;

    FOR R IN cur LOOP
        part:=NULL;
        IF &pending<2 THEN
            stmt:=stmt||parse(r.own,nvl(r.rnam,r.nam),r.typ,part,pct,dop)||chr(10);
        ELSIF r.typ NOT LIKE 'INDEX%' AND NOT(r.own='SYS' AND r.nam LIKE 'X$%') THEN
            stmt:=stmt||utl_lms.format_message(CASE &pending WHEN 2 THEN pub ELSE cls END,r.own,nvl(r.rnam,r.nam))||chr(10);
        END IF;
    END LOOP;

    IF stmt IS NULL THEN
        raise_application_error(-20001,'Cannot find matched objects for SQL: '||sq_id);
    END IF;
    submit(trim(chr(10) from stmt));
END;
/