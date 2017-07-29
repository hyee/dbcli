/*[[
    Get resource usage from SQL monitor. Usage: @@NAME {sql_id [<SQL_EXEC_ID>] [-l|-a|-s]} | {. <keyword>} [-u|-f"<filter>"]
    Related parameters for SQL monitor: 
        _sqlmon_recycle_time,_sqlmon_max_planlines,_sqlmon_max_plan,_sqlmon_threshold,control_management_pack_access,statistics_level
    -u: Only show the SQL list within current schema
    -l: List the records related to the specific SQL_ID
    -f: List the records that match the predicates, i.e.: -f"MODULE='DBMS_SCHEDULER'"
    -s: Plan format is "ALL-SESSIONS-SQL_FULLTEXT-SQL_TEXT", this is the default
    -a: Plan format is "ALL-SQL_FULLTEXT-SQL_TEXT"
    
   --[[
      @CHECK_VERSION: 11.0={1}
      &option: default={}, l={,sql_exec_id}
      &filter: default={1=1},f={},l={sql_id=:V1},u={username=sys_context('userenv','current_schema')}
      &format: default={BASIC+PLAN+BINDS},s={ALL-SESSIONS}, a={ALL} 
   --]]
]]*/

set feed off VERIFY off
var c refcursor;
var rs CLOB;
var filename varchar2;
DECLARE
BEGIN
    IF :V1 IS NOT NULL AND '&option' IS NULL THEN
        execute immediate 'alter session set "_sqlmon_max_planlines"=3000';
        OPEN :c FOR
            SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => '&format-SQL_FULLTEXT-SQL_TEXT',
                                                    TYPE         => 'TEXT',
                                                    sql_id       => :V1,
                                                    SQL_EXEC_ID  => :V2,
                                                    inst_id      => :INSTANCE) AS report
            FROM   dual;
        BEGIN
            :rs:=DBMS_SQLTUNE.REPORT_SQL_MONITOR(report_level => 'ALL',TYPE=> 'ACTIVE',sql_id=> :V1,SQL_EXEC_ID=> :V2) ;
            :filename:='sqlm_'||:V1||'.html';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    ELSE
        OPEN :c FOR
            SELECT *
            FROM   (SELECT /*+no_expand*/
                           a.sql_id &option,count(1) seens, 
                           to_char(min(first_refresh_time),'MMDD HH24:MI:SS') first_seen,
                           to_char(max(last_refresh_time),'MMDD HH24:MI:SS') last_seen,
                           max(sid||',@'||inst_id) keep(dense_rank last order by last_refresh_time) last_sid,
                           max(status) keep(dense_rank last order by last_refresh_time,sid) last_status,
                           round(SUM(ELAPSED_TIME)*1e-6/60,2) ela, round(SUM(QUEUING_TIME)*1e-6,2) QUEUE, 
                           round(SUM(CPU_TIME)*1e-6/60,2) CPU, round(SUM(APPLICATION_WAIT_TIME)*1e-6/60,2) app,
                           round(SUM(CONCURRENCY_WAIT_TIME)*1e-6/60,2) cc, 
                           round(SUM(CLUSTER_WAIT_TIME)*1e-6/60,2) cl, 
                           round(SUM(PLSQL_EXEC_TIME)*1e-6/60,2) plsql, 
                           round(SUM(JAVA_EXEC_TIME)*1e-6/60,2) JAVA, round(SUM(USER_IO_WAIT_TIME)*1e-6/60,2) io,
                           round(SUM(PHYSICAL_READ_BYTES)/1024/1024,2) read_mb, round(SUM(PHYSICAL_WRITE_BYTES)/1024/1024,2) write_mb,
                           substr(regexp_replace(regexp_replace(max(sql_text),'^\s+|[' || CHR(10) || CHR(13) || ']'),'\s{2,}',' '),1,200) sql_text
                     FROM   gv$sql_monitor a
                     WHERE  NOT regexp_like(a.process_name, '^[pP]\d+$')
                     AND    (:V2 IS NOT NULL or NOT regexp_like(upper(trim(SQL_TEXT)),'^(BEGIN|DECLARE|CALL)'))
                     AND    a.sql_id || lower(sql_text) LIKE '%' || lower(:V2) || '%'
                     AND    (&filter)
                     GROUP BY sql_id &option
                     ORDER  BY last_seen DESC)
            WHERE  ROWNUM <= 100
            ORDER  BY last_seen, ela;
    END IF;
END;
/
print c;
save rs filename
