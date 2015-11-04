/*[[Show alert information.
    --[[
        @check_version: 11.0={}
        @check_access: dba_outstanding_alerts/DBA_ALERT_HISTORY={}
    --]]
]]*/
SET FEED OFF
PRO Recent 50 historical alerts:
PRO ============================
SELECT * from (SELECT * FROM DBA_ALERT_HISTORY a ORDER BY 1 desc) where rownum<=50 order by 1;

PRO Active alerts:
PRO ==============
select * from dba_outstanding_alerts order by 1;