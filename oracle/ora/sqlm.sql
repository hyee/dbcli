/*[[
    Get resource usage from SQL monitor. Usage: @@NAME {sql_id [<SQL_EXEC_ID>] [[plan_hash_value] -l|-a|-s]} | {. <keyword>} [-u|-f"<filter>"] [-avg]
    Related parameters for SQL monitor: 
        _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
    
    Usages:
       1. @@NAME <sql_id> [<sql_exec_id>]           : Extract sql monitor report with specific sql_id, options: -s,-a,-f"<format>"
       2. @@NAME [. <keyword>]                      : List recent sql monitor reports,options: -avg,-u,-f"<filter>" 
       3. @@NAME <sql_id> -l [plan_hash|sql_exec_id]: List the reports and generate perf hub report for specific SQL_ID, options: -avg,-u,-a,-f"<filter>"
       4. @@NAME -snap <sec> <sid>                  : Monitor the specific <sid> for <sec> seconds, and then list the SQL monitor result, options: -avg
       
    Options:
        -u  : Only show the SQL list within current schema
        -f  : List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
        -s  : Plan format is "ALL-SESSIONS-SQL_FULLTEXT-SQL_TEXT", this is the default
        -a  : Plan format is "ALL-SQL_FULLTEXT-SQL_TEXT", when together with "-l" option, generate SQL Hub report
        -avg: Show avg time in case of listing the SQL monitor reports 

   --[[
      @ver: 12.2={} 11.2={--}
      &uniq:    default={count(DISTINCT sql_exec_id||','||to_char(sql_exec_start,'YYYYMMDDHH24MISS'))}
      &option : default={}, l={,sql_exec_id,plan_hash,sql_exec_start}
      &option1: default={&uniq execs,round(sum(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME))/&uniq*1e-6,2) avg_ela,}, l={}
      &filter: default={1=1},f={},l={sql_id=sq_id},snap={DBOP_EXEC_ID=dopeid and dbop_name=dopename},u={username=nvl('&0',sys_context('userenv','current_schema'))}
      &format: default={BASIC+PLAN+BINDS},s={ALL-SESSIONS}, a={ALL}
      &tot : default={1} avg={0}
      &avg : defult={1} avg={&uniq}
      &snap: default={0} snap={1}
      &showhub: default={0} a={1}
      @check_access_hub : SYS.DBMS_PERF={&showhub} default={0}
      @check_access_sqlm: SYS.DBMS_SQL_MONITOR/SYS.DBMS_LOCK={1} default={0}
   --]]
]]*/

set feed off VERIFY off
var c refcursor;
var c0 refcursor;
var c1 refcursor;
var c2 refcursor;
var rs CLOB;
var filename varchar2;
var plan_hash number;
col dur,avg_ela,ela,parse,queue,cpu,app,cc,cl,plsql,java,io,time format smhd2
col read,write,iosize,mem,temp,cellio,buffget,offload,offlrtn,calc_kmg,ofl format kmg
col est_cost,est_rows,act_rows,ioreq,execs,outputs,FETCHES,dxwrite,calc_tmb format TMB

ALTER SESSION SET PLSQL_CCFLAGS = 'hub:&check_access_hub,sqlm:&check_access_sqlm';

DECLARE
    plan_hash  INT := regexp_substr(:V2, '^\d+$');
    start_time DATE;
    end_time   DATE;
    sq_id      VARCHAR2(50):=:V1;
    inst       INT := :INSTANCE;
    execs      INT;
    counter    INT := &tot;
    filename   VARCHAR2(100);
    content    CLOB;
    dopename   VARCHAR(30);
    dopeid     INT;
    keyw       VARCHAR2(300):=:V2;
    c2         SYS_REFCURSOR;
    sql_exec   INT;
    sql_start  DATE;
    serial     INT;
BEGIN
    IF &SNAP=1 THEN
        $IF $$sqlm=0 OR DBMS_DB_VERSION.release=1 $THEN
            raise_application_error(-20001,'You dont'' have access on dbms_sql_monitor/dbms_lock, or db version < 12.2!');
        $ELSE
            dopename := 'DBCLI_SNAPPER_'||USERENV('SESSIONID');
            select max(serial#) into serial from v$session where sid=plan_hash;
            if serial is null then 
                raise_application_error(-20001, 'session#'||plan_hash||' cannot be found in v$session!');
            end if;
            dopeid:= sys.dbms_sql_monitor.begin_operation (
                             dbop_name       => dopename,
                             dbop_eid        => dopeid,
                             forced_tracking => sys.dbms_sql_monitor.force_tracking,
                             session_id      => plan_hash,
                             session_serial  => serial);
            sys.dbms_lock.sleep(sq_id+0);
            sys.dbms_sql_monitor.end_operation(dopename,dopeid);
            dbms_output.put_line('Filter: dbop_name='''||dopename||''' and dbop_exec_id='||dopeid);
            open c2 for 
                SELECT *
                FROM   (SELECT MAX(DECODE(MOD(rnk, 3), 1, NAME)) stat_name#1,
                               MAX(DECODE(MOD(rnk, 3), 1, VALUE)) stat_value#1,
                               MAX(DECODE(MOD(rnk, 3), 2, NAME)) stat_name#2,
                               MAX(DECODE(MOD(rnk, 3), 2, VALUE)) stat_value#2,
                               MAX(DECODE(MOD(rnk, 3), 0, NAME)) stat_name#3,
                               MAX(DECODE(MOD(rnk, 3), 0, VALUE)) stat_value#3
                        FROM   (SELECT substr(NAME, 1, 35) NAME, SUM(VALUE) VALUE, row_number() OVER(ORDER BY SUM(VALUE) DESC) rnk
                                FROM   gv$sql_monitor
                                JOIN   gv$sql_monitor_sesstat
                                USING  (inst_id, KEY) NATURAL
                                JOIN   v$statname
                                WHERE  VALUE > 0
                                AND    dbop_name = dopename
                                AND    DBOP_EXEC_ID = dopeid
                                GROUP  BY NAME)
                        GROUP  BY CEIL(rnk / 3)
                        ORDER  BY stat_value#1 DESC NULLS LAST)
                WHERE  ROWNUM <= 30;
            sq_id     := NULL;
            keyw      := NULL;
            plan_hash := NULL;
        $END
        :C2 := C2;
    END IF;
    
    IF sq_id IS NOT NULL AND '&option' IS NULL THEN
        --EXECUTE IMMEDIATE 'alter session set "_sqlmon_max_planlines"=3000';
        sql_exec := :V2;
        IF sql_exec IS NULL THEN
            select max(sql_exec_id) keep(dense_rank last order by sql_exec_start),
                   max(sql_exec_start)
            into  sql_exec,sql_start
            from  gv$sql_monitor
            where sql_id=sq_id
            AND   PX_SERVER# IS NULL
            and   inst_id=nvl(inst,inst_id);
        END IF;
        OPEN :c FOR
            SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => '&format-SQL_FULLTEXT-SQL_TEXT', TYPE => 'TEXT', sql_id => sq_id, SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec, inst_id => inst) AS report FROM   dual;
        BEGIN
            content  := DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => 'ALL', TYPE => 'EM', sql_id => sq_id,  SQL_EXEC_START=>sql_start,SQL_EXEC_ID => sql_exec, inst_id => inst);
            filename := 'sqlm_' || sq_id || '.html';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        --refer to https://ctandrewsayer.wordpress.com/2017/10/19/how-many-rows-were-insertedupdateddeleted-in-my-merge/
        $IF dbms_db_version.version>11 $THEN
            OPEN c2 FOR
            SELECT up.plan_line_id,sms.name,UP.type,count(1) processes, 
                   decode(decode(up.type,5,max(up.typ1),up.type),
                                 1,sum(up.value)
                                 ,2,sum(up.value)
                                 ,3,sum(up.value)
                                 ,4,max(up.value)
                                 ,min(up.value)) calc_tmb,
                   decode(decode(up.type,5,max(up.typ1),up.type),
                                 1,sum(up.value)
                                 ,2,sum(up.value)
                                 ,3,sum(up.value)
                                 ,4,max(up.value)
                                 ,min(up.value)) calc_kmg,
                   dop_down.value_text, sms.description
            FROM   (SELECT *
                    FROM   (SELECT process_name,
                                   plan_line_id,
                                   otherstat_1_id,
                                   otherstat_1_type,
                                   otherstat_1_value,
                                   otherstat_2_id,
                                   otherstat_2_type,
                                   otherstat_2_value,
                                   otherstat_3_id,
                                   otherstat_3_type,
                                   otherstat_3_value,
                                   otherstat_4_id,
                                   otherstat_4_type,
                                   otherstat_4_value,
                                   otherstat_5_id,
                                   otherstat_5_type,
                                   otherstat_5_value,
                                   otherstat_6_id,
                                   otherstat_6_type,
                                   otherstat_6_value,
                                   otherstat_7_id,
                                   otherstat_7_type,
                                   otherstat_7_value,
                                   otherstat_8_id,
                                   otherstat_8_type,
                                   otherstat_8_value,
                                   otherstat_9_id,
                                   otherstat_9_type,
                                   otherstat_9_value,
                                   otherstat_10_id,
                                   otherstat_10_type,
                                   otherstat_10_value
                            FROM   gv$sql_plan_monitor spm
                            WHERE  spm.sql_id = sq_id
                            AND    spm.sql_exec_id = sql_exec
                            AND    sql_exec_start=sql_start) --
                           unpivot((typ1,id, TYPE, VALUE) --
                           FOR pivId IN((otherstat_1_type,otherstat_1_id, otherstat_1_type, otherstat_1_value) AS 1, (otherstat_1_type,otherstat_2_id, otherstat_2_type, otherstat_2_value) AS 2,
                                        (otherstat_1_type,otherstat_3_id, otherstat_3_type, otherstat_3_value) AS 3, (otherstat_1_type,otherstat_4_id, otherstat_4_type, otherstat_4_value) AS 4,
                                        (otherstat_1_type,otherstat_5_id, otherstat_5_type, otherstat_5_value) AS 5, (otherstat_1_type,otherstat_6_id, otherstat_6_type, otherstat_6_value) AS 6,
                                        (otherstat_1_type,otherstat_7_id, otherstat_7_type, otherstat_7_value) AS 7, (otherstat_1_type,otherstat_8_id, otherstat_8_type, otherstat_8_value) AS 8,
                                        (otherstat_1_type,otherstat_9_id, otherstat_9_type, otherstat_9_value) AS 9, (otherstat_1_type,otherstat_10_id, otherstat_10_type, otherstat_10_value) AS 10))) up
            LEFT   JOIN v$sql_monitor_statname sms
            ON     up.id = sms.id
            LEFT   JOIN (SELECT 'downgrade reason' NAME, 350 VALUE, 'DOP downgrade due to adaptive DOP' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 351 VALUE, 'DOP downgrade due to resource manager max DOP' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 352 VALUE, 'DOP downgrade due to insufficient number of processes' value_text
                         FROM   dual
                         UNION ALL
                         SELECT 'downgrade reason' NAME, 353 VALUE, 'DOP downgrade because slaves failed to join' value_text
                         FROM   dual) dop_down
            ON     sms.name = dop_down.name
            AND    up.value = dop_down.value
            WHERE  up.value IS NOT NULL
            group  by  up.plan_line_id, sms.name,up.type, dop_down.value_text, sms.description
            ORDER  BY 1, 2;
        $END
        
        :c1 := c2; 
    ELSE
        OPEN :c FOR
            SELECT *
            FROM   (SELECT   a.sql_id &OPTION,
                             &option1 to_char(MIN(sql_exec_start), 'MMDD HH24:MI:SS') first_seen,
                             to_char(MAX(last_refresh_time), 'MMDD HH24:MI:SS') last_seen,
                             MAX(sid || ',@' || inst_id) keep(dense_rank LAST ORDER BY last_refresh_time) last_sid,
                             MAX(status) keep(dense_rank LAST ORDER BY last_refresh_time, sid) last_status,
                             round(sum(last_refresh_time - sql_exec_start)/&avg * 86400, 2) dur,
                             round(sum(ela)/&avg * 1e-6, 2) ela,
                             round(sum(QUEUING_TIME)/&avg * 1e-6, 2) QUEUE,
                             round(sum(CPU_TIME)/&avg * 1e-6, 2) CPU,
                             round(sum(APPLICATION_WAIT_TIME)/&avg * 1e-6, 2) app,
                             round(sum(CONCURRENCY_WAIT_TIME)/&avg * 1e-6, 2) cc,
                             round(sum(CLUSTER_WAIT_TIME)/&avg * 1e-6, 2) cl,
                             round(sum(PLSQL_EXEC_TIME)/&avg * 1e-6, 2) plsql,
                             round(sum(JAVA_EXEC_TIME)/&avg * 1e-6, 2) JAVA,
                             round(sum(USER_IO_WAIT_TIME)/&avg * 1e-6, 2) io,
                             round(sum(PHYSICAL_READ_BYTES)/&avg, 2) READ,
                             round(sum(PHYSICAL_WRITE_BYTES)/&avg, 2) WRITE,
                             &ver round(sum(IO_CELL_OFFLOAD_ELIGIBLE_BYTES)/&avg,2) OFL,
                             substr(regexp_replace(regexp_replace(MAX(sql_text), '^\s+'), '\s+', ' '), 1, 200) sql_text
                    FROM   (select sql_id,sql_exec_start,sql_exec_id,
                                     max(NVL2(PX_QCSID,null,SQL_PLAN_HASH_VALUE)) plan_hash,
                                     max(NVL2(PX_QCSID,null,SQL_PLAN_HASH_VALUE)) SQL_PLAN_HASH_VALUE,
                                     max(NVL2(PX_QCSID,null,sid)) sid,
                                     max(NVL2(PX_QCSID,null,inst_id)) inst_id,
                                     max(NVL2(PX_QCSID,null,sql_text)) sql_text,
                                     max(NVL2(PX_QCSID,null,status)) status,
                                     max(last_refresh_time) last_refresh_time,
                                     sum(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME)) ela,
                                     sum(ELAPSED_TIME) ELAPSED_TIME,
                                     sum(CPU_TIME) cpu_time,
                                     sum(QUEUING_TIME) QUEUING_TIME,
                                     sum(APPLICATION_WAIT_TIME) APPLICATION_WAIT_TIME,
                                     SUM(CONCURRENCY_WAIT_TIME) CONCURRENCY_WAIT_TIME,
                                     SUM(CLUSTER_WAIT_TIME) CLUSTER_WAIT_TIME,
                                     SUM(PLSQL_EXEC_TIME) PLSQL_EXEC_TIME,
                                     SUM(JAVA_EXEC_TIME) JAVA_EXEC_TIME,
                                     SUM(USER_IO_WAIT_TIME) USER_IO_WAIT_TIME,
                                     SUM(PHYSICAL_WRITE_BYTES) PHYSICAL_WRITE_BYTES,
                                     SUM(PHYSICAL_READ_BYTES) PHYSICAL_READ_BYTES
                                     &ver ,SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) IO_CELL_OFFLOAD_ELIGIBLE_BYTES
                              FROM  gv$sql_monitor a
                              WHERE (&filter)
                              GROUP BY sql_id,sql_exec_start,sql_exec_id) a
                    WHERE  (&SNAP=1 OR (plan_hash IS NULL AND :V2 IS NOT NULL OR NOT regexp_like(upper(TRIM(SQL_TEXT)), '^(BEGIN|DECLARE|CALL)')))
                    AND    (&SNAP=1 OR (keyw IS NULL OR a.sql_id ||'_'|| sql_plan_hash_value||'_'|| sql_exec_id || lower(sql_text) LIKE '%' || lower(keyw) || '%'))
                    GROUP  BY sql_id &OPTION
                    ORDER  BY last_seen DESC)
            WHERE  ROWNUM <= 100
            ORDER  BY last_seen, ela;
        IF sq_id IS NOT NULL AND '&option' IS NOT NULL THEN
            SELECT /*+no_expand*/ MAX(sql_plan_hash_value) KEEP(DENSE_RANK LAST ORDER BY SQL_EXEC_START) INTO plan_hash 
            FROM  gv$sql_monitor 
            WHERE sql_id = sq_id AND (plan_hash IS NULL OR plan_hash in(sql_exec_id,sql_plan_hash_value));
        
            IF plan_hash IS NOT NULL THEN
                SELECT MIN(sql_exec_start), MAX(last_refresh_time), &uniq
                INTO   start_time, end_time, execs
                FROM   gv$sql_monitor
                WHERE  sql_id = sq_id
                AND    PX_SERVER# IS NULL
                AND    sql_plan_hash_value = plan_hash;
                
                $IF DBMS_DB_VERSION.VERSION>11 AND $$hub =1 $THEN
                    filename := 'sqlhub_' || sq_id || '.html';
                    content  := sys.dbms_perf.report_sql(sql_id => sq_id,
                                                         is_realtime => 1,
                                                         outer_start_time => start_time,
                                                         outer_end_time => end_time,
                                                         selected_start_time => start_time,
                                                         selected_end_time => end_time,
                                                         inst_id => inst,
                                                         dbid => null,
                                                         monitor_list_detail => 20);
                $END
                
                IF counter = 0 THEN
                    counter := execs;
                END IF;
            
                OPEN :c0 FOR
                    SELECT DECODE(phv, plan_hash, '*', ' ') || phv plan_hash,
                           &uniq execs,
                           SUM(nvl2(ERROR_MESSAGE, 1, 0)) errs,
                           round(SUM(FETCHES), 2) FETCHES,
                           to_char(MIN(sql_exec_start), 'MMDD HH24:MI:SS') first_seen,
                           to_char(MAX(last_refresh_time), 'MMDD HH24:MI:SS') last_seen,
                           round(SUM(dur*nvl2(px_qcsid,0,1))/&avg, 2) dur,
                           round(SUM(GREATEST(ELAPSED_TIME,CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME)) * 1e-6 /&avg, 2) ela,
                           round(SUM(QUEUING_TIME) * 1e-6 /&avg, 2) QUEUE,
                           round(SUM(CPU_TIME) * 1e-6 /&avg, 2) CPU,
                           round(SUM(APPLICATION_WAIT_TIME) * 1e-6 /&avg, 2) app,
                           round(SUM(CONCURRENCY_WAIT_TIME) * 1e-6 /&avg, 2) cc,
                           round(SUM(CLUSTER_WAIT_TIME) * 1e-6 /&avg, 2) cl,
                           round(SUM(PLSQL_EXEC_TIME) * 1e-6 /&avg, 2) plsql,
                           round(SUM(JAVA_EXEC_TIME) * 1e-6 /&avg, 2) JAVA,
                           round(SUM(USER_IO_WAIT_TIME) * 1e-6 /&avg, 2) io,
                           round(SUM(io_interconnect_bytes) /&avg, 2) cellio,
                           round(SUM(PHYSICAL_READ_BYTES) /&avg, 2) READ,
                           round(SUM(PHYSICAL_WRITE_BYTES) /&avg, 2) WRITE,
                           round(SUM(DIRECT_WRITES) /&avg, 2) dxwrite,
                           round(SUM(BUFFER_GETS)*8192 /&avg, 2) buffget,
                           &ver round(SUM(IO_CELL_OFFLOAD_ELIGIBLE_BYTES) /&avg, 2) offload,
                           &ver round(SUM(IO_CELL_OFFLOAD_RETURNED_BYTES) /&avg, 2) offlrtn,
                           MAX(PX_MAXDOP) DOP,
                           MAX(DOPS) SIDS,
                           regexp_replace(MAX(ERROR_MESSAGE) keep(dense_rank LAST ORDER BY nvl2(ERROR_MESSAGE, last_refresh_time, NULL) NULLS FIRST),'\s+', ' ') last_error
                    FROM   (SELECT a.*,sql_plan_hash_value phv,
                                   max(greatest((last_refresh_time-sql_exec_start)*86400,ELAPSED_TIME*1e-6,(CPU_TIME+APPLICATION_WAIT_TIME+CONCURRENCY_WAIT_TIME+CLUSTER_WAIT_TIME+USER_IO_WAIT_TIME+QUEUING_TIME)*1e-6))  over(partition by sql_exec_id,sql_exec_start) dur,
                                   count(distinct inst_id||','||sid) over(partition by sql_exec_id,sql_exec_start) dops 
                            FROM gv$sql_monitor a WHERE sql_id = sq_id) b
                    GROUP  BY phv
                    ORDER  BY decode(phv, plan_hash, SYSDATE + 1, MAX(last_refresh_time));
            
                OPEN :c1 FOR
                    WITH ASH AS
                     (SELECT /*+materialize*/id, SUM(cnt) aas, MAX(SUBSTR(event, 1, 30) || '(' || cnt || ')') keep(dense_rank LAST ORDER BY cnt) top_event
                      FROM   (SELECT id, nvl(event, 'ON CPU') event, round(SUM(flag) / counter, 3) cnt
                              FROM   (SELECT a.*, rank() over(PARTITION BY sql_exec_id,sql_exec_start ORDER BY flag) r
                                      FROM   (SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id,sql_exec_start, 1 flag
                                              FROM   gv$active_session_history
                                              WHERE  sql_id = sq_id
                                              AND    sql_plan_hash_value = plan_hash
                                              AND    sample_time BETWEEN start_time AND end_time
                                              UNION ALL
                                              SELECT SQL_PLAN_LINE_ID id, event, current_obj#, sql_exec_id,sql_exec_start, 10 flag
                                              FROM   dba_hist_active_sess_history
                                              WHERE  sql_id = sq_id
                                              AND    sql_plan_hash_value = plan_hash
                                              AND    sample_time BETWEEN start_time AND end_time) a)
                              WHERE  r = 1
                              GROUP  BY id, event)
                      GROUP  BY id),
                    SQLM as (SELECT /*+materialize*/ plan_line_id ID,
                                   MAX(plan_parent_id) pid,
                                   MIN(lpad(' ', plan_depth, ' ') || plan_operation || NULLIF(' ' || plan_options, ' ')) operation,
                                   MAX(plan_object_name) name,
                                   round(SUM(TIME*flag), 3) TIME,
                                   round(SUM(TIME*flag) / NULLIF(SUM(tick*flag),0), 2) "%",
                                   --MAX(plan_cost) est_cost,
                                   MAX(plan_cardinality) est_rows,
                                   round(SUM(output_rows) / execs, 2) act_rows,
                                   round(SUM(starts) / execs, 2) avg_exec,
                                   round(SUM(output_rows) / counter, 3) outputs,
                                   round(SUM(io_interconnect_bytes) / counter, 3) cellio,
                                   round(SUM(physical_read_bytes + physical_write_bytes) / counter, 3) iosize,
                                   round(SUM(physical_read_requests + physical_write_requests) / counter, 3) ioreq,
                                   MAX(workarea_max_mem) mem,
                                   MAX(workarea_max_tempseg) temp
                            FROM   (SELECT a.*,
                                           decode(a.sql_exec_start,max(a.sql_exec_start) over(),1,0) flag,                            
                                           ((b.last_refresh_time - b.sql_exec_start)*86400+1)*NVL2(b.px_qcsid,0,1) tick,
                                           max((a.last_change_time-a.first_change_time)*86400+1) over(partition by a.sql_exec_id,a.sql_exec_start,a.plan_line_id) TIME
                                    FROM   gv$sql_plan_monitor a, gv$sql_monitor b
                                    WHERE  b.sql_id = sq_id
                                    AND    b.sql_plan_hash_value = plan_hash
                                    AND    b.sql_id = a.sql_id
                                    AND    b.sql_exec_id = a.sql_exec_id
                                    AND    b.sql_exec_start=a.sql_exec_start
                                    AND    b.key=a.key
                                    AND    b.inst_id = a.inst_id
                                    AND    b.sid = a.sid
                                    AND    b.sql_plan_hash_value = a.sql_plan_hash_value)
                            GROUP  BY plan_line_id)
                    SELECT row_number() over(ORDER BY rownum DESC) OID, m.*
                    FROM   (select * FROM (SELECT * FROM SQLM LEFT JOIN ash USING (id)) START WITH ID = (SELECT MIN(id) FROM SQLM) CONNECT BY PRIOR id = pid ORDER SIBLINGS BY id DESC) m
                    ORDER  BY id;
                
            END IF;
        END IF;
    END IF;
    :rs       := content;
    :filename := filename;
END;
/
print c;
set colsep |
col stat_value#1,stat_value#2,stat_value#3 format #,##0
print c0;
print c1;
print c2;
save rs filename
