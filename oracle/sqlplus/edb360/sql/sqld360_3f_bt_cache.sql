DEF section_name = 'Big Table Caching';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;


DEF title = 'BT Scan Cache';
DEF main_table = 'GV$BT_SCAN_CACHE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$bt_scan_cache
 ORDER BY inst_id 
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'BT Scan Objects Temps';
DEF main_table = 'GV$BT_SCAN_OBJ_TEMPS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       o.owner, o.object_name, o.subobject_name,
       bsc.*
  FROM gv$bt_scan_obj_temps bsc,
       dba_objects o
 WHERE bsc.dataobj# = o.data_object_id 
   AND (o.owner, o.object_name) in &&tables_list.
 ORDER BY bsc.inst_id, o.owner, o.object_name, o.subobject_name
';
END;
/
@@sqld360_9a_pre_one.sql
