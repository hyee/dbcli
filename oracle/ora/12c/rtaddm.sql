/*[[
    Get real-time ADDM report, supports 12c only. Usage: @@NAME [report_id]

    No argument lists the saved ADDM reports (component_name='perf') from
    dba_hist_reports; report_id 0 asks dbms_addm for the real-time report and
    any other report_id dumps that saved report through dbms_perf. Both are
    wrapped into the EM active-report HTML and saved as the file below.
    --[[
        @ver: 12.1={}
    --]]
]]*/

set feed off verify off
VAR report CLOB;
VAR cur REFCURSOR;
DECLARE
    v_report_id INT := regexp_substr(:V1, '^\d+$');
    v_report    CLOB;
    v_version   VARCHAR2(30);
BEGIN
    OPEN :cur FOR
        SELECT report_id,
               snap_id,
               dbid,
               instance_number,
               component_id,
               period_start_time,
               period_end_time,
               generation_time,
               reps_xml."trigger_cause",
               reps_xml."impact"
        FROM   dba_hist_reports reps,
               XMLTABLE('/report_repository_summary/trigger'
                        PASSING xmltype(reps.report_summary)
                        COLUMNS "trigger_cause" VARCHAR2(30) PATH '/trigger/@id_desc',
                                "impact"        VARCHAR2(30) PATH '/trigger/@impact') reps_xml
        WHERE  reps.component_name = 'perf'
        AND    report_id = nvl(v_report_id, report_id)
        ORDER  BY report_id DESC;
    IF v_report_id = 0 THEN
        v_report := dbms_addm.real_time_addm_report();
        :report := q'[<?xml version="1.0" encoding="UTF-8"?><html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
        <base href="http://download.oracle.com/otn_software/"/>
        <script language="javascript" type="text/javascript" src="emviewers/scripts/flashver.js">
        <!--Test flash version-->
        </script>
        <style>
              body { margin: 0px; overflow:hidden }
            </style>
        </head>
        <body scroll="no">
        <script type="text/xml">]'||v_report||q'[<!--FXTMODEL-->
        </script>
        <script id="scriptVersion" language="javascript" type="text/javascript">var version = "12";</script>
        <script language="JavaScript" type="text/javascript" src="emviewers/scripts/loadswf.js">
        
        <!--Load report viewer-->
        </script>
        <iframe name="_history" frameborder="0" scrolling="no" width="22" height="0">
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"/>
        <script type="text/javascript" language="JavaScript1.2" charset="utf-8">
            var v = new top.Vars(top.getSearch(window));
            var fv = v.toString('$_');
        </script>
        </head>
        <body>
        <script type="text/javascript" language="JavaScript1.2" charset="utf-8" src="emviewers/scripts/document.js">
        <!--Run document script-->
        </script>
        </body>
        </html>
        </iframe>
        </body>
        </html>]';
    ELSIF v_report_id IS NOT NULL THEN
        v_report := dbms_perf.report_addm_watchdog_xml(v_report_id).getclobval();
        SELECT extractvalue(xmltype(v_report), '/report/@db_version')
        INTO   v_version
        FROM   dual;

        :report := '<html>
          <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
            <base href="http://download.oracle.com/otn_software/"/>
            <script id="scriptVersion" language="javascript" type="text/javascript">var version = "' || v_version || '";</script>
            <script id="scriptActiveReportInit" language="javascript" type="text/javascript" src="emviewers/scripts/activeReportInit.js">
              <!-- script defining sendXML() -->
            </script>
          </head>
          <body onload="sendXML();">
            <script type="text/javascript">writeIframe();</script>
            <script id="fxtmodel" type="text/xml">
              <!--FXTMODEL-->' || v_report || '<!--FXTMODEL--></script></body></html>';
    END IF;
END;
/
print cur;
save report last_realtime_addm.html