DEF section_name = 'Testcase';
DEF title = 'TCB Testcase';
DEF main_table = 'DBMS_SQLDIAG';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF

@@sqld360_5t_finddir.sql

@@sqld360_0s_pre_nondef

VAR sql_text CLOB
VAR tc CLOB
VAR tc_user VARCHAR2(30)

BEGIN

  SELECT parsing_schema_name
    INTO :tc_user
    FROM gv$sql
   WHERE sql_id = '&&sqld360_sqlid.'
     AND rownum = 1
     AND sql_fulltext IS NOT NULL;

EXCEPTION WHEN NO_DATA_FOUND THEN

  -- pick up one user that executed the SQL
  -- might give strange results for SQLs that run in
  -- different schemas where underlying objects are different
  SELECT parsing_schema_name
    INTO :tc_user
    FROM dba_hist_sqlstat
   WHERE sql_id =  '&&sqld360_sqlid.'
     AND ROWNUM = 1;

END;
/

SET TIMI ON;
SET SERVEROUT ON;
BEGIN
  DBMS_SQLDIAG.EXPORT_SQL_TESTCASE(
      directory     => :tcb_dir,
      sql_text      => :sqld360_fullsql,
      user_name     => :tc_user,
      testcase_name => 'sqld360_&&sqld360_sqlid.',
      testcase      => :tc
  );
END;
/

SET TIMI OFF;
SET SERVEROUT OFF;
SET TERM OFF;
SET PAGES 50000

HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title.
PRO <a href="&&one_spool_filename._tcb.zip">zip</a>
PRO </li>
SPO OFF;
HOS zip -jmq &&one_spool_filename._tcb &&tcb_path./sqld360_&&sqld360_sqlid.*
HOS zip -mq &&sqld360_main_filename._&&sqld360_file_time. &&one_spool_filename._tcb.zip
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html

--HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log2..txt
