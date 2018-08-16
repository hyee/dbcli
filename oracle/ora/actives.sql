/*[[
    Show active sessions. Usage: @@NAME [sid|wt|ev|sql|<col>] [-s|-p|-b|-o|-m] {[-f"<filter>"|-u|-i] [-f2"<filter>"|-u2|-i2]}
    
    Options(options within same group cannot combine, i.e. "@@NAME -u -i" is illegal, use "@@NAME -u -i2" instead):
        Filter options#1:
            -u  : Only show the sessions of current_schema
            -i  : Exclude the idle events
            -f  : Customize the filter, Usage: -f"<filter>"
        Filter options#2:
            -u2 : Only show the sessions of current_schema
            -i2 : Exclude the idle events
            -f2 : Customize the filter, Usage: -f2"<filter>"
        Field options:  Field options can be followed by other customized fields. ie: -s,p1raw
            -s  : Show related procedures and lines(default)
            -p  : Show p1/p2/p2text/p3
            -b  : Show blocking sessions and waiting objects
            -o  : Show OS user id/machine/program/etc
            -m  : Show SQL Mornitor report(gv$sql_monitor)
        Sorting options: the '-' symbole is optional
            sid : sort by sid(default)
            wt  : sort by wait time
            sql : sort by sql text
            ev  : sort by event
            -o  : together with the '-o' option above, sort by logon_time
           <col>: field in v$session
    --[[
        &fields : {
               s={coalesce(nullif(program_name,'0'),'['||regexp_replace(nvl(a.module,a.program),' *\(.*\)$')||'('||osuser||')]') PROGRAM,program_line# line#},
               o={schemaname schema,osuser,logon_time,regexp_replace(machine,'(\..*|^.*\\)') machine,regexp_replace(program,' *\(.*') program},
               p={p1,p2,p2text,p3},
               b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
                 (SELECT OBJECT_NAME FROM ALL_OBJECTS WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2) WAITING_OBJ,
                 ROW_WAIT_BLOCK# WAIT_BLOCK#},
               m={execs, ela,cpu,io,app,cc,cl,plsql,java,read_mb,write_mb}  
            }
        &V1 :   sid={''||sid},wt={wait_secs desc},ev={event},sql={sql_text},o={logon_time}
        &SQLM:  {default={},
                 m={LEFT JOIN (
                        SELECT --+ no_merge
                               sid, sql_id, count(distinct sql_exec_id) execs,
                               round(SUM(ELAPSED_TIME)*1e-6/60,2) ela, round(SUM(QUEUING_TIME)*1e-6,2) QUEUE, 
                               round(SUM(CPU_TIME)*1e-6/60,2) CPU, round(SUM(APPLICATION_WAIT_TIME)*1e-6/60,2) app,
                               round(SUM(CONCURRENCY_WAIT_TIME)*1e-6/60,2) cc, 
                               round(SUM(CLUSTER_WAIT_TIME)*1e-6/60,2) cl, 
                               round(SUM(PLSQL_EXEC_TIME)*1e-6/60,2) plsql, 
                               round(SUM(JAVA_EXEC_TIME)*1e-6/60,2) JAVA, round(SUM(USER_IO_WAIT_TIME)*1e-6/60,2) io,
                               round(SUM(PHYSICAL_READ_BYTES)/1024/1024,2) read_mb, round(SUM(PHYSICAL_WRITE_BYTES)/1024/1024,2) write_mb
                        FROM   v$sql_monitor
                        WHERE  status = 'EXECUTING'
                        GROUP BY sid, sql_id) m
                    USING (sid, sql_id)}
                } 
        &Filter: {default={ROOT_SID =1 OR (wait_class!='Idle' and event not like '%PX%') or sql_text is not null}, 
                  f={},
                  i={wait_class!='Idle'}
                  u={(ROOT_SID =1 OR STATUS='ACTIVE' or sql_text is not null) and schemaname=nvl('&0',sys_context('userenv','current_schema'))}
                 }
        &Filter2:{default={1=1}, 
                  f2={},
                  i2={wait_class!='Idle'}
                  u2={(ROOT_SID =1 OR STATUS='ACTIVE' or sql_text is not null) and schemaname=sys_context('userenv','current_schema')}
                 }
        &smen : default={0}, m={&CHECK_ACCESS_M}
        @COST : 11.0={1440*(sysdate-sql_exec_start)},10.0={sql_secs/60}
        @CHECK_ACCESS_OBJ: dba_objects={dba_objects},all_objects={all_objects}
        @CHECK_ACCESS_PX11: {
            v$px_session={v$px_session},
            default={(select null inst_id,null sid,null qcinst_id,null qcsid from dual where 1=2)}
        }
        @CHECK_ACCESS_PRO11: {
            v$process={v$process},
            default={(select null inst_id,null addr,null spid from dual where 1=2)}
        }

        @CHECK_ACCESS_SES: gv$session={gv$session}, v$session={(select /*+merge*/ userenv('instance') inst_id,a.* from v$session a)}
        @CHECK_ACCESS_SQL: gv$sql={gv$sql}, v$sql={(select /*+merge*/ userenv('instance') inst_id,a.* from v$sql a)}
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

        @CHECK_ACCESS_M: gv$sql_workarea_active/gv$sessmetric={1},default={0}
    --]]
]]*/


set feed off VERIFY on
VAR actives refcursor "Active Sessions"
VAR time_model refcursor "Top Session Metric"

DECLARE
    time_model sys_refcursor;
    cur SYS_REFCURSOR;
BEGIN
    IF dbms_db_version.version > 10 THEN
        OPEN :actives FOR q'{
            WITH sess AS
             (SELECT (select object_name from &CHECK_ACCESS_OBJ o where o.object_id=s.program_id) program_name,
                     s.*
              FROM   TABLE(gv$(CURSOR(
                   SELECT (SELECT spid FROM &CHECK_ACCESS_PRO11 d WHERE d.addr = s.paddr)|| regexp_substr(s.program, '\(.*\)') spid,
                          CASE WHEN s.seconds_in_wait > 1.3E9 THEN 0 ELSE round(seconds_in_wait-WAIT_TIME/100) END wait_secs,
                          CASE WHEN s.SID = s.qcsid THEN 1 ELSE 0 END ROOT_SID,
                          regexp_substr(sql_info,'[^'||chr(1)||']+',1,1)+0 program_id,
                          regexp_substr(sql_info,'[^'||chr(1)||']+',1,2)+0 program_line#,
                          regexp_substr(sql_info,'[^'||chr(1)||']+',1,3)+0 plan_hash_value,
                          regexp_substr(sql_info,'[^'||chr(1)||']+',1,4)   sql_text,
                          regexp_substr(sql_info,'[^'||chr(1)||']+',1,5)   sql_secs,
                          s.*
                    FROM  (SELECT /*+order use_hash(m)*/ * FROM 
                            (SELECT (SELECT qcsid FROM &CHECK_ACCESS_PX11 p WHERE  s.sid = p.sid) qcsid,
                                    (SELECT /*+index(b.GV$SQL.X$KGLCURSOR_CHILD)*/ b.program_id||chr(1)
                                         || b.program_line#||chr(1)
                                         || b.plan_hash_value||chr(1)
                                         || substr(TRIM(regexp_replace(replace(b.sql_text,chr(0)), '[' || chr(1) || chr(10) || chr(13) || chr(9) || ' ]+', ' ')), 1, 200)||chr(1)
                                         || round(decode(b.child_number,0,b.elapsed_time * 1e-6 / (1 + b.executions), 86400 * (SYSDATE - to_date(b.last_load_time, 'yyyy-mm-dd/hh24:mi:ss'))))
                                     FROM   v$sql b 
                                     WHERE  s.sql_id = b.sql_id 
                                     and b.child_number=nvl(s.sql_child_number,0)) sql_info,
                                     userenv('instance') inst_id, 
                                     s.*
                             FROM    v$session s
                             WHERE   s.event NOT LIKE 'Streams%') s &SQLM) s
                    ))) s
              WHERE sid||'@'||inst_id!=userenv('sid')||'@'||userenv('instance')),
            s4 AS(
              SELECT /*+no_merge(s3)*/
                     DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
                     decode(LEVEL, 1, sql_id) new_sql_id,
                     rownum r,
                     s3.*
              FROM   sess s3
              START  WITH (qcsid IS NULL OR ROOT_SID=1)
              CONNECT BY qcsid = PRIOR SID
                  AND    ROOT_SID=0
                  AND    LEVEL < 3
              ORDER SIBLINGS BY &V1)
            SELECT /*+cardinality(a 1)*/
                   rownum "#",
                   a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
                   a.spid,
                   a.sql_id,
                   plan_hash_value plan_hash,
                   sql_child_number child,
                   a.event,
                   ROUND(greatest(nvl(&COST,0),wait_secs/60,nvl2(sql_id,last_call_et,0)/60),1) waited,
                   &fields,sql_text
            FROM   s4 a
            WHERE  (&filter) AND (&Filter2)
            ORDER  BY r}';
    ELSE
        OPEN :actives FOR
            WITH s1 AS(
              SELECT /*+no_merge*/*
              FROM   &CHECK_ACCESS_SES &SQLM
              WHERE  not (sid = USERENV('SID') and inst_id = userenv('instance'))
              AND   (event not like 'Streams%')),
            s3  AS(SELECT /*+no_merge no_merge(s2)*/ s1.*,qcinst_id,qcsid FROM s1,&CHECK_ACCESS_PX s2 where s1.inst_id=s2.inst_id(+) and s1.SID=s2.sid(+)),
            sq1 AS(
              SELECT /*+materialize ordered use_nl(a b)*/ a.*,
                    extractvalue(b.column_value,'/ROW/A1')              program_name,
                    extractvalue(b.column_value,'/ROW/A2')              program_line#,
                    extractvalue(b.column_value,'/ROW/A3')              sql_text,
                    extractvalue(b.column_value,'/ROW/A4')              plan_hash_value,
                    nvl(extractvalue(b.column_value,'/ROW/A5')+0,0)     sql_secs
              FROM (select distinct inst_id,sql_id,nvl(sql_child_number,0) child from s1 where sql_id is not null) A,
                    TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'[
                        SELECT /*+opt_param('_optim_peek_user_binds','false') opt_param('cursor_sharing','force')*/
                              (select c.owner  ||'.' || c.object_name from &CHECK_ACCESS_OBJ c where c.object_id=program_id and rownum<2) A1,
                               program_line# A2,
                               substr(trim(regexp_replace(REPLACE(sql_text, chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' ')),1,200) A3,
                               plan_hash_value A4,
                               round(decode(child_number,0,elapsed_time*1e-6/(1+executions),86400*(sysdate-to_date(last_load_time,'yyyy-mm-dd/hh24:mi:ss')))) A5
                        FROM  &CHECK_ACCESS_SQL
                        WHERE ROWNUM<2 AND sql_id=']'||a.sql_id||''' AND inst_id='||a.inst_id||' and child_number='||a.child)
                    ,'/ROWSET/ROW'))) B),
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
            SELECT /*+cardinality(a 1)*/
                   rownum "#",
                   a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
                   (SELECT spid
                    FROM   &CHECK_ACCESS_PRO d
                    WHERE  d.inst_id = a.inst_id
                    AND    d.addr = a.paddr) || regexp_substr(program, '\(.*\)') spid,
                   a.sql_id,
                   plan_hash_value plan_hash,
                   sql_child_number child,
                   a.event,
                   ROUND(greatest(nvl(&COST,0),wait_secs/60,nvl2(sql_id,last_call_et,0)/60),1) waited,
                   &fields,sql_text
            FROM   s4 a
            WHERE  (&filter) AND (&Filter2)
            ORDER  BY r;
    END IF;    
    $IF &smen=1 $THEN
        OPEN time_model FOR
            SELECT *
            FROM   (SELECT session#,
                           max(regexp_replace(nvl(c.module,c.program),' *\(TNS.*\)$')||'('||c.osuser||')') program,
                           max(a.sql_id) sql_id,
                           COUNT(1) PX,
                           MAX(intsize_csec / 100) metric_Secs,
                           round(SUM(PGA_MEMORY) / 1024 / 1024, 2) PGA_MB,
                           round(SUM(ACTUAL_MEM_USED) / 1024 / 1024, 2) WRK_MB,
                           round(SUM(TEMPSEG_SIZE) / 1024 / 1024, 2) TEMP_MB,
                           round(SUM(cpu), 2) cpu,
                           round(100 * ratio_to_report(SUM(CPU)) OVER(), 2) "CPU%",
                           round(SUM(physical_reads * blksiz), 2) physical_MB,
                           round(SUM(physical_reads * blksiz * 100 / intsize_csec), 2) "P_MB/SEC",
                           round(100 * ratio_to_report(SUM(physical_reads)) OVER(), 2) "PSC%",
                           round(SUM(logical_reads * blksiz), 2) logical_MB,
                           round(SUM(logical_reads * blksiz * 100 / intsize_csec), 2) "L_MB/SEC",
                           round(100 * ratio_to_report(SUM(logical_reads)) OVER(), 2) "LGC%",
                           SUM(hard_parses) hard_parse,
                           SUM(soft_parses) soft_parse
                    FROM   (SELECT a.*,
                                   b.*,
                                   nvl(qcsid, session_id) || ',@' || nvl(qcinst_id, a.inst_id) SESSION#,
                                   SUM(b.ACTUAL_MEM_USED) over(PARTITION BY b.sid, b.inst_id) exp_size,
                                   SUM(b.TEMPSEG_SIZE) over(PARTITION BY b.sid, b.inst_id) TEMP_SIZE,
                                   row_number() OVER(PARTITION BY b.sid, b.inst_id ORDER BY ACTUAL_MEM_USED DESC) r
                            FROM   gv$sql_workarea_active b, gv$sessmetric a
                            WHERE  a.session_id = b.sid(+)
                            AND    a.inst_id = b.inst_id(+)
                            ) a,
                           (SELECT /*+no_merge*/
                             VALUE / 1024 / 1024 blksiz
                            FROM   v$parameter
                            WHERE  NAME = 'db_block_size'),
                            gv$session c
                    WHERE  r = 1
                    AND    SESSION#=(c.sid||',@'||c.inst_id)
                    AND    c.sid != USERENV('SID')
                    AND    c.audsid != userenv('sessionid')
                    GROUP  BY session#)
            WHERE  "CPU%" + "PSC%" + nvl("LGC%",0) + hard_parse > 0
            ORDER  BY GREATEST("CPU%", "PSC%", "LGC%") DESC;

    $END
    :time_model:=time_model;
END;
/