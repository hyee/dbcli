/*[[Get SQL Monitor report from dba_hist_reports, supports 12c only. Usage: @@NAME {[sql_id|report_id] [YYYYMMDDHH24MI] [YYYYMMDDHH24MI]} [-f"<filter>"]
  --[[
    @ver: 12.1={}
    &filter: default={1=1}, f={} 
  --]]
]]*/

SET FEED OFF verify off
VAR report CLOB;
VAR cur REFCURSOR;
col DURATION format itv
DECLARE
    v_report_id int:= regexp_substr(:V1,'^\d+$');
    v_sql_id    VARCHAR2(30);
    v_report    clob;
BEGIN
    IF v_report_id IS NULL THEN
        OPEN :cur FOR
            SELECT * FROM (
                SELECT SNAP_ID,REPORT_ID,KEY1 SQL_ID,KEY2 SQL_EXEC_ID,
                       PERIOD_START_TIME,(PERIOD_END_TIME-PERIOD_START_TIME)*86400 DURATION,
                       SESSION_ID|| ',' || SESSION_SERIAL# || ',@' || INSTANCE_NUMBER session#,
                       EXTRACTVALUE(XMLTYPE(REPORT_SUMMARY),'//service') service,
                       EXTRACTVALUE(XMLTYPE(REPORT_SUMMARY),'//program') program,
                       substr(trim(regexp_replace(REPLACE(EXTRACTVALUE(XMLTYPE(REPORT_SUMMARY),'//sql_text'), chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' ')),1,200) SQL_TEXT
                FROM  dba_hist_reports reps
                WHERE reps.COMPONENT_NAME='sqlmonitor'
                AND   KEY1=nvl(v_sql_id,KEY1)
                AND   PERIOD_START_TIME<=NVL(to_date(NVL(:V3,:ENDTIME),'yymmddhh24mi'),sysdate)
                AND   PERIOD_END_TIME>=NVL(to_date(NVL(:V2,:STARTTIME),'yymmddhh24mi'),sysdate-30)
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