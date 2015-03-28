DEF section_name = 'Identification';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'SQL Text';
DEF main_table = 'V$SQLTEXT_WITH_NEWLINES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM v$sqltext_with_newlines
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY piece
';
END;
/
@@sqld360_9a_pre_one.sql


DEF title = 'SQL Text from AWR';
DEF main_table = 'DBA_HIST_SQLTEXT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */ 
       *
  FROM dba_hist_sqltext
 WHERE sql_id = ''&&sqld360_sqlid.''
';
END;
/
@@sqld360_9a_pre_one.sql
