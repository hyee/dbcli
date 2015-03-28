@@&&edb360_0g.tkprof.sql
DEF section_id = '1b';
DEF section_name = 'Security';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Users';
DEF main_table = 'DBA_USERS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_users
 ORDER BY username
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Profiles';
DEF main_table = 'DBA_PROFILES';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_profiles
 ORDER BY profile
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Users With Sensitive Roles Granted';
DEF main_table = 'DBA_ROLE_PRIVS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       p.* from dba_role_privs p
where (p.granted_role in 
(''AQ_ADMINISTRATOR_ROLE'',''DELETE_CATALOG_ROLE'',''DBA'',''DM_CATALOG_ROLE'',''EXECUTE_CATALOG_ROLE'',
''EXP_FULL_DATABASE'',''GATHER_SYSTEM_STATISTICS'',''HS_ADMIN_ROLE'',''IMP_FULL_DATABASE'',
   ''JAVASYSPRIV'',''JAVA_ADMIN'',''JAVA_DEPLOY'',''LOGSTDBY_ADMINISTRATOR'',
   ''OEM_MONITOR'',''OLAP_DBA'',''RECOVERY_CATALOG_OWNER'',''SCHEDULER_ADMIN'',
   ''SELECT_CATALOG_ROLE'',''WM_ADMIN_ROLE'',''XDBADMIN'',''RESOURCE'')
    or p.granted_role like ''%ANY%'')
   and p.grantee not in &&exclusion_list.
   and p.grantee not in &&exclusion_list2.
   and p.grantee in (select username from dba_users)
order by p.grantee, p.granted_role
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Users With Inappropriate Tablespaces Granted';
DEF main_table = 'DBA_USERS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       * from dba_users
where (default_tablespace in (''SYSAUX'',''SYSTEM'') or
temporary_tablespace not in
   (select tablespace_name
   from dba_tablespaces
   where contents = ''TEMPORARY''
   and status = ''ONLINE''))
and username not in &&exclusion_list.
and username not in &&exclusion_list2.
order by username
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Proxy Users';
DEF main_table = 'PROXY_USERS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ *
  FROM proxy_users
 ORDER BY client';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Profile Verification Functions';
DEF main_table = 'DBA_PROFILES';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       owner, object_name, created, last_ddl_time, status
  FROM dba_objects
 WHERE object_name IN (SELECT limit
                         FROM dba_profiles
                        WHERE resource_name = ''PASSWORD_VERIFY_FUNCTION'')
 ORDER BY 1,2';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Users with CREATE SESSION privilege';
DEF main_table = 'DBA_USERS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ DISTINCT 
       u.NAME "SCHEMA", d.account_status
  FROM SYS.user$ u, SYS.dba_users d
 WHERE u.NAME = d.username
   AND d.account_status NOT LIKE ''%LOCKED%''
   AND u.type# = 1
   AND u.NAME != ''SYS''
   AND u.NAME != ''SYSTEM''
   AND u.user# IN (
              SELECT     grantee#
                    FROM SYS.sysauth$
              CONNECT BY PRIOR grantee# = privilege#
              START WITH privilege# =
                                     (SELECT PRIVILEGE
                                        FROM SYS.system_privilege_map
                                       WHERE NAME = ''CREATE SESSION''))
   AND u.NAME IN (SELECT DISTINCT owner
                    FROM dba_objects
                   WHERE object_type != ''SYNONYM'')
ORDER BY 1';
END;
/
@@edb360_9a_pre_one.sql




