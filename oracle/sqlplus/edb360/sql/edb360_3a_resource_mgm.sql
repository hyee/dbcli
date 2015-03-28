@@&&edb360_0g.tkprof.sql
DEF section_id = '3a';
DEF section_name = 'Database Resource Management (DBRM)';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Consumer Groups';
DEF main_table = 'DBA_RSRC_CONSUMER_GROUPS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_consumer_groups
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Consumer Group Users and Roles';
DEF main_table = 'DBA_RSRC_CONSUMER_GROUP_PRIVS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_consumer_group_privs
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Groups Mappings';
DEF main_table = 'DBA_RSRC_GROUP_MAPPINGS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_group_mappings
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Groups Mapping Priorities';
DEF main_table = 'DBA_RSRC_MAPPING_PRIORITY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_mapping_priority
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Plan Directives';
DEF main_table = 'DBA_RSRC_PLAN_DIRECTIVES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_plan_directives
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Plans';
DEF main_table = 'DBA_RSRC_PLANS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_rsrc_plans
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Active Resource Consumer Groups';
DEF main_table = 'GV$RSRC_CONSUMER_GROUP';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrc_consumer_group
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Consumer Group History';
DEF main_table = 'GV$RSRC_CONS_GROUP_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrc_cons_group_history
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Plan';
DEF main_table = 'GV$RSRC_PLAN';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrc_plan
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Plan History';
DEF main_table = 'GV$RSRC_PLAN_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrc_plan_history
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'RM Stats per Session';
DEF main_table = 'GV$RSRC_SESSION_INFO';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrc_session_info
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resources Consumed per Consumer Group';
DEF main_table = 'GV$RSRCMGRMETRIC';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrcmgrmetric
 ORDER BY
       1, 2
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'Resources Consumed History';
DEF main_table = 'GV$RSRCMGRMETRIC_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$rsrcmgrmetric_history
 ORDER BY
       1, 2
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql


