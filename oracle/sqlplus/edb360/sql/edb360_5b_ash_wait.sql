@@&&edb360_0g.tkprof.sql
DEF section_id = '5b';
DEF section_name = 'Active Session History (ASH) on Wait Class';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

-- from 5a
SET SERVEROUT ON;
SPO 99830_&&common_edb360_prefix._chart_setup_driver2.sql;
DECLARE
  l_count NUMBER;
BEGIN
  FOR i IN 1 .. 15
  LOOP
    SELECT COUNT(*) INTO l_count FROM gv$instance WHERE instance_number = i;
    IF l_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('COL inst_'||LPAD(i, 2, '0')||' NOPRI;');
      DBMS_OUTPUT.PUT_LINE('DEF tit_'||LPAD(i, 2, '0')||' = '''';');
    ELSE
      DBMS_OUTPUT.PUT_LINE('COL inst_'||LPAD(i, 2, '0')||' HEA ''Inst '||i||''' FOR 999990.0 PRI;');
      DBMS_OUTPUT.PUT_LINE('DEF tit_'||LPAD(i, 2, '0')||' = ''Inst '||i||''';');
    END IF;
  END LOOP;
END;
/
SPO OFF;
SET SERVEROUT OFF;
@99830_&&common_edb360_prefix._chart_setup_driver2.sql;
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 99830_&&common_edb360_prefix._chart_setup_driver2.sql >> &&edb360_log3..txt

DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
DEF chartype = 'AreaChart';
DEF stacked = 'isStacked: true,';
DEF vaxis = 'Average Active Sessions - AAS (stacked)';
DEF vbaseline = '';

BEGIN
  :sql_text_backup := '
SELECT /*+ &&ds_hint. */
       MIN(snap_id) snap_id,
       TO_CHAR(TRUNC(sample_time, ''HH''), ''YYYY-MM-DD HH24:MI'')          begin_time,
       TO_CHAR(TRUNC(sample_time, ''HH'') + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(SUM(CASE instance_number WHEN 1 THEN 10 ELSE 0 END) / 3600, 3) inst_01,
       ROUND(SUM(CASE instance_number WHEN 2 THEN 10 ELSE 0 END) / 3600, 3) inst_02,
       ROUND(SUM(CASE instance_number WHEN 3 THEN 10 ELSE 0 END) / 3600, 3) inst_03,
       ROUND(SUM(CASE instance_number WHEN 4 THEN 10 ELSE 0 END) / 3600, 3) inst_04,
       ROUND(SUM(CASE instance_number WHEN 5 THEN 10 ELSE 0 END) / 3600, 3) inst_05,
       ROUND(SUM(CASE instance_number WHEN 6 THEN 10 ELSE 0 END) / 3600, 3) inst_06,
       ROUND(SUM(CASE instance_number WHEN 7 THEN 10 ELSE 0 END) / 3600, 3) inst_07,
       ROUND(SUM(CASE instance_number WHEN 8 THEN 10 ELSE 0 END) / 3600, 3) inst_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM dba_hist_active_sess_history
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND @filter_predicate@
 GROUP BY
       TRUNC(sample_time, ''HH'')
 ORDER BY
       TRUNC(sample_time, ''HH'')
';
END;
/
-- end from 5a

DEF skip_lch = '';
DEF title = 'AAS Waiting on User IO per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''User I/O''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on System IO per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''System I/O''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Cluster per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Cluster''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Commit per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Commit''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Concurrency per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Concurrency''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Application per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Application''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_application');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Administrative per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Administrative''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Configuration per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Configuration''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Network per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Network''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Queueing per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Queueing''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Scheduler per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Scheduler''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Idle per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Idle''');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Other per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Other''');
@@edb360_9a_pre_one.sql