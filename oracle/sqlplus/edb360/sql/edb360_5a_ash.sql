@@&&edb360_0g.tkprof.sql
DEF section_id = '5a';
DEF section_name = 'Active Session History (ASH)';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
DEF chartype = 'AreaChart';
DEF stacked = 'isStacked: true,';
DEF vaxis = 'Average Active Sessions - AAS (stacked)';
DEF vbaseline = '';

DEF tit_01 = '';
DEF tit_02 = 'On CPU';
DEF tit_03 = 'User I/O';
DEF tit_04 = 'System I/O';
DEF tit_05 = 'Cluster';
DEF tit_06 = 'Commit';
DEF tit_07 = 'Concurrency';
DEF tit_08 = 'Application';
DEF tit_09 = 'Administrative';
DEF tit_10 = 'Configuration';
DEF tit_11 = 'Network';
DEF tit_12 = 'Queueing';
DEF tit_13 = 'Scheduler';
DEF tit_14 = 'Idle';
DEF tit_15 = 'Other';

COL aas_total FOR 999990.000;
COL aas_on_cpu FOR 999990.000;
COL aas_administrative FOR 999990.000;
COL aas_application FOR 999990.000;
COL aas_cluster FOR 999990.000;
COL aas_commit FOR 999990.000;
COL aas_concurrency FOR 999990.000;
COL aas_configuration FOR 999990.000;
COL aas_idle FOR 999990.000;
COL aas_network FOR 999990.000;
COL aas_other FOR 999990.000;
COL aas_queueing FOR 999990.000;
COL aas_scheduler FOR 999990.000;
COL aas_system_io FOR 999990.000;
COL aas_user_io FOR 999990.000;

BEGIN
  :sql_text_backup := '
SELECT /*+ &&ds_hint. */
       MIN(snap_id) snap_id,
       TO_CHAR(TRUNC(sample_time, ''HH''), ''YYYY-MM-DD HH24:MI'')          begin_time,
       TO_CHAR(TRUNC(sample_time, ''HH'') + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(10 * COUNT(*) / 3600, 3)                                                      aas_total,
       ROUND(SUM(CASE session_state WHEN ''ON CPU''         THEN 10 ELSE 0 END) / 3600, 3) aas_on_cpu,
       ROUND(SUM(CASE wait_class    WHEN ''User I/O''       THEN 10 ELSE 0 END) / 3600, 3) aas_user_io,
       ROUND(SUM(CASE wait_class    WHEN ''System I/O''     THEN 10 ELSE 0 END) / 3600, 3) aas_system_io,
       ROUND(SUM(CASE wait_class    WHEN ''Cluster''        THEN 10 ELSE 0 END) / 3600, 3) aas_cluster,
       ROUND(SUM(CASE wait_class    WHEN ''Commit''         THEN 10 ELSE 0 END) / 3600, 3) aas_commit,
       ROUND(SUM(CASE wait_class    WHEN ''Concurrency''    THEN 10 ELSE 0 END) / 3600, 3) aas_concurrency,
       ROUND(SUM(CASE wait_class    WHEN ''Application''    THEN 10 ELSE 0 END) / 3600, 3) aas_application,
       ROUND(SUM(CASE wait_class    WHEN ''Administrative'' THEN 10 ELSE 0 END) / 3600, 3) aas_administrative,
       ROUND(SUM(CASE wait_class    WHEN ''Configuration''  THEN 10 ELSE 0 END) / 3600, 3) aas_configuration,
       ROUND(SUM(CASE wait_class    WHEN ''Network''        THEN 10 ELSE 0 END) / 3600, 3) aas_network,
       ROUND(SUM(CASE wait_class    WHEN ''Queueing''       THEN 10 ELSE 0 END) / 3600, 3) aas_queueing,
       ROUND(SUM(CASE wait_class    WHEN ''Scheduler''      THEN 10 ELSE 0 END) / 3600, 3) aas_scheduler,
       ROUND(SUM(CASE wait_class    WHEN ''Idle''           THEN 10 ELSE 0 END) / 3600, 3) aas_idle,
       ROUND(SUM(CASE wait_class    WHEN  ''Other''         THEN 10 ELSE 0 END) / 3600, 3) aas_other
  FROM dba_hist_active_sess_history
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND instance_number = @instance_number@
 GROUP BY
       TRUNC(sample_time, ''HH'')
 ORDER BY
       TRUNC(sample_time, ''HH'')
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'AAS per Wait Class for Cluster';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'instance_number');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'AAS per Wait Class for Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'AAS per Wait Class for Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'AAS per Wait Class for Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'AAS per Wait Class for Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'AAS per Wait Class for Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'AAS per Wait Class for Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'AAS per Wait Class for Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'AAS per Wait Class for Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.edb360_9a_pre_one.sql

SET SERVEROUT ON;
SPO 99820_&&common_edb360_prefix._chart_setup_driver2.sql;
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
@99820_&&common_edb360_prefix._chart_setup_driver2.sql;
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 99820_&&common_edb360_prefix._chart_setup_driver2.sql >> &&edb360_log3..txt

DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
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

DEF skip_lch = '';
DEF title = 'AAS Total per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', '1 = 1');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS On CPU per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'session_state = ''ON CPU''');
@@edb360_9a_pre_one.sql

