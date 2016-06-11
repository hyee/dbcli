/*[[
   Show current connection's information
   --[[
      @ctn: 12={sys_context('userenv','con_name') current_container,}, default={}
   --]]
]]*/
set feed off
select /*INTERNAL_DBCLI_CMD*/ user username,sys_context('userenv','current_schema') current_schema,
               (SELECT VALUE FROM Nls_Database_Parameters WHERE parameter='NLS_RDBMS_VERSION') version,
                sys_context('userenv','language') lang,
                (select sid from v$mystat where rownum<2) sid,
                (select instance_number from v$instance where rownum<2) inst_id,
                &ctn
                sys_context('userenv','isdba') is_sysdba
from dual;

PRO Session Optimizer Env:
PRO ======================
select * from v$ses_optimizer_env where sid=userenv('sid') order by 3;

PRO Session Cursor Cache:
PRO =====================
set pivot 1
SELECT * FROM V$SESSION_OBJECT_CACHE;


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

