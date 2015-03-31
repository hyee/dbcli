-- setup
SET VER OFF; 
SET FEED OFF; 
SET ECHO OFF;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD/HH24:MI:SS') edb360_time_stamp FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'HH24:MI:SS') hh_mm_ss FROM DUAL;
SELECT REPLACE(TRANSLATE('&&title.',
'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ''`~!@#$%^*()-_=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz0123456789_'), '__', '_') title_no_spaces FROM DUAL;
SELECT '&&common_edb360_prefix._&&section_id._&&title_no_spaces.' spool_filename FROM DUAL;
SET HEA OFF;
SET TERM ON;

-- log
SPO &&edb360_log..txt APP;
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
HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_log..txt

-- spools query
SPO &&common_edb360_prefix._query.sql;
SELECT 'SELECT ROWNUM row_num, v0.* FROM ('||CHR(10)||TRIM(CHR(10) FROM :sql_text)||CHR(10)||') v0 WHERE ROWNUM <= &&max_rows.' FROM DUAL;
SPO OFF;
SET HEA ON;
GET &&common_edb360_prefix._query.sql

-- update main report
SPO &&edb360_main_report..html APP;
PRO <li title="&&main_table.">&&title. <small><em>(&&row_count.)</em></small>
SPO OFF;
HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html

-- execute one sql
@@&&skip_html.&&edb360_skip_html.edb360_9b_one_html.sql
@@&&skip_text.&&edb360_skip_text.edb360_9c_one_text.sql
@@&&skip_csv.&&edb360_skip_csv.edb360_9d_one_csv.sql
@@&&skip_lch.&&edb360_skip_line.edb360_9e_one_line_chart.sql
@@&&skip_pch.&&edb360_skip_pie.edb360_9f_one_pie_chart.sql
HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_log2..txt

-- sql monitor long executions of sql from edb360
SELECT 'N' edb360_tuning_pack_for_sqlmon, '--' skip_sqlmon_exec FROM DUAL
/
SELECT '&&tuning_pack.' edb360_tuning_pack_for_sqlmon, NULL skip_sqlmon_exec, SUBSTR(sql_text, 1, 100) edb360_sql_text_100, elapsed_time FROM v$sql 
WHERE sql_id = '&&edb360_prev_sql_id.' AND elapsed_time / 1e6 > 60 /* seconds */
/
@@&&skip_tuning.&&skip_sqlmon_exec.sqlmon.sql &&edb360_tuning_pack_for_sqlmon. &&edb360_prev_sql_id.
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. sqlmon_&&edb360_prev_sql_id._&&current_time..zip

-- needed reset after eventual sqlmon above
SET TERM OFF; 
SET HEA ON; 
SET LIN 32767; 
SET NEWP NONE; 
SET PAGES &&def_max_rows.; 
SET LONG 32000; 
SET LONGC 2000; 
SET WRA ON; 
SET TRIMS ON; 
SET TRIM ON; 
SET TI OFF; 
SET TIMI OFF; 
SET ARRAY 100; 
SET NUM 20; 
SET SQLBL ON; 
SET BLO .; 
SET RECSEP OFF;

-- cleanup
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
DEF title_suffix = '';
DEF haxis = '&&db_version. dbname:&&database_name_short. host:&&host_name_short. (avg cpu_count: &&avg_cpu_count.)';
DEF tit_01 = '';
DEF tit_02 = '';
DEF tit_03 = '';
DEF tit_04 = '';
DEF tit_05 = '';
DEF tit_06 = '';
DEF tit_07 = '';
DEF tit_08 = '';
DEF tit_09 = '';
DEF tit_10 = '';
DEF tit_11 = '';
DEF tit_12 = '';
DEF tit_13 = '';
DEF tit_14 = '';
DEF tit_15 = '';

-- update main report
SPO &&edb360_main_report..html APP;
PRO </li>
SPO OFF;
HOS zip -q &&edb360_main_filename._&&edb360_file_time. &&edb360_main_report..html
