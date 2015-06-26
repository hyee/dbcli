DEF section_name = 'Database Configuration';
SPO &&sqld360_main_report..html APP;
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
@@sqld360_9a_pre_one.sql

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
@@sqld360_9a_pre_one.sql

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
@@sqld360_9a_pre_one.sql

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
@@sqld360_9a_pre_one.sql


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
@@sqld360_9a_pre_one.sql

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
@@sqld360_9a_pre_one.sql

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
@@sqld360_9a_pre_one.sql

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
@@_9a_pre_one.sql


COL address NOPRI
COL hash_value NOPRI
COL sql_id NOPRI
COL child_address NOPRI

DEF title = 'Optimizer Environment';
DEF main_table = 'GV$SQL_OPTIMIZER_ENV';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sql_optimizer_env
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, sql_id, child_number, id
';
END;
/
@@sqld360_9a_pre_one.sql

DEF title = 'Non-default Optimizer Environment';
DEF main_table = 'GV$SQL_OPTIMIZER_ENV';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sql_optimizer_env
 WHERE sql_id = ''&&sqld360_sqlid.''
   AND isdefault = ''NO''
 ORDER BY inst_id, sql_id, child_number, id
';
END;
/
@@sqld360_9a_pre_one.sql

COL address PRI
COL hash_value PRI
COL sql_id PRI
COL child_address PRI



DEF title = 'System Stats';
DEF main_table = 'AUX_STATS$';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM sys.aux_stats$
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'IO Calibration';
DEF main_table = 'DBA_RSRC_IO_CALIBRATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_rsrc_io_calibrate
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Non-default Fix Controls';
DEF main_table = 'DBA_RSRC_IO_CALIBRATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM v$system_fix_control
 WHERE is_default = 0
 ORDER BY bugno
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'All Fix Controls';
DEF main_table = 'DBA_RSRC_IO_CALIBRATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM v$system_fix_control
 ORDER BY bugno
';
END;
/
@@sqld360_9a_pre_one.sql


COL addr NOPRI

DEF title = 'Optimizer Processing Rate';
DEF main_table = 'V$OPTIMIZER_PROCESSING_RATE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM v$optimizer_processing_rate
 ORDER BY operation_name 
';
END;
/
@@&&skip_10g.&&skip_11g.sqld360_9a_pre_one.sql

COL addr PRI


--DEF title = 'Alert Log';
--DEF main_table = 'X$DBGALERTEXT';
--BEGIN
--  :sql_text := '
--SELECT /*+ &&top_level_hints. */ 
--       originating_timestamp,
--       message_text
--FROM sys.x$dbgalertext
--WHERE originating_timestamp > SYSDATE - &&history_days.
--ORDER BY originating_timestamp DESC
--';
--END;
--/
--@@&&skip_10g.sqld360_9a_pre_one.sql

--DEF title = 'SQLTXPLAIN Version';
--DEF main_table = 'SQLTXPLAIN.SQLI$_PARAMETER';
--BEGIN
--  :sql_text := '
--SELECT /*+ &&top_level_hints. */ 
--sqltxplain.sqlt$a.get_param(''tool_version'') sqlt_version,
--sqltxplain.sqlt$a.get_param(''tool_date'') sqlt_version_date,
--sqltxplain.sqlt$a.get_param(''install_date'') install_date
--FROM DUAL
--';
--END;
--/
--@@sqld360_9a_pre_one.sql
