-- setup
SET VER OFF; 
SET FEED OFF; 
SET ECHO OFF;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') sqld360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SELECT REPLACE(TRANSLATE('&&title.',
'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ''`~!@#$%^*()-_=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz0123456789_'), '__', '_') title_no_spaces FROM DUAL;
SELECT '&&common_sqld360_prefix._&&column_number._&&title_no_spaces.' spool_filename FROM DUAL;
SET HEA OFF;
SET TERM ON;

-- log
SPO &&sqld360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
PRO &&hh_mm_ss. col:&&column_number.of&&max_col_number. "&&section_name."
PRO &&hh_mm_ss. &&title.&&title_suffix.

-- count
PRINT sql_text;
PRO &&hh_mm_ss. col:&&column_number.of&&max_col_number.. Computing COUNT(*)...
EXEC :row_count := -1;
EXEC :sql_text_display := TRIM(CHR(10) FROM :sql_text)||';';
SET TIMI ON;
SET SERVEROUT ON;
BEGIN
  --:sql_text_display := TRIM(CHR(10) FROM :sql_text)||';';
  BEGIN
    --EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ('||CHR(10)||TRIM(CHR(10) FROM :sql_text)||CHR(10)||')' INTO :row_count;
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ('||CHR(10)||TRIM(CHR(10) FROM DBMS_LOB.SUBSTR(:sql_text, 32700, 1))||CHR(10)||')' INTO :row_count;
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(SQLERRM));
  END;
  DBMS_OUTPUT.PUT_LINE(TRIM(TO_CHAR(:row_count))||' rows selected.'||CHR(10));
END;
/
SET TIMI OFF;
SET SERVEROUT OFF;
PRO
SET TERM OFF;
COL row_count NEW_V row_count NOPRI;
SELECT TRIM(TO_CHAR(:row_count)) row_count FROM DUAL;
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log..txt

-- spools query
SPO &&common_sqld360_prefix._query.sql;
SELECT 'SELECT ROWNUM row_num, v0.* FROM ('||CHR(10)||TRIM(CHR(10) FROM :sql_text)||CHR(10)||') v0 WHERE ROWNUM <= &&max_rows.' FROM DUAL;
SPO OFF;
SET HEA ON;
GET &&common_sqld360_prefix._query.sql

-- update main report
SPO &&sqld360_main_report..html APP;
PRO <li title="&&main_table.">&&title. <small><em>(&&row_count.)</em></small>
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html

-- execute one sql
@@&&skip_html.&&sqld360_skip_html.sqld360_9b_one_html.sql
@@&&skip_text.&&sqld360_skip_text.sqld360_9c_one_text.sql
@@&&skip_csv.&&sqld360_skip_csv.sqld360_9d_one_csv.sql
@@&&skip_lch.&&sqld360_skip_line.sqld360_9e_one_line_chart.sql
@@&&skip_pch.&&sqld360_skip_pie.sqld360_9f_one_pie_chart.sql
@@&&skip_bch.&&sqld360_skip_bar.sqld360_9g_one_bar_chart.sql
@@&&skip_tch.&&sqld360_skip_tree.sqld360_9h_one_org_chart.sql
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_log2..txt
EXEC :sql_text := NULL;
COL row_num FOR 9999999 HEA '#' PRI;
DEF abstract = '';
DEF abstract2 = '';
DEF foot = '';
DEF max_rows = '&&def_max_rows.';
DEF skip_html = '';
DEF skip_text = '';
DEF skip_csv = '';
DEF skip_lch = 'Y';
DEF skip_pch = 'Y';
DEF skip_bch = 'Y';
DEF skip_tch = 'Y';
DEF title_suffix = '';
DEF haxis = '&&db_version. dbname:&&database_name_short. host:&&host_name_short. (avg cpu_count: &&avg_cpu_count.)';

-- update main report
SPO &&sqld360_main_report..html APP;
PRO </li>
SPO OFF;
HOS zip -q &&sqld360_main_filename._&&sqld360_file_time. &&sqld360_main_report..html
