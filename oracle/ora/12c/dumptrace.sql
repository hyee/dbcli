/*[[
    Dump trace file from gv$diag_trace_file, supports 12c only. Usage: @@NAME [trace_file_name] [-f"<filter>"]

    Without an argument it lists the trace files (newest change_time first); with
    a trace file name it dumps that file's content into the variable <report>,
    which is saved as last_trace.txt below. The name to pass is the two-column
    concatenation ADR_HOME||TRACE_FILENAME as shown in the listing.

    Options:
        -f"<filter>" : an extra WHERE predicate on gv$diag_trace_file, e.g.
                       @@NAME -f"trace_filename like 'O19C_ora%'"
    --[[
        @ver: 12.1={}
        &filter: default={1=1}, f={}
        @check_access_trace: gv$diag_trace_file={}
    --]]
]]*/
set feed off verify off
VAR report CLOB;
VAR cur REFCURSOR;
col duration format itv
DECLARE
    v_file   VARCHAR2(300) := :V1;
    v_report CLOB;
BEGIN
    OPEN :cur FOR
        SELECT inst_id,
               adr_home || trace_filename trace_filename,
               change_time,
               modify_time,
               con_id
        FROM   gv$diag_trace_file
        WHERE  (&filter)
        AND    (v_file IS NULL OR v_file = adr_home || trace_filename)
        ORDER  BY change_time DESC;
    IF v_file IS NOT NULL THEN
        dbms_lob.createtemporary(v_report, TRUE);
        FOR r IN (SELECT *
                  FROM   gv$diag_trace_file_contents
                  WHERE  v_file = adr_home || trace_filename) LOOP
            dbms_lob.writeappend(v_report, length(r.payload), r.payload);
        END LOOP;
        :report := v_report;
    END IF;
END;
/
print cur;
save report last_trace.txt
