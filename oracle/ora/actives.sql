/*[[
    Show active sessions. Usage: ora actives [-s|-p|-b] [-f"<filter>"|-u] [sid|wt|ev|sql|<col>]
    Options:
        Filter options:
            -u  : Only show the session of current_schema
            -i  : Exclude the idle events
            -f  : Custimized filter, Usage: -f"<filter>"
        Field options:  Field options can be following by other customized fields. ie: -s,p1raw
            -s  : Show related procedures and lines(default)
            -p  : Show p1/p2/p2text/p3
            -b  : Show blocking sessions and waiting objects
            -o  : Show os user id/machine/program/etc 
        Sorting options: the '-' symbole is optional
            sid : sort by sid(default)
            wt  : sort by wait time
            sql : sort by sql text
            ev  : sort by event
            -o  : together with the '-o' option above, sort by logon_time
           <col>: field in v$session
        Other options:
            -m  : Show SQL memory information in additional
    --[[
        &fields : {
               s={coalesce(nullif(program_name,'0'),'['||regexp_replace(nvl(a.module,a.program),' *\(.*\)$')||'('||osuser||')]') PROGRAM,PROGRAM_LINE# line#},
               o={schemaname schema,osuser,logon_time,regexp_replace(machine,'(\..*|^.*\\)') machine,regexp_replace(program,' *\(.*') program},
               p={p1,p2,p2text,p3},
               b={NULLIF(BLOCKING_SESSION||',@'||BLOCKING_INSTANCE,',@') BLOCK_BY,
                 (SELECT OBJECT_NAME FROM ALL_OBJECTS WHERE OBJECT_ID=ROW_WAIT_OBJ# AND ROWNUM<2) WAITING_OBJ,
                 ROW_WAIT_BLOCK# WAIT_BLOCK#}
            }
        &V1 : sid={''||sid},wt={seconds_in_wait desc},ev={event},sql={sql_text},o={logon_time}
        &Filter: {default={ROOT_SID =1 OR wait_class!='Idle' or sql_text is not null}, 
                  f={},
                  i={wait_class!='Idle'}
                  u={(ROOT_SID =1 OR STATUS='ACTIVE' or sql_text is not null) and schemaname=sys_context('userenv','current_schema')}
                 }
        &tmodel : default={0}, m={1}
        @COST : 11.0={nvl(1440*(sysdate-SQL_EXEC_START),wait_secs/60)},10.0={(select TIME_WAITED/6000 from gv$session_event b where b.inst_id=a.inst_id and b.sid=a.sid and b.event=a.event)},9.0={null}
        @CHECK_ACCESS1: dba_objects={dba_objects},all_objects={all_objects}
        @CHECK_ACCESS2: gv$px_session/gv$sql/gv$process={}
    --]]
]]*/

set feed off
set printvar on
VAR actives refcursor "Active Sessions"
VAR time_model refcursor "Top Session Time Model"
BEGIN
    OPEN :actives FOR
        WITH s1 AS
         (SELECT /*+no_merge*/*
          FROM   gv$session
          WHERE  sid != USERENV('SID')
          AND    audsid != userenv('sessionid')
          And    (event not like 'Streams%')),
        s3 AS
         (SELECT /*+no_merge no_merge(s2)*/ * FROM s1 LEFT JOIN  gv$px_session s2 USING (inst_id, SID, serial#,saddr)),
        sq1 as(
         SELECT /*+materialize ordered use_nl(a b)*/ a.*,
               extractvalue(b.column_value,'/ROW/A1')     program_name,
               extractvalue(b.column_value,'/ROW/A2')     PROGRAM_LINE#,
               extractvalue(b.column_value,'/ROW/A3')     sql_text,
               extractvalue(b.column_value,'/ROW/A4')     plan_hash_value
         FROM (select distinct inst_id,sql_id,nvl(sql_child_number,0) child from s1 where sql_id is not null) A,
               TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'[
                   SELECT (select c.owner  ||'.' || c.object_name from &CHECK_ACCESS1 c where c.object_id=program_id and rownum<2) A1,
                          PROGRAM_LINE# A2,
                          trim(substr(regexp_replace(REPLACE(sql_text, chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200)) A3,
                          plan_hash_value A4
                   FROM  gv$sql
                   WHERE ROWNUM<2 AND sql_id=']'||a.sql_id||''' AND inst_id='||a.inst_id||' and child_number='||a.child)
               ,'/ROWSET/ROW'))) B
        ),
        s4 AS
         (SELECT /*+materialize no_merge(s3)*/
               DECODE(LEVEL, 1, '', '  ') || SID NEW_SID,
               decode(LEVEL, 1, sql_id) new_sql_id,
               rownum r,
               s3.*
          FROM   (SELECT s3.*,
                         CASE WHEN seconds_in_wait > 1300000000 THEN 0 ELSE seconds_in_wait END wait_secs,
                         CASE WHEN S3.SID = S3.qcsid AND S3.inst_id = NVL(s3.qcinst_id,s3.inst_id) THEN 1 ELSE 0 END ROOT_SID,
                         plan_hash_value,
                         program_name,
                         program_line#,
                         sql_text
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
                FROM   gv$process d
                WHERE  d.inst_id = a.inst_id
                AND    d.addr = a.paddr) || regexp_substr(program, '\(.*\)') spid,
               a.sql_id,
               plan_hash_value plan_hash,
               sql_child_number child,
               a.event,&fields,
               ROUND(&COST,1) waits,
               sql_text
        FROM   s4 a
        WHERE  (&filter)
        ORDER  BY r;

    IF &tmodel = 1 THEN
        OPEN :time_model FOR
            SELECT *
            FROM   (SELECT session#,
                           max(regexp_replace(nvl(c.module,c.program),' *\(TNS.*\)$')||'('||c.osuser||')') program,
                           max(a.sql_id) sql_id,
                           COUNT(1) PX,
                           MAX(intsize_csec / 100) Secs,
                           round(SUM(PGA_MEMORY) / 1024 / 1024, 2) PGA_MB,
                           round(SUM(exp_size) / 1024 / 1024, 2) WRK_MB,
                           round(SUM(TEMP_SIZE) / 1024 / 1024, 2) TEMP_MB,
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
            WHERE  "CPU%" + "PSC%" + "LGC%" + hard_parse > 0
            ORDER  BY GREATEST("CPU%", "PSC%", "LGC%") DESC;

    END IF;
END;
/