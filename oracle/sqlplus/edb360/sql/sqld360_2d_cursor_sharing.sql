DEF section_name = 'Cursor Sharing';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;


DEF title = 'Non-sharing reasons';
DEF main_table = 'GV$SQL_SHARED_CURSOR';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       * 
  FROM gv$sql_shared_cursor 
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, child_number
';
END;
/
@@sqld360_9a_pre_one.sql

