/*[[
    Show active sessions. Usage: @@NAME [sid|wt|ev|sql|<col>] [-s|-p|-b|-o|-m] {[-f"<filter>"|-text"<keyword>"|-u|-i] [-f2"<filter>"|-u2|-i2]}
    
    Options(options within same group cannot combine, i.e. "@@NAME -u -i" is illegal, use "@@NAME -u -i2" instead):
        Filter options#1:
            -u   : Only show the sessions of current_schema
            -i   : Exclude the idle events
            -f   : Customize the filter, i.e.: -f"inst_id=1"
            -text: Find sql with keyword
        Filter options#2:
            -u2 : Only show the sessions of current_schema
            -i2 : Exclude the idle events
            -f2 : Customize the filter, Usage: i.e.: -f2"username='SYS'"
        Field options:  Field options can be followed by other customized fields. ie: -s,p1raw
            -s  : Show related procedures and lines(default)
            -p  : Show p1/p2/p2text/p3
            -b  : Show blocking sessions and waiting objects
            -o  : Show OS user id/machine/program/etc
            -m  : Show SQL Mornitor report(gv$sql_monitor)
            -c  : show consumer group and queue duration
        Sorting options: the '-' symbole is optional
            sid : sort by sid(default)
            wt  : sort by wait time
            sql : sort by sql text
            ev  : sort by event
            -o  : together with the '-o' option above, sort by logon_time
           <col>: field in v$session
    --[[
        &fields : {
               s={coalesce(nullif(program_name,'0'),'['||regexp_replace(regexp_replace(nvl(a.module,a.program),' *\(.*\)$'),'.*@')||'('||osuser||')]') PROGRAM,program_line# line# },
               o={schemaname schema,osuser,logon_time,regexp_replace(machine,'(\..*|^.*\\)') machine,regexp_replace(program,' *\(.*') program &0},
               p={p1,p2,p2text,p3 &0},
               b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
                 (SELECT OBJECT_NAME FROM &CHECK_ACCESS_OBJ WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2) WAITING_OBJ,
                 ROW_WAIT_BLOCK# WAIT_BLOCK# &0},
               c={USERNAME,RESOURCE_CONSUMER_GROUP RSRC_GROUP,CURRENT_QUEUE_DURATION QUEUED &0}
            }
        &V1 :   sid={''||sid},wt={wait_secs desc},ev={event},sql={sql_text},o={logon_time}
        &Filter: {default={ROOT_SID =1 OR status='ACTIVE' and (wait_class!='Idle' and event not like 'SQL*Net message from client')}, 
                  f={},
                  text={upper(sql_text) like upper('%&0%')}
                  i={wait_class!='Idle'}
                  u={(ROOT_SID =1 OR STATUS='ACTIVE') and schemaname=nvl('&0',sys_context('userenv','current_schema'))}
                 }
        &Filter2:{default={1=1}, 
                  f2={},
                  i2={wait_class!='Idle'}
                  u2={(ROOT_SID =1 OR STATUS='ACTIVE') and schemaname=sys_context('userenv','current_schema')}
                 }
        &smen : default={0}, m={&CHECK_ACCESS_M}
        @COST : 11.0={1440*(sysdate-sql_exec_start)},10.0={sql_secs/60}
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
    --]]
]]*/


set feed off VERIFY off
VAR actives refcursor "Active Sessions"
VAR time_model refcursor "Top Session Metric"

DECLARE
    time_model sys_refcursor;
    cur SYS_REFCURSOR;
BEGIN
    OPEN :actives --don't materialize sess or v$sql will not use index. Use dynamic SQL to support older version
    FOR q'{WITH sess AS
         (SELECT /*+inline*/ (select /*+index(o) opt_param('optimizer_dynamic_sampling' 0)*/ 
                 object_name from &CHECK_ACCESS_OBJ o where s.program_id>0 and o.object_id=s.program_id and o.object_type!='DATABASE LINK') program_name,
                 s.*
          FROM   TABLE(gv$(CURSOR(
                SELECT CASE WHEN s.seconds_in_wait > 1.3E9 THEN 0 ELSE round(seconds_in_wait-wait_time/100) END wait_secs,
                       CASE WHEN s.SID||'@'||inst_id = s.qcsid THEN 1 ELSE 0 END ROOT_SID,
                       s.*
                FROM  (SELECT  /*+ordered use_nl(s sq) no_merge(s) use_hash(s p px)*/
                                 nvl2(px.qcsid,px.qcsid||'@'||nvl(px.qcinst_id,inst_id),'') qcsid,
                                 p.spid|| regexp_substr(s.program, '\(\S+\)') spid,
                                 s.*, nvl(sq.sq_id,s.sql_id) sq_id,
                                 sq.program_id,sq.program_line#,sq.plan_hash_value,
                                 coalesce(sq.sql_text,nvl2(idn,'idn: '||idn,'')) sql_text,
                                 sq.sql_secs
                        FROM   (select  userenv('instance') inst_id,
                                        case when a.p1text='idn' 
                                             and (a.p1>131072 or event not like 'library%') then a.p1 end idn,
                                        a.*
                                 from   v$session a
                                 WHERE  (event NOT LIKE 'Streams%' or wait_class!='Idle' or event not like 'SQL*%')
                                 AND    userenv('instance')=nvl('&instance',userenv('instance'))) s,
                                lateral(
                                 select  program_line#,program_id,plan_hash_value,sql_id sq_id,
                                         substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '\s+', ' ')), 1, 1024) sql_text,
                                         round(decode(child_number,0,elapsed_time * 1e-6 / (1 + executions), 86400 * (SYSDATE - to_date(last_load_time, 'yyyy-mm-dd/hh24:mi:ss')))) sql_secs
                                 from    v$sql sq
                                 WHERE   s.idn is null
                                 AND     s.sql_id is not null
                                 AND     s.sql_id=sq.sql_id
                                 AND     nvl(s.sql_child_number,0)=sq.child_number
                                 UNION ALL 
                                 select  program_line#,program_id,plan_hash_value,sql_id,
                                         substr(TRIM(regexp_replace(replace(sql_text,chr(0)), '\s+', ' ')), 1, 1024) sql_text,
                                         round(decode(child_number,0,elapsed_time * 1e-6 / (1 + executions), 86400 * (SYSDATE - to_date(last_load_time, 'yyyy-mm-dd/hh24:mi:ss')))) sql_secs
                                 from    v$sql sq
                                 WHERE   s.idn is not null
                                 AND     s.idn=sq.hash_value
                                 AND     rownum<2)(+) sq,
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
               rownum "#",
               a.NEW_SID || ',' || a.serial# || ',@' || a.inst_id session#,
               a.spid,
               a.sq_id,
               plan_hash_value plan_hash,
               sql_child_number child,
               a.event,
               ROUND(greatest(nvl(&COST,0),wait_secs/60,nvl2(sq_id,last_call_et,0)/60),1) waited,
               &fields,substr(sql_text,1,200) sql_text
        FROM   s4 a
        WHERE  (&filter) AND (&Filter2)
        ORDER  BY r}';
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
                    FROM   (SELECT nvl(qcsid, session_id) || ',@' || nvl(qcinst_id, a.inst_id) SESSION#,
                                   a.*,
                                   b.*,
                                   SUM(b.ACTUAL_MEM_USED) over(PARTITION BY b.sid, b.inst_id) exp_size,
                                   SUM(b.TEMPSEG_SIZE) over(PARTITION BY b.sid, b.inst_id) TEMP_SIZE,
                                   row_number() OVER(PARTITION BY b.sid, b.inst_id ORDER BY ACTUAL_MEM_USED DESC) r
                            FROM   gv$sql_workarea_active b, gv$sessmetric a
                            WHERE  a.session_id = b.sid(+)
                            AND    a.inst_id = b.inst_id(+)) a,
                           (SELECT /*+no_merge*/VALUE / 1024 / 1024 blksiz
                            FROM   v$parameter
                            WHERE  NAME = 'db_block_size'),
                            gv$session c
                    WHERE  r = 1
                    AND    SESSION#=(c.sid||',@'||c.inst_id)
                    GROUP  BY session#)
            WHERE  "CPU%" + "PSC%" + nvl("LGC%",0) + hard_parse > 0
            ORDER  BY GREATEST("CPU%", "PSC%", "LGC%") DESC;
    $END
    :time_model:=time_model;
END;
/

print actives
print time_model