/* 
   Extracted from eAdam
*/

/* ------------------------------------------------------------------------- */
DEF section_id = '7c';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');

SET TERM OFF ECHO OFF ARRAY 1000;

DEF date_mask = 'YYYY-MM-DD/HH24:MI:SS';
DEF timestamp_mask = 'YYYY-MM-DD/HH24:MI:SS.FF6';
DEF fields_delimiter = '<,>';

ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ".,";
ALTER SESSION SET NLS_DATE_FORMAT = '&&date_mask.';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = '&&timestamp_mask.';

-- timestamp for record keeping control
COL eadam_current_time NEW_V eadam_current_time;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') eadam_current_time FROM DUAL;

/* ------------------------------------------------------------------------- */

SET TERM OFF ECHO OFF DEF ON FEED OFF FLU OFF HEA OFF NUM 30 LIN 32767 LONG 4000000 LONGC 4000 NEWP NONE PAGES 0 SHOW OFF SQLC MIX TAB OFF TRIMS ON VER OFF TIM OFF TIMI OFF ARRAY 1000 SQLP SQL> BLO . RECSEP OFF COLSEP '&&fields_delimiter.';

SPO dba_hist_xtr_control.txt;
SELECT d.dbid, d.name dbname, d.db_unique_name, d.platform_name,
       i.instance_number, i.instance_name, i.host_name, i.version,
       '&&eadam_current_time.' current_sysdate
  FROM v$database d,
       v$instance i;
SPO OFF;
HOS gzip dba_hist_xtr_control.txt
HOS tar -cf &&edb360_tar_filename..tar dba_hist_xtr_control.txt.gz
HOS rm dba_hist_xtr_control.txt.gz

/* ------------------------------------------------------------------------- */

SPO dba_tab_columns.txt;
SELECT table_name,
       column_id,
       column_name,
       data_type,
       data_length,
       data_precision,
       data_scale
  FROM dba_tab_columns
 WHERE (owner, table_name) IN 
(('SYS', 'DBA_HIST_ACTIVE_SESS_HISTORY')
)
ORDER BY CASE owner WHEN 'SYS' THEN 1 ELSE 2 END, table_name, column_id;
SPO OFF;
HOS gzip dba_tab_columns.txt
HOS tar -rf &&edb360_tar_filename..tar dba_tab_columns.txt.gz
HOS rm dba_tab_columns.txt.gz

/* ------------------------------------------------------------------------- */

SPO dba_hist_active_sess_history.txt;
SELECT * FROM dba_hist_active_sess_history 
WHERE dbid = &&edb360_dbid. 
AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
AND sql_id IN (SELECT operation FROM plan_table WHERE statement_id = 'SQLD360_SQLID');
SPO OFF;
HOS gzip dba_hist_active_sess_history.txt
HOS tar -rf &&edb360_tar_filename..tar dba_hist_active_sess_history.txt.gz
HOS rm dba_hist_active_sess_history.txt.gz

/* ------------------------------------------------------------------------- */

SET TERM ON COLSEP '';

HOS zip -m &&edb360_main_filename._&&edb360_file_time. &&edb360_tar_filename..tar >> &&edb360_log3..txt
