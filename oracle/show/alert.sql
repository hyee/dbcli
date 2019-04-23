/*[[Show alert information(dba_outstanding_alerts/dba_alert_history).
    --[[
        @check_version: 11.0={}
        @check_access: dba_outstanding_alerts/dba_alert_history={}
    --]]
]]*/
SET FEED OFF
PRO Recent 50 historical alerts:
PRO ============================
SELECT * from (SELECT * FROM dba_alert_history a ORDER BY 1 desc) where rownum<=50 order by 1;

PRO Active alerts:
PRO ==============
select * from dba_outstanding_alerts order by 1;