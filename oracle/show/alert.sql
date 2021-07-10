/*[[Show alert information(dba_outstanding_alerts/dba_alert_history).
    --[[
        @check_version: 11.0={}
        @check_access: dba_outstanding_alerts/dba_alert_history={}
        @check_access_inc: {
            v$diag_incident={
                PRO Recent Problems:
                PRO =================
                SELECT * FROM (
                    SELECT * FROM table(gv$(cursor(select userenv('instance') inst,a.* from v$diag_problem a))) order by lastinc_time desc
                ) WHERE ROWNUM <=10;
                PRO Recent Incidents:
                PRO =================
                SELECT * FROM (
                    SELECT * FROM table(gv$(cursor(select userenv('instance') inst,a.* from v$diag_incident a))) order by create_time desc
                ) WHERE ROWNUM <=30;}
            default={}
        }
    --]]
]]*/
SET FEED OFF
PRO Recent 50 historical alerts:
PRO ============================
SELECT * from (SELECT * FROM dba_alert_history a ORDER BY 1 desc) where rownum<=50 order by 1;

PRO Active alerts(Refer to dbms_server_alert/dba%thresholds/v$alert_types):
PRO =======================================================================
select * from dba_outstanding_alerts order by 1;

&check_access_inc