/*[[Get real-time ADDM report, supports 12c only. Usage: @@NAME [report_id]
  --[[
    @ver: 12.1={}
  --]]
]]*/

SET FEED OFF verify off
VAR report CLOB;
VAR cur REFCURSOR;
DECLARE
    v_report_id int:= regexp_substr(:V1,'^\d+$');
    v_report    clob;
    v_version   varchar2(30);
BEGIN
    OPEN :cur FOR
        SELECT REPORT_ID,SNAP_ID,DBID,INSTANCE_NUMBER,COMPONENT_ID,PERIOD_START_TIME,
               PERIOD_END_TIME,GENERATION_TIME,reps_xml."trigger_cause", reps_xml."impact"
        FROM  dba_hist_reports  reps,
           XMLTABLE('/report_repository_summary/trigger'
               PASSING XMLTYPE(reps.report_summary)
               COLUMNS "trigger_cause" varchar2(30)
                        PATH '/trigger/@id_desc',
                       "impact" varchar2(30)
                        PATH '/trigger/@impact') reps_xml 
        WHERE reps.COMPONENT_NAME='perf'
        AND   REPORT_ID=nvl(v_report_id,REPORT_ID)
        ORDER BY REPORT_ID DESC;
    IF v_report_id IS NOT NULL THEN
        v_report := dbms_perf.report_addm_watchdog_xml(v_report_id).getClobVal();
        SELECT extractvalue(xmltype(v_report), '/report/@db_version')
        INTO v_version
        FROM dual;

        :report := '<html>
          <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
            <base href="http://download.oracle.com/otn_software/"/>
            <script id="scriptVersion" language="javascript" type="text/javascript">var version = "'|| v_version || '";</script>
            <script id="scriptActiveReportInit" language="javascript" type="text/javascript" src="emviewers/scripts/activeReportInit.js">
              <!-- script defining sendXML() -->
            </script>
          </head>
          <body onload="sendXML();">
            <script type="text/javascript">writeIframe();</script>
            <script id="fxtmodel" type="text/xml">
              <!--FXTMODEL-->'||v_report||'<!--FXTMODEL--></script></body></html>';
    END IF;
END;
/
print cur;
save report last_realtime_addm.html