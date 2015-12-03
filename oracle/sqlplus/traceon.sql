set feed off verify off
col tracefile_name format a150;
alter session set timed_statistics = true;
alter session set MAX_DUMP_FILE_SIZE = unlimited;
alter session set tracefile_identifier='dbcli';
VAR ver REFCURSOR;
SET SERVEROUTPUT ON
DECLARE
    rs SYS_REFCURSOR;
BEGIN
    $IF DBMS_DB_VERSION.VERSION >10 $THEN
        OPEN rs FOR SELECT VALUE as tracefile_name FROM V$DIAG_INFO WHERE NAME = 'Default Trace File';
    $ELSE
        OPEN rs FOR SELECT u_dump.value || '/' || SYS_CONTEXT('userenv','instance_name') || '_ora_' || p.spid ||
                           nvl2(p.traceid, '_' || p.traceid, NULL) || '.trc' "Trace File"
                    FROM   v$parameter u_dump
                    CROSS  JOIN v$process p
                    JOIN   v$session s
                    ON     p.addr = s.paddr
                    WHERE  u_dump.name = 'user_dump_dest'
                    AND    s.audsid = sys_context('userenv', 'sessionid');
    $END
    :ver := rs;
END;
/
PRINT VER;

Accept lv prompt 'Tracing was enabled with level: '
alter session set events '10046 trace name context forever, level &lv';
set feed on verify on