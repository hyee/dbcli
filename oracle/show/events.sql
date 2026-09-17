/*[[Show the events enabled at session, process or system level. Usage: @@NAME [-session|-system|-process]
    -session : Dump the events enabled for the current session (default)
    -process : Dump the events enabled for the current process
    -system  : Dump the events enabled at system level
    The events are dumped into the default trace file, and listed when
    v$diag_trace_file_contents is accessible.
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
    EXECUTE IMMEDIATE 'alter session set tracefile_identifier='''||ran||'''';
    EXECUTE IMMEDIATE q'[alter session set events 'immediate eventdump(&target)']';
    $IF &check_access_diag=0 $THEN
        dbms_output.put_line('write events into default trace file, please run "loadtrace default" to download to tracefile.');
    $ELSE
        OPEN c FOR
            SELECT TIMESTAMP,payload
            FROM   v$diag_trace_file_contents
            WHERE  adr_home=(SELECT value FROM v$diag_info WHERE name='ADR Home')
            AND    trace_filename=(SELECT regexp_substr(value,'[^\\/]+$') FROM v$diag_info WHERE name='Default Trace File' )
            AND    record_level>0
            AND    session_id>0;
    $END
    :c := c;
END;
/