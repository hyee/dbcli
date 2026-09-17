/*[[
   Show information about the current connection
   --[[
      @ctn: 12={sys_context('userenv','con_name') current_container,}, default={}
   --]]
]]*/
set feed off


PRO Session Optimizer Env:
PRO ======================
SELECT * FROM v$ses_optimizer_env WHERE sid=userenv('sid') ORDER BY 3;

PRO Session Object Cache:
PRO =====================
set pivot 1
SELECT * FROM v$session_object_cache;


var pcur refcursor;
DECLARE
    pcur SYS_REFCURSOR;
BEGIN
    $IF dbms_db_version.version < 11 $THEN
        OPEN pcur for
            SELECT u_dump.value || '/' || sys_context('userenv','instance_name') || '_ora_' || p.spid ||
                   nvl2(p.traceid, '_' || p.traceid, NULL) || '.trc' "Trace File"
            FROM   v$parameter u_dump
            CROSS  JOIN v$process p
            JOIN   v$session s
            ON     p.addr = s.paddr
            WHERE  u_dump.name = 'user_dump_dest'
            AND    s.audsid = sys_context('userenv', 'sessionid');
    $ELSE
        OPEN pcur for SELECT value "Trace File" FROM v$diag_info WHERE name='Default Trace File';
    $END
    :pcur := pcur;
END;
/

SELECT /*INTERNAL_DBCLI_CMD*/ user username,sys_context('userenv','current_schema') current_schema,
       (SELECT value FROM nls_database_parameters WHERE parameter='NLS_RDBMS_VERSION') version,
       sys_context('userenv','language') lang,
       (SELECT sid FROM v$mystat WHERE ROWNUM<2) sid,
       (SELECT instance_number FROM v$instance WHERE ROWNUM<2) inst_id,
       &ctn
       sys_context('userenv','isdba') is_sysdba
FROM   dual;
