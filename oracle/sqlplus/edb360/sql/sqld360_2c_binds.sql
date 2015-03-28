DEF section_name = 'Binds';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;


DEF title = 'Binds Summary from Memory';
DEF main_table = 'GV$SQL_BIND_CAPTURE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       inst_id, child_number, position, datatype_string, min(value_string) min_value, max(value_string) max_value
  FROM gv$sql_bind_capture 
 WHERE sql_id = ''&&sqld360_sqlid.''
 GROUP BY inst_id, child_number, position, datatype_string
 ORDER BY inst_id, child_number, position, datatype_string
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Binds List from Memory';
DEF main_table = 'GV$SQL_BIND_CAPTURE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sql_bind_capture
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, child_number, position
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Binds Summary from History';
DEF main_table = 'DBA_HIST_SQLBIND';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       instance_number, position, datatype_string, min(value_string) min_value, max(value_string) max_value
  FROM dba_hist_sqlbind
 WHERE sql_id = ''&&sqld360_sqlid.''
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id. 
   AND ''&&diagnostics_pack.'' = ''Y''
 GROUP BY instance_number, position, datatype_string
 ORDER BY instance_number, position, datatype_string
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Binds List from History';
DEF main_table = 'DBA_HIST_SQLBIND';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_hist_sqlbind
 WHERE sql_id = ''&&sqld360_sqlid.''
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id. 
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY snap_id desc, instance_number, position
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'Binds with unstable datatype';
DEF main_table = 'GV$SQL_BIND_CAPTURE';
BEGIN
  :sql_text := '
SELECT name, position, MIN(datatype_string) MIN_DATATYPE, MAX(datatype_string) MAX_DATATYPE
  FROM (SELECT name, position, datatype_string
          FROM gv$sql_bind_capture
         WHERE sql_id = ''&&sqld360_sqlid.''
         UNION
         SELECT name, position, datatype_string
           FROM dba_hist_sqlbind
          WHERE sql_id = ''&&sqld360_sqlid.''
            AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id. 
            AND ''&&diagnostics_pack.'' = ''Y'' )
 GROUP BY name, position 
 HAVING COUNT(*) > 1
';
END;
/
@@sqld360_9a_pre_one.sql
