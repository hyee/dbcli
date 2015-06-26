DEF section_name = 'In-Memory';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;


DEF title = 'In-Memory Area';
DEF main_table = 'GV$INMEMORY_AREA';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$inmemory_area
 ORDER BY inst_id, pool 
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'In-Memory Segments';
DEF main_table = 'GV$IM_SEGMENTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$im_segments
 WHERE (owner, segment_name) in &&tables_list.
 ORDER BY inst_id, owner, segment_name, partition_name, segment_type
';
END;
/
@@sqld360_9a_pre_one.sql

DEF title = 'In-Memory Column Level';
DEF main_table = 'GV$IM_COLUMN_LEVEL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$im_column_level
 WHERE (owner, table_name) in &&tables_list.
 ORDER BY inst_id, owner, table_name, segment_column_id 
';
END;
/
@@sqld360_9a_pre_one.sql
