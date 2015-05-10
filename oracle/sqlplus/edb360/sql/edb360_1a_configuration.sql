@@&&edb360_0g.tkprof.sql
DEF section_id = '1a';
DEF section_name = 'Database Configuration';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Identification';
DEF main_table = 'V$DATABASE';
BEGIN
  :sql_text := '
SELECT d.dbid,
       d.name dbname,
       d.db_unique_name,
       d.platform_name,
       i.version,
       i.inst_id,
       i.instance_number,
       i.instance_name,
       LOWER(SUBSTR(i.host_name||''.'', 1, INSTR(i.host_name||''.'', ''.'') - 1)) host_name,
       p.value cpu_count,
       ''&&ebs_release.'' ebs_release,
       ''&&ebs_system_name.'' ebs_system_name,
       ''&&siebel_schema.'' siebel_schema,
       ''&&siebel_app_ver.'' siebel_app_ver,
       ''&&psft_schema.'' psft_schema,
       ''&&psft_tools_rel.'' psft_tools_rel
  FROM v$database d,
       gv$instance i,
       gv$system_parameter2 p
 WHERE p.inst_id = i.inst_id
   AND p.name = ''cpu_count''
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'Version';
DEF main_table = 'V$VERSION';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$version
';
END;				
/
@@edb360_9a_pre_one.sql

DEF title = 'Database';
DEF main_table = 'V$DATABASE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$database
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Instance';
DEF main_table = 'GV$INSTANCE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$instance
 ORDER BY
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Database and Instance History';
DEF main_table = 'DBA_HIST_DATABASE_INSTANCE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       dbid,				
       instance_number,	
       startup_time,		
       version,			
       db_name,			
       instance_name,		
       host_name,			
       platform_name	
  FROM dba_hist_database_instance
 ORDER BY
       dbid,				
       instance_number,	
       startup_time
';
END;				
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'Instance Recovery';
DEF main_table = 'GV$INSTANCE_RECOVERY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$instance_recovery
 ORDER BY
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Database Properties';
DEF main_table = 'DATABASE_PROPERTIES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM database_properties
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Registry';
DEF main_table = 'DBA_REGISTRY';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_registry
 ORDER BY
       comp_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Registry History';
DEF main_table = 'DBA_REGISTRY_HISTORY';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_registry_history
 ORDER BY
       1
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Registry Hierarchy';
DEF main_table = 'DBA_REGISTRY_HIERARCHY';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_registry_hierarchy
 ORDER BY
       1, 2, 3
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Feature Usage Statistics';
DEF main_table = 'DBA_FEATURE_USAGE_STATISTICS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_feature_usage_statistics
 ORDER BY
       name,
       version
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'License';
DEF main_table = 'GV$LICENSE';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$license
 ORDER BY
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Resource Limit';
DEF main_table = 'GV$RESOURCE_LIMIT';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$resource_limit
 ORDER BY
       resource_name,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'HWM Statistics';
DEF main_table = 'DBA_HIGH_WATER_MARK_STATISTICS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_high_water_mark_statistics
 ORDER BY
       dbid,
       name
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'Database Links';
DEF main_table = 'DBA_DB_LINKS';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_db_links
 ORDER BY
       owner,
       db_link
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Modified Parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$system_parameter2
 WHERE ismodified = ''MODIFIED''
 ORDER BY
       name,
       inst_id,
       ordinal
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Non-default Parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$system_parameter2
 WHERE isdefault = ''FALSE''
 ORDER BY
       name,
       inst_id,
       ordinal
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'All Parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$system_parameter2
 ORDER BY
       name,
       inst_id,
       ordinal
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Parameter File';
DEF main_table = 'V$SPPARAMETER';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$spparameter
 WHERE isspecified = ''TRUE''
 ORDER BY
       name,
       sid,
       ordinal
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'System Parameters Change Log';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
WITH 
all_parameters AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       snap_id,
       dbid,
       instance_number,
       parameter_name,
       value,
       isdefault,
       ismodified,
       lag(value) OVER (PARTITION BY dbid, instance_number, parameter_hash ORDER BY snap_id) prior_value
  FROM dba_hist_parameter
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
)
SELECT /*+ &&top_level_hints. */
       TO_CHAR(s.begin_interval_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(s.end_interval_time, ''YYYY-MM-DD HH24:MI'') end_time,
       p.snap_id,
       --p.dbid,
       p.instance_number,
       p.parameter_name,
       p.value,
       p.isdefault,
       p.ismodified,
       p.prior_value
  FROM all_parameters p,
       dba_hist_snapshot s
 WHERE p.value != p.prior_value
   AND s.snap_id = p.snap_id
   AND s.dbid = p.dbid
   AND s.instance_number = p.instance_number
 ORDER BY
       s.begin_interval_time DESC,
       --p.dbid,
       p.instance_number,
       p.parameter_name
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'SQLTXPLAIN Version';
DEF main_table = 'SQLTXPLAIN.SQLI$_PARAMETER';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
sqltxplain.sqlt$a.get_param(''tool_version'') sqlt_version,
sqltxplain.sqlt$a.get_param(''tool_date'') sqlt_version_date,
sqltxplain.sqlt$a.get_param(''install_date'') install_date
FROM DUAL
';
END;
/
@@edb360_9a_pre_one.sql




