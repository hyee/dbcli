@@&&edb360_0g.tkprof.sql
DEF section_id = '1c';
DEF section_name = 'Auditing';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Default Object Auditing Options';
DEF main_table = 'ALL_DEF_AUDIT_OPTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM all_def_audit_opts
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Object Auditing Options';
DEF main_table = 'DBA_OBJ_AUDIT_OPTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       o.*
  FROM dba_obj_audit_opts o
 WHERE (o.alt,o.aud,o.com,o.del,o.gra,o.ind,o.ins,o.loc,o.ren,o.sel,o.upd,o.ref,o.exe,o.fbk,o.rea) NOT IN 
       (SELECT d.alt,d.aud,d.com,d.del,d.gra,d.ind,d.ins,d.loc,d.ren,d.sel,d.upd,d.ref,d.exe,d.fbk,d.rea FROM all_def_audit_opts d)
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Statement Auditing Options';
DEF main_table = 'DBA_STMT_AUDIT_OPTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_stmt_audit_opts
 ORDER BY
       1 NULLS FIRST, 2 NULLS FIRST
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'System Privileges Auditing Options';
DEF main_table = 'DBA_PRIV_AUDIT_OPTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_priv_audit_opts
 ORDER BY
       1 NULLS FIRST, 2 NULLS FIRST
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Audit related Initialization Parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       inst_id, name "PARAMETER", value, isdefault, ismodified
  FROM gv$system_parameter2
 WHERE name LIKE ''%audit%''
 ORDER BY 2,1,3
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Unified Auditing';
DEF main_table = 'V$OPTION';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       value "Unified Auditing"
  FROM v$option
 WHERE parameter = ''Unified Auditing'' 
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Audit Configuration';
DEF main_table = 'DBA_AUDIT_MGMT_CONFIG_PARAMS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_audit_mgmt_config_params
 ORDER BY 1,2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Audit Trail Locations';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       SUBSTR(owner||''.''||table_name,1,30) audit_trail, tablespace_name
  FROM dba_tables
 WHERE table_name IN (''AUD$'',''AUDIT$'',''FGA$'',''FGA_LOG$'')
    OR table_name IN (''UNIFIED_AUDIT_TRAIL'',''CDB_UNIFIED_AUDIT_TRAIL'',''V_$UNIFIED_AUDIT_TRAIL'',''GV_$UNIFIED_AUDIT_TRAIL'') -- 12c UAT
 ORDER BY 1,2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Object Level Privileges (Audit Trail)';
DEF main_table = 'DBA_TAB_PRIVS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       owner || ''.'' || table_name "TABLE", grantee, privilege, grantable
  FROM dba_tab_privs
 WHERE (   table_name IN (''AUD$'',''AUDIT$'',''FGA$'',''FGA_LOG$'')
        OR table_name IN (''UNIFIED_AUDIT_TRAIL'',''CDB_UNIFIED_AUDIT_TRAIL'',''V_$UNIFIED_AUDIT_TRAIL'',''GV_$UNIFIED_AUDIT_TRAIL'') -- 12c UAT
       )
   AND grantee NOT IN (''SYS'',''SYSTEM'',''DBA'',''AUDIT_ADMIN'',''AUDIT_VIEWER'')
   AND owner IN (''SYS'',''SYSTEM'')
 ORDER BY table_name, owner, grantee, privilege
';
END;
/
@@edb360_9a_pre_one.sql
