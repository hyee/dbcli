/*[[Show system level enabled events. Usage: @@NAME [-session|-system|-process]
    type: can be session,process or system
    --[[
        &target: session={session} system={system} process={process}
        @check_access_diag: v$diag_trace_file_contents={1} default={0}
    --]]
]]*/
set feed off verify on
var c refcursor
DECLARE
    ran  INT := round(dbms_random.value*1e8);
    c    SYS_REFCURSOR;
BEGIN
    execute immediate 'alter session set tracefile_identifier='''||ran||'''';
    execute immediate q'[alter session set events 'immediate eventdump(&target)']';
    $IF &check_access_diag=0 $THEN
        dbms_output.put_line('write events into default trace file, please run "loadtrace default" to download to tracefile.');
    $ELSE
        OPEN c FOR
            SELECT TIMESTAMP,PAYLOAD
            FROM   v$diag_trace_file_contents
            WHERE  ADR_HOME=(SELECT VALUE FROM v$diag_info WHERE NAME='ADR Home')
            AND    TRACE_FILENAME=(SELECT REGEXP_SUBSTR(VALUE,'[^\\/]+$') FROM v$diag_info WHERE NAME='Default Trace File' ) 
            AND    RECORD_LEVEL>0
            AND    SESSION_ID>0;
    $END
    :c := c;
END;
/