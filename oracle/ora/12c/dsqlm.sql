/*[[Get SQL Monitor report from dba_hist_reports, supports 12c only. Usage: @@NAME {[sql_id|report_id] [YYYYMMDDHH24MI] [YYYYMMDDHH24MI]} [-f"<filter>"]
  --[[
    @ver: 12.1={}
    &grp   : default={none}, g={g}, d={d}
    &filter: default={1=1}, f={} 
  --]]
]]*/

SET FEED OFF verify off
VAR report CLOB;
VAR cur REFCURSOR;
col DURATION format smhd2
col elapsed format smhd2
col cpuwait format smhd2
col iowait format smhd2
col ccwait format smhd2
col clwait format smhd2
col bfgets format kmg
col ioreads format kmg
col iowrites format kmg
DECLARE
    v_report_id int:= regexp_substr(:V1,'^\d+$');
    v_sql_id    VARCHAR2(30):=:V1;
    v_report    clob;
BEGIN
    IF v_report_id IS NULL THEN
        OPEN :cur FOR
            SELECT * 
            FROM (
                SELECT SNAP_ID,REPORT_ID,KEY1 SQL_ID,EXTRACTVALUE(summary,'//plan_hash') plan_hash, KEY2 SQL_EXEC_ID,
                       PERIOD_START_TIME,
                       (PERIOD_END_TIME-PERIOD_START_TIME)*86400 DURATION,
                       EXTRACTVALUE(summary,'//stat[@name="elapsed_time"]')/1e6 elapsed,
                       EXTRACTVALUE(summary,'//stat[@name="cpu_time"]')/1e6 cpuwait,
                       EXTRACTVALUE(summary,'//stat[@name="user_io_wait_time"]')/1e6 iowait,
                       EXTRACTVALUE(summary,'//stat[@name="concurrency_wait_time"]')/1e6 ccwait,
                       EXTRACTVALUE(summary,'//stat[@name="cluster_wait_time"]')/1e6 clwait,
                       EXTRACTVALUE(summary,'//stat[@name="buffer_gets"]')+0 bfgets,
                       EXTRACTVALUE(summary,'//stat[@name="read_bytes"]')+0 IOreads,
                       EXTRACTVALUE(summary,'//stat[@name="write_bytes"]')+0 IOwrites,
                       SESSION_ID|| ',' || SESSION_SERIAL# || ',@' || INSTANCE_NUMBER session#,
                       EXTRACTVALUE(summary,'//service') service,
                       EXTRACTVALUE(summary,'//program') program,
                       substr(trim(regexp_replace(REPLACE(EXTRACTVALUE(summary,'//sql_text'), chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' ')),1,200) SQL_TEXT
                FROM (SELECT /*+no_merge*/ reps.*,xmltype(REPORT_SUMMARY) summary
                      FROM   dba_hist_reports reps
                      WHERE  reps.COMPONENT_NAME='sqlmonitor'
                      AND    KEY1=nvl(v_sql_id,KEY1)
                      AND    PERIOD_START_TIME<=NVL(to_date(NVL(:V3,:ENDTIME),'yymmddhh24mi'),sysdate)
                      AND    PERIOD_END_TIME>=NVL(to_date(NVL(:V2,:STARTTIME),'yymmddhh24mi'),sysdate-30)) reps
            ) WHERE &filter
            ORDER BY REPORT_ID DESC;
    ELSE
        OPEN :cur for 
            SELECT DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => v_report_id, TYPE => 'text')
            FROM dual;
        :report := DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL(RID => v_report_id, TYPE => 'active');
    END IF;
END;
/
print cur
save report last_dsqlm_report.html