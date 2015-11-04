/*[[Show current connection's information]]*/
set feed off printvar off
var ssid VARCHAR2;
var sinst VARCHAR2;
BEGIN
    :ssid := sys_context('userenv','sid');
    :sinst := sys_context('userenv','instance');
END;
/
ora session &ssid

select /*INTERNAL_DBCLI_CMD*/ user username,
               (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_RDBMS_VERSION') version,
                sys_context('userenv','language') lang,
                (select sid from v$mystat where rownum<2) sid,
                (select instance_number from v$instance where rownum<2) inst_id,
                sys_context('userenv','isdba') is_sysdba
from dual;

var pcur refcursor;
DECLARE
    pcur SYS_REFCURSOR;
BEGIN
    $IF DBMS_DB_VERSION.VERSION < 11 $THEN
        open pcur for 
            SELECT u_dump.value || '/' || SYS_CONTEXT('userenv','instance_name') || '_ora_' || p.spid ||
                   nvl2(p.traceid, '_' || p.traceid, NULL) || '.trc' "Trace File"
            FROM   v$parameter u_dump
            CROSS  JOIN v$process p
            JOIN   v$session s
            ON     p.addr = s.paddr
            WHERE  u_dump.name = 'user_dump_dest'
            AND    s.audsid = sys_context('userenv', 'sessionid');
    $ELSE
        open pcur for select value "Trace File" from v$diag_info where name='Default Trace File';
    $END
    :pcur := pcur;
END;
/
print pcur
