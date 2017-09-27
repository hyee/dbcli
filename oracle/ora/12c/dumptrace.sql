/*[[Dump trace file from gv$diag_trace_file, supports 12c only. Usage: @@NAME [trace_file_name] [-f"<filter>"]
  --[[
    @ver: 12.1={}
    &filter: default={1=1}, f={}
    @check_access_trace: gv$diag_trace_file={}
  --]]
]]*/

SET FEED OFF verify off
VAR report CLOB;
VAR cur REFCURSOR;
col DURATION format itv
DECLARE
    v_file VARCHAR2(300):= :V1;
    v_report    clob;
BEGIN
    OPEN :CUR FOR 
        SELECT INST_ID, ADR_HOME||TRACE_FILENAME TRACE_FILENAME, CHANGE_TIME,MODIFY_TIME,CON_ID
        FROM   gv$diag_trace_file
        WHERE  (&filter)
        AND    (v_file IS NULL OR v_file=ADR_HOME||TRACE_FILENAME)
        ORDER  BY CHANGE_TIME DESC;
    IF v_file IS NOT NULL THEN
        DBMS_LOB.CREATETEMPORARY(v_report,TRUE);
        FOR R IN(SELECT * FROM gv$diag_trace_file_contents WHERE v_file=ADR_HOME||TRACE_FILENAME) LOOP
            DBMS_LOB.writeAppend(v_report,length(r.PAYLOAD),r.PAYLOAD);
        END LOOP;
        :report := v_report;
    END IF;
END;
/
print cur;
save report last_trace.txt