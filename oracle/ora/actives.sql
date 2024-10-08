/*[[
    Show active sessions. Usage: @@NAME [sid|wt|ev|sql|<col>] [-s|-p|-b|-o|-m] {[-f"<filter>"|-text"<keyword>"|-u|-i] [-f2"<filter>"|-u2|-i2]}
    
    Options(options within same group cannot combine, i.e. "@@NAME -u -i" is illegal, use "@@NAME -u -i2" instead):
        Filter options#1:
            -u   : Only show the sessions of current_schema
            -i   : Exclude the idle events
            -f   : Customize the filter, i.e.: -f"inst_id=1"
            -sql : Find sql with keyword
        Field options:  Field options can be followed by other customized fields. ie: -s,p1raw
            -s  : Show related procedures and lines(default)
            -p  : Show p1/p2/p2text/p3
            -b  : Show blocking sessions and waiting objects
            -o  : Show OS user id/machine/program/etc
            -m  : Show SQL Mornitor report(gv$sql_monitor)
            -c  : show consumer group and queue duration
        Sorting options: the '-' symbole is optional
           -sid : sort by sid(default)
           -wt  : sort by wait time
           -sql : sort by sql text
           -ev  : sort by event
            -o  : together with the '-o' option above, sort by logon_time
           <col>: field in v$session
           -cpu : together with option '-m', sort metric by cpu
           -io  : together with option '-m', sort metric by io
           -log : together with option '-m', sort metric by logical reads
        Other Options:
           -new: Use style#2 SQL(possibly slower)
    --[[
        &fields : {
               s={coalesce(nullif(program_name,'0'),'['||regexp_replace(regexp_replace(nvl(a.module,a.program),' *\(.*\)$'),'.*@')||'('||osuser||')]') PROGRAM,program_line# line# &0},
               o={schemaname schema,osuser,logon_time,regexp_replace(machine,'(\..*|^.*\\)') machine,regexp_replace(program,' *\(.*') program &0},
               p={p1,p2,p2text,p3 &0},
               b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
                 (SELECT OBJECT_NAME FROM &CHECK_ACCESS_OBJ WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2) WAITING_OBJ,
                 ROW_WAIT_BLOCK# WAIT_BLOCK# &0},
               c={USERNAME,RESOURCE_CONSUMER_GROUP RSRC_GROUP,CURRENT_QUEUE_DURATION QUEUED &0}
            }
        &V1 :   sid={''||sid},wt={wait_secs desc},ev={event},sql={sql_text},o={logon_time}
        &fil1: {
            default={NOT(wait_class='Idle' and (event like 'SQL*%' or event LIKE 'Streams%'))}
            f={}
            u={schemaname=nvl(upper('&0'),sys_context('userenv','current_schema'))}
            i={wait_class!='Idle' &0}
        }
        
        &fil2: {
            default={}
            sql={AND 1=1}
            f={AND &0}
            i={AND &fil1}
            u={AND &fil1}
        }
        &style: default={0} new={1}
        &text: default={}  sql={AND upper(sql_fulltext) like upper(q'~%&0%~')}
        &ouj : default={(+)} sql={/**/}  
        &smen : default={0}, m={&CHECK_ACCESS_M}
        &ord  : default={} cpu={"CPU%" desc nulls last,} io={"Physical|Reads" desc nulls last,} log={"Logical|Reads" desc nulls last,}
        @COST : 11.0={86400*(sysdate-sql_exec_start)},10.0={sql_secs}
        @CHECK_ACCESS_OBJ: dba_objects={dba_objects},all_objects={all_objects}
        @CHECK_ACCESS_PX11: {
            v$px_session={v$px_session},
            default={(select null sid,null qcinst_id,null qcsid from dual where 1=2)}
        }
        @CHECK_ACCESS_PRO11: {
            v$process={(select addr,spid from v$process)},
            default={(select null addr,null spid from dual where 1=2)}
        }
        @CHECK_ACCESS_SQL: gv$sql={gv$sql}, v$sql={(select /*+merge*/ userenv('instance') inst_id,a.* from v$sql a)}
        @CHECK_ACCESS_M: gv$sql_workarea_active/gv$sessmetric={1},default={0}
        @CHECK_ACCESS_PX: {
            gv$px_session={gv$px_session},
            v$px_session={(select /*+merge*/ userenv('instance') inst_id,a.* from v$px_session a)},
            default={(select null inst_id,null sid,null qcinst_id,null qcsid from dual where 1=2)}
        }
        @CHECK_ACCESS_PRO: {
            gv$process={gv$process},
            v$process={(select /*+merge*/ userenv('instance') inst_id,a.* from v$process a)},
            default={(select null inst_id,null addr,null spid from dual where 1=2)}
        }
        @CHECK_ACCESS_SES: gv$session={gv$session}, v$session={(select /*+merge*/ userenv('instance') inst_id,a.* from v$session a)}
    --]]
]]*/


set feed off VERIFY off
col "Physical|Reads,Logical|Reads,HARD|PARSE,SOFT|PARSE" for tmb
col "CPU%,Physical|Reads%,Logical|Reads%" for pct
col "PGA|MEM,LAST SQL|MEM,LAST SQL|TEMP" for kmg
col "waited" for smhd2
col "LAST SQL|ACTIVE" for usmhd2

VAR actives refcursor "Active Sessions"
VAR time_model refcursor "Top Session Metric(Recent 15 secs)"

DECLARE
    time_model sys_refcursor;
    cur SYS_REFCURSOR;
    cs  VARCHAR2(20);
    PROCEDURE report_start IS
        l_intval PLS_INTEGER;
        l_rtn    PLS_INTEGER;
    BEGIN
        IF cs IS NULL THEN
            execute immediate q'[begin :rtn := sys.dbms_utility.get_parameter_value('cursor_sharing',:l_intval,:l_strval); end;]'
            using out l_rtn, in out l_intval,in out cs;
        END IF;
        IF upper(cs) != 'FORCE' THEN
            EXECUTE IMMEDIATE 'alter session set cursor_sharing=force';
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PROCEDURE report_end IS
    BEGIN
        IF upper(cs) != 'FORCE' THEN
            EXECUTE IMMEDIATE 'alter session set cursor_sharing='||cs;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
BEGIN
    IF dbms_db_version.version > 11 and &style=1 THEN
    OPEN :actives --don't materialize sess or v$sql will not use index. Use dynamic SQL to support older version
    FOR q'{WITH sess AS
         (SELECT /*+inline no_parallel */ 
                (select /*+index(o) */ 
                        object_name 
                 from &CHECK_ACCESS_OBJ o 
                 where s.program_id>0 and o.object_id=s.program_id and o.object_type!='DATABASE LINK') program_name,
                 s.*
          FROM   TABLE(gv$(CURSOR(
                SELECT CASE WHEN s.seconds_in_wait > 1.3E9 THEN 0 ELSE round(seconds_in_wait-wait_time/100) END wait_secs,
                       CASE WHEN s.SID||'@'||inst_id = s.qcsid THEN 1 ELSE 0 END ROOT_SID,
                       s.*
                FROM  (SELECT  /*+ordered no_merge(s) use_hash(s p px) push_pred(sq)
                                  table_stats(SYS.X$KGLCURSOR_CHILD set blocks=100000 rows=1000000)
                                  use_nl(sq)
                                */
                                 nvl2(px.qcsid,px.qcsid||'@'||nvl(px.qcinst_id,inst_id),'') qcsid,
                                 p.spid|| regexp_substr(s.program, '\(\S+\)') spid,
                                 s.*, nvl(sq.sq_id,s.sql_id) sq_id,
                                 sq.program_id,sq.program_line#,sq.plan_hash_value,
                                 coalesce(sq.sql_text,nvl2(idn,'idn: '||idn,'')) sql_text,
                                 sq.sql_secs
                        FROM   (select  /*+opt_estimate(query_block rows=1000)*/
                                        userenv('instance') inst_id,
                                        case when a.p1text='idn' --_kgl_bucket_count
                                             and (a.p1>131072 or event not like '%bucket%') then a.p1 end idn,
                                        a.*
                                 from   v$session a
                                 WHERE  (&fil1)
                                 AND    userenv('instance')=nvl('&instance',userenv('instance'))) s,
                                lateral(
                                 select  /*+merge(sq) index(sq)*/
                                         program_line#,program_id,plan_hash_value,sql_id sq_id,
                                         substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '\s+', ' ')), 1, 1024) sql_text,
                                         round(decode(child_number,0,elapsed_time * 1e-6 / (1 + executions), 86400 * (SYSDATE - to_date(last_load_time, 'yyyy-mm-dd/hh24:mi:ss')))) sql_secs
                                 from    v$sql sq
                                 WHERE   s.idn is null
                                 AND     s.sql_id is not null
                                 AND     s.sql_id=sq.sql_id
                                 AND     nvl(s.sql_child_number,0)=sq.child_number &text
                                 UNION ALL 
                                 select  /*+merge(sq) index(sq)*/
                                         program_line#,program_id,plan_hash_value,sql_id,
                                         substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '\s+', ' ')), 1, 1024) sql_text,
                                         round(decode(child_number,0,elapsed_time * 1e-6 / (1 + executions), 86400 * (SYSDATE - to_date(last_load_time, 'yyyy-mm-dd/hh24:mi:ss')))) sql_secs
                                 from    v$sql sq
                                 WHERE   s.idn is not null
                                 AND     s.idn=sq.hash_value &text
                                 AND     rownum<2)&ouj sq,
                                &CHECK_ACCESS_PX11 px,
                                &CHECK_ACCESS_PRO11 p
                        WHERE   s.sid = px.sid(+)
                        AND     s.paddr=p.addr) s
                ))) s
          WHERE sid||'@'||inst_id!=userenv('sid')||'@'||userenv('instance')),
        s4 AS(
          SELECT /*+no_merge(s3) NO_CONNECT_BY_FILTERING CONNECT_BY_COMBINE_SW*/
                 DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
                 rownum r,
                 s3.*
          FROM   sess s3
          START  WITH (qcsid IS NULL OR ROOT_SID=1)
          CONNECT BY qcsid =  PRIOR SID ||'@'||PRIOR inst_id
              AND    ROOT_SID=0
              AND    LEVEL < 3
          ORDER SIBLINGS BY &V1)
        SELECT /*+cardinality(a 1)*/
               row_number() over(order by r) "#",
               a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
               a.spid,
               a.sq_id,
               plan_hash_value plan_hash,
               sql_child_number child,
               a.event,
               ROUND(greatest(nvl(&COST,0),wait_secs,nvl2(sq_id,last_call_et,0)),2) waited,
               &fields,substr(sql_text,1,200) sql_text
        FROM   s4 a
        WHERE  :fil2 IS NOT NULL 
        OR     (ROOT_SID =1 OR status='ACTIVE' and wait_class!='Idle')
        ORDER  BY r}' USING :fil2;
    ELSE
        report_start;
        BEGIN
        OPEN :actives FOR
            WITH s1 AS(
              SELECT /*+no_parallel materialize OPT_PARAM('_fix_control' '26552730:0') opt_estimate(query_block rows=3000) table_stats(SYS.X$KSLWT set rows=3000)*/*
              FROM   &CHECK_ACCESS_SES 
              WHERE (&fil1)
              AND    sid||'@'||inst_id!=userenv('sid')||'@'||userenv('instance')
              AND    userenv('instance')=nvl('&instance',userenv('instance'))),
            s3  AS(SELECT /*+no_merge no_merge(s2) use_hash(s2)*/ s1.*,qcinst_id,qcsid FROM s1,&CHECK_ACCESS_PX s2 where s1.inst_id=s2.inst_id(+) and s1.SID=s2.sid(+)),
            sq1 AS(
              SELECT /*+materialize ordered use_nl(a b)*/ a.*,
                    extractvalue(b.column_value,'/ROW/A1')              program_name,
                    extractvalue(b.column_value,'/ROW/A2')              program_line#,
                    extractvalue(b.column_value,'/ROW/A3')              sql_text,
                    extractvalue(b.column_value,'/ROW/A4')              plan_hash_value,
                    nvl(extractvalue(b.column_value,'/ROW/A5')+0,0)     sql_secs
              FROM (select /*+no_merge*/ distinct inst_id,sql_id,nvl(sql_child_number,0) child from s1 where sql_id is not null) A,
                    TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'[
                        SELECT /*+opt_param('_optim_peek_user_binds','false') table_stats(SYS.X$KGLCURSOR_CHILD set blocks=100000 rows=1000000) index(a)*/ 
                              (select c.owner  ||'.' || c.object_name 
                               from &CHECK_ACCESS_OBJ c 
                               where program_id>0
                               and   c.object_id=program_id
                               and   object_type!='DATABASE LINK' 
                               and   rownum<2) A1,
                               program_line# A2,
                               substr(trim(regexp_replace(REPLACE(sql_text, chr(0)),'[[:space:][:cntrl:]]+',' ')),1,200) A3,
                               plan_hash_value A4,
                               round(decode(child_number,0,elapsed_time*1e-6/(1+executions),86400*(sysdate-to_date(last_load_time,'yyyy-mm-dd/hh24:mi:ss')))) A5
                        FROM  &CHECK_ACCESS_SQL a
                        WHERE ROWNUM<2 &text
                        AND   sql_id=']'||a.sql_id||''' AND inst_id='||a.inst_id||' and child_number='||a.child)
                    ,'/ROWSET/ROW')))&ouj B),
            s4 AS(
              SELECT /*+materialize no_merge(s3)*/
                     DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
                     decode(LEVEL, 1, sql_id) new_sql_id,
                     rownum r,
                     s3.*
              FROM   (SELECT s3.*,
                             CASE WHEN seconds_in_wait > 1.3E9 THEN 0 ELSE round(seconds_in_wait-WAIT_TIME/100) END wait_secs,
                             CASE WHEN S3.SID = S3.qcsid AND S3.inst_id = NVL(s3.qcinst_id,s3.inst_id) THEN 1 ELSE 0 END ROOT_SID,
                             plan_hash_value,
                             program_name,
                             program_line#,
                             sql_text,
                             sql_secs
                      FROM   s3, sq1
                      WHERE  s3.inst_id=sq1.inst_id(+) and s3.sql_id=sq1.sql_id(+) and nvl(s3.sql_child_number,0)=sq1.child(+)) s3
              START  WITH (qcsid IS NULL OR ROOT_SID=1)
              CONNECT BY qcsid = PRIOR SID
                  AND    qcinst_id = PRIOR inst_id
                  AND    ROOT_SID=0
                  AND    LEVEL < 3
              ORDER SIBLINGS BY &V1)
            SELECT /*+cardinality(a 1) use_hash(d)*/
                   row_number() over(order by r) "#",
                   a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
                   d.spid || regexp_substr(A.program, '\(\S+\)') spid,
                   a.sql_id,
                   plan_hash_value plan_hash,
                   sql_child_number child,
                   a.event,
                   ROUND(greatest(nvl(&COST,0),wait_secs,nvl2(sql_id,last_call_et,0)),2) waited,
                   &fields,sql_text
            FROM   s4 a,(SELECT spid,inst_id,addr from &CHECK_ACCESS_PRO) d
            WHERE  d.inst_id = a.inst_id
            AND    d.addr = a.paddr
            AND   (:fil2 IS NOT NULL  OR (ROOT_SID =1 OR status='ACTIVE' and wait_class!='Idle'))
            ORDER  BY r;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        report_end;
    END IF;   
    $IF &smen=1 $THEN
    OPEN time_model FOR q'~
        SELECT rownum "#",a.*
        FROM   (SELECT session#,
                       MAX(usr) usr,
                       MAX(program) program,
                       greatest(count(1),nvl(max(degree),1)) dop,
                       round(ratio_to_report(SUM(CPU)) over(),4) "CPU%",
                       round(ratio_to_report(SUM(PHYSICAL_READ_PCT)) over(),4) "Physical|Reads%",
                       round(ratio_to_report(SUM(LOGICAL_READ_PCT)) over(),4)  "Logical|Reads%",
                       SUM(PHYSICAL_READS) "Physical|Reads",
                       SUM(LOGICAL_READS) "Logical|Reads",
                       SUM(PGA_MEMORY) "PGA|MEM",
                       SUM(HARD_PARSES) "HARD|PARSE",
                       SUM(SOFT_PARSES) "SOFT|PARSE",
                       MAX(SQL_ID) "LAST|SQL",
                       SUM(ACTIVE_TIME) "LAST SQL|ACTIVE",
                       MAX(OPERATION_TYPE) KEEP(DENSE_RANK LAST ORDER BY ACTIVE_TIME) "LAST SQL|OPERATION",
                       SUM(ACTUAL_MEM_USED) "LAST SQL|MEM",
                       SUM(TEMPSEG_SIZE) "LAST SQL|TEMP",
                       SUM(NUMBER_PASSES) "HASH JOIN|PASSES"
                FROM TABLE(GV$(CURSOR(
                        SELECT /*+use_hash(m s p w)*/
                               coalesce(p.qcsid,w.qcsid,sid)
                               ||',' ||nvl(p.qcserial#,s.serial#)
                               ||',@'||nvl(nvl2(p.qcsid,p.qcinst_id,w.qcinst_id),inst_id) session#,
                               s.schemaname usr,
                               nvl(regexp_substr(s.program,'\(.\S+\)'),substr(regexp_replace(s.program,'[@\(\-].*'),1,30)) program,
                               nvl(w.sql_id,s.sql_id) sql_id,
                               w.OPERATION_TYPE,
                               w.ACTIVE_TIME,
                               w.ACTUAL_MEM_USED,
                               w.TEMPSEG_SIZE,
                               w.NUMBER_PASSES,
                               m.CPU,
                               m.PHYSICAL_READS,
                               m.LOGICAL_READS,
                               m.PGA_MEMORY,
                               m.HARD_PARSES,
                               m.SOFT_PARSES,
                               m.PHYSICAL_READ_PCT,
                               m.LOGICAL_READ_PCT,
                               p.degree
                        FROM  (SELECT m.*,session_id sid FROM v$sessmetric m) m
                        JOIN  (SELECT s.*,userenv('instance') inst_id FROM V$SESSION s) s USING (sid)
                        LEFT   JOIN v$px_session p USING (sid)
                        LEFT   JOIN v$sql_workarea_active w USING (sid)
                        WHERE  inst_id=nvl('&instance',inst_id) 
                        &fil2
                ))) a 
                GROUP BY session#
                ORDER  BY &ord nvl("CPU%",0) + nvl("Physical|Reads%"/2,0) + nvl("Logical|Reads%"/15,0) DESC,"PGA|MEM" desc
        ) a WHERE ROWNUM<=50~';
    $END
    :time_model:=time_model;
END;
/

print actives
print time_model