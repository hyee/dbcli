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
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. 99830_&&common_edb360_prefix._chart_setup_driver2.sql

DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
DEF chartype = 'AreaChart';
DEF stacked = 'isStacked: true,';
DEF vaxis = 'Average Active Sessions - AAS (stacked)';
DEF vbaseline = '';
BEGIN
  :sql_text_backup := '
WITH
ash_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       snap_id,
       dbid,
       instance_number,
       COUNT(*) total,
       SUM(CASE session_state WHEN ''ON CPU''         THEN 1 ELSE 0 END) on_cpu,
       SUM(CASE wait_class    WHEN ''Administrative'' THEN 1 ELSE 0 END) w_administrative,
       SUM(CASE wait_class    WHEN ''Application''    THEN 1 ELSE 0 END) w_application,
       SUM(CASE wait_class    WHEN ''Cluster''        THEN 1 ELSE 0 END) w_cluster,
       SUM(CASE wait_class    WHEN ''Commit''         THEN 1 ELSE 0 END) w_commit,
       SUM(CASE wait_class    WHEN ''Concurrency''    THEN 1 ELSE 0 END) w_concurrency,
       SUM(CASE wait_class    WHEN ''Configuration''  THEN 1 ELSE 0 END) w_configuration,
       SUM(CASE wait_class    WHEN ''Idle''           THEN 1 ELSE 0 END) w_idle,
       SUM(CASE wait_class    WHEN ''Network''        THEN 1 ELSE 0 END) w_network,
       SUM(CASE wait_class    WHEN ''Other''          THEN 1 ELSE 0 END) w_other,
       SUM(CASE wait_class    WHEN ''Queueing''       THEN 1 ELSE 0 END) w_queueing,
       SUM(CASE wait_class    WHEN ''Scheduler''      THEN 1 ELSE 0 END) w_scheduler,
       SUM(CASE wait_class    WHEN ''System I/O''     THEN 1 ELSE 0 END) w_system_io,
       SUM(CASE wait_class    WHEN ''User I/O''       THEN 1 ELSE 0 END) w_user_io       
  FROM dba_hist_active_sess_history
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND @filter_predicate@
 GROUP BY
       snap_id,
       dbid,
       instance_number
),
ash_denorm_3 AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       a.snap_id,
       a.dbid,
       a.instance_number,
       s.begin_interval_time,
       s.end_interval_time,
       ROUND((CAST(s.end_interval_time AS DATE) - CAST(s.begin_interval_time AS DATE)) * 24 * 60 * 60) interval_secs,
       (10 * total)            total,
       (10 * on_cpu)           on_cpu,
       (10 * w_administrative) w_administrative,
       (10 * w_application)    w_application,
       (10 * w_cluster)        w_cluster,
       (10 * w_commit)         w_commit,
       (10 * w_concurrency)    w_concurrency,
       (10 * w_configuration)  w_configuration,
       (10 * w_idle)           w_idle,
       (10 * w_network)        w_network,
       (10 * w_other)          w_other,
       (10 * w_queueing)       w_queueing,
       (10 * w_scheduler)      w_scheduler,
       (10 * w_system_io)      w_system_io,
       (10 * w_user_io)        w_user_io
  FROM ash_denorm_2 a,
       dba_hist_snapshot s
 WHERE s.snap_id = a.snap_id
   AND s.dbid = a.dbid
   AND s.instance_number = a.instance_number
   AND s.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s.dbid = &&edb360_dbid.
   AND s.end_interval_time > (s.begin_interval_time + (1 / (24 * 60))) /* filter out snaps apart < 1 min */
),
ash_aas AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       instance_number,
       TO_CHAR(begin_interval_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(end_interval_time, ''YYYY-MM-DD HH24:MI'')   end_time,
       (total / interval_secs)            aas_total,
       (on_cpu / interval_secs)           aas_on_cpu,
       (w_administrative / interval_secs) aas_administrative,
       (w_application / interval_secs)    aas_application,
       (w_cluster / interval_secs)        aas_cluster,
       (w_commit / interval_secs)         aas_commit,
       (w_concurrency / interval_secs)    aas_concurrency,
       (w_configuration / interval_secs)  aas_configuration,
       (w_idle / interval_secs)           aas_idle,
       (w_network / interval_secs)        aas_network,
       (w_other / interval_secs)          aas_other,
       (w_queueing / interval_secs)       aas_queueing,
       (w_scheduler / interval_secs)      aas_scheduler,
       (w_system_io / interval_secs)      aas_system_io,
       (w_user_io / interval_secs)        aas_user_io
  FROM ash_denorm_3
),
aas_denorm_4 AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       begin_time,
       end_time,
       CASE instance_number WHEN 1 THEN @column_name@ ELSE 0 END inst_01,
       CASE instance_number WHEN 2 THEN @column_name@ ELSE 0 END inst_02,
       CASE instance_number WHEN 3 THEN @column_name@ ELSE 0 END inst_03,
       CASE instance_number WHEN 4 THEN @column_name@ ELSE 0 END inst_04,
       CASE instance_number WHEN 5 THEN @column_name@ ELSE 0 END inst_05,
       CASE instance_number WHEN 6 THEN @column_name@ ELSE 0 END inst_06,
       CASE instance_number WHEN 7 THEN @column_name@ ELSE 0 END inst_07,
       CASE instance_number WHEN 8 THEN @column_name@ ELSE 0 END inst_08
  FROM ash_aas
)
SELECT snap_id,
       MIN(begin_time) begin_time,
       MIN(end_time) end_time,
       ROUND(SUM(inst_01), 3) inst_01,
       ROUND(SUM(inst_02), 3) inst_02,
       ROUND(SUM(inst_03), 3) inst_03,
       ROUND(SUM(inst_04), 3) inst_04,
       ROUND(SUM(inst_05), 3) inst_05,
       ROUND(SUM(inst_06), 3) inst_06,
       ROUND(SUM(inst_07), 3) inst_07,
       ROUND(SUM(inst_08), 3) inst_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM aas_denorm_4
 GROUP BY
       snap_id
 ORDER BY
       snap_id
';
END;
/
-- end from 5a

DEF skip_lch = '';
DEF title = 'AAS Waiting on User IO per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''User I/O''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_user_io');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on System IO per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''System I/O''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_system_io');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Cluster per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Cluster''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_cluster');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Commit per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Commit''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_commit');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Concurrency per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Concurrency''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_concurrency');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Application per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Application''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_application');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Administrative per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Administrative''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_administrative');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Configuration per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Configuration''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_configuration');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Network per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Network''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_network');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Queueing per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Queueing''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_queueing');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Scheduler per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Scheduler''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_scheduler');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Idle per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Idle''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_idle');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'AAS Waiting on Other per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = ''Other''');
EXEC :sql_text := REPLACE(:sql_text, '@column_name@', 'aas_other');
@@&&skip_diagnostics.edb360_9a_pre_one.sql