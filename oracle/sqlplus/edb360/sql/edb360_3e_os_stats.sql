@@&&edb360_0g.tkprof.sql
DEF section_id = '3e';
DEF section_name = 'Operating System (OS) Statistics History';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Operating System (OS) Statistics';
DEF main_table = 'GV$OSSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$osstat
';
END;
/
@@edb360_9a_pre_one.sql

DEF main_table = 'DBA_HIST_OSSTAT';
DEF chartype = 'LineChart';
DEF stacked = '';
DEF vaxis = 'OS Avg Load, Num of CPUs and Num of CPU Cores';
DEF vbaseline = '';
DEF tit_01 = 'Average Load';
DEF tit_02 = 'Number of CPUs';
DEF tit_03 = 'Number of CPU Cores';
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
COL load FOR 999990.00;
BEGIN
  :sql_text_backup := '
WITH 
osstat_denorm AS (
SELECT /*+ &&sq_fact_hints. */
       s.snap_id,
       s.instance_number,
       SUM(CASE s.stat_name WHEN ''LOAD''          THEN value ELSE 0 END) load,
       SUM(CASE s.stat_name WHEN ''NUM_CPUS''      THEN value ELSE 0 END) num_cpus,
       SUM(CASE s.stat_name WHEN ''NUM_CPU_CORES'' THEN value ELSE 0 END) num_cpu_cores
  FROM dba_hist_osstat s
 WHERE s.stat_name IN (''LOAD'', ''NUM_CPUS'', ''NUM_CPU_CORES'')
   AND s.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s.dbid = &&edb360_dbid.
   AND s.instance_number = @instance_number@
 GROUP BY
       s.snap_id,
       s.instance_number
),
osstat_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       MIN(h.snap_id) snap_id,
       h.instance_number,
       TRUNC(CAST(s.end_interval_time AS DATE), ''HH'') begin_time,
       MAX(load) load,
       MAX(num_cpus) num_cpus,
       MAX(num_cpu_cores) num_cpu_cores
  FROM osstat_denorm h,
       dba_hist_snapshot s
 WHERE s.snap_id = h.snap_id
   AND s.instance_number = h.instance_number
   AND (CAST(s.end_interval_time AS DATE) - CAST(s.begin_interval_time AS DATE)) * 86400 > 60 -- ignore snaps too close
   AND s.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s.dbid = &&edb360_dbid.
   AND s.instance_number = @instance_number@
 GROUP BY
       h.instance_number,
       TRUNC(CAST(s.end_interval_time AS DATE), ''HH'')
)
SELECT MIN(snap_id) snap_id,
       TO_CHAR(begin_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(begin_time + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(SUM(load), 2) load,
       SUM(num_cpus) num_cpus,
       SUM(num_cpu_cores) num_cpu_cores,
       0 dummy_04,
       0 dummy_05,
       0 dummy_06,
       0 dummy_07,
       0 dummy_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM osstat_denorm_2
 GROUP BY
       begin_time
 ORDER BY
       begin_time
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'Load and CPUs for Cluster';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 's.instance_number');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'Load and CPUs for Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'Load and CPUs for Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'Load and CPUs for Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'Load and CPUs for Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'Load and CPUs for Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'Load and CPUs for Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'Load and CPUs for Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'Load and CPUs for Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF main_table = 'DBA_HIST_OSSTAT';
DEF chartype = 'LineChart';
DEF stacked = '';
DEF vaxis = 'Time as a Percent of Number of CPUs';
DEF vbaseline = 'baseline: 100,';
DEF tit_01 = '';
DEF tit_02 = '';
DEF tit_03 = 'Idle Time %';
DEF tit_04 = 'Busy Time %';
DEF tit_05 = 'User Time %';
DEF tit_06 = 'Nice Time %';
DEF tit_07 = 'Sys Time %';
DEF tit_08 = 'OS CPU Wait Time %';
DEF tit_09 = 'RM CPU Wait Time %';
DEF tit_10 = 'IO Time %';
DEF tit_11 = '';
DEF tit_12 = '';
DEF tit_13 = '';
DEF tit_14 = '';
DEF tit_15 = '';
COL load FOR 999990.0;
COL idle_time_perc FOR 999990.0;
COL busy_time_perc FOR 999990.0;
COL user_time_perc FOR 999990.0;
COL nice_time_perc FOR 999990.0;
COL sys_time_perc FOR 999990.0;
COL os_cpu_wait_time_secs FOR 999990.0;
COL rsrc_mgr_cpu_wait_perc FOR 999990.0;
COL iowait_perc FOR 999990.0;
BEGIN
  :sql_text_backup := '
WITH 
osstat_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       dbid,
       instance_number,
       SUM(CASE stat_name WHEN ''NUM_CPUS''               THEN value       ELSE 0 END) num_cpus,
       SUM(CASE stat_name WHEN ''LOAD''                   THEN value       ELSE 0 END) load,
       SUM(CASE stat_name WHEN ''IDLE_TIME''              THEN value / 100 ELSE 0 END) idle_time_secs,
       SUM(CASE stat_name WHEN ''BUSY_TIME''              THEN value / 100 ELSE 0 END) busy_time_secs,
       SUM(CASE stat_name WHEN ''USER_TIME''              THEN value / 100 ELSE 0 END) user_time_secs,
       SUM(CASE stat_name WHEN ''NICE_TIME''              THEN value / 100 ELSE 0 END) nice_time_secs,
       SUM(CASE stat_name WHEN ''SYS_TIME''               THEN value / 100 ELSE 0 END) sys_time_secs,
       SUM(CASE stat_name WHEN ''OS_CPU_WAIT_TIME''       THEN value / 100 ELSE 0 END) os_cpu_wait_time_secs,
       SUM(CASE stat_name WHEN ''RSRC_MGR_CPU_WAIT_TIME'' THEN value / 100 ELSE 0 END) rsrc_mgr_cpu_wait_time_secs,
       SUM(CASE stat_name WHEN ''IOWAIT_TIME''            THEN value / 100 ELSE 0 END) iowait_time_secs,
       SUM(CASE stat_name WHEN ''VM_IN_BYTES''            THEN value       ELSE 0 END) vm_in_bytes,
       SUM(CASE stat_name WHEN ''VM_OUT_BYTES''           THEN value       ELSE 0 END) vm_out_bytes
  FROM dba_hist_osstat
 WHERE stat_name IN (''NUM_CPUS'', ''LOAD'', ''IDLE_TIME'', ''BUSY_TIME'', ''USER_TIME'', ''NICE_TIME'', ''SYS_TIME'', ''OS_CPU_WAIT_TIME'', ''RSRC_MGR_CPU_WAIT_TIME'', ''IOWAIT_TIME'', ''VM_IN_BYTES'', ''VM_OUT_BYTES'')
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND instance_number = @instance_number@
 GROUP BY
       snap_id,
       dbid,
       instance_number
),
osstat_delta AS (
SELECT /*+ &&sq_fact_hints. */
       h1.snap_id,
       h1.dbid,
       h1.instance_number,
       s1.begin_interval_time,
       s1.end_interval_time,
       ROUND((CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 24 * 60 * 60) interval_secs,
       h1.num_cpus,
       h1.load,
       (h1.idle_time_secs - h0.idle_time_secs) idle_time_secs,
       (h1.busy_time_secs - h0.busy_time_secs) busy_time_secs,
       (h1.user_time_secs - h0.user_time_secs) user_time_secs,
       (h1.nice_time_secs - h0.nice_time_secs) nice_time_secs,
       (h1.sys_time_secs - h0.sys_time_secs) sys_time_secs,
       (h1.os_cpu_wait_time_secs - h0.os_cpu_wait_time_secs) os_cpu_wait_time_secs,
       (h1.rsrc_mgr_cpu_wait_time_secs - h0.rsrc_mgr_cpu_wait_time_secs) rsrc_mgr_cpu_wait_time_secs,
       (h1.iowait_time_secs - h0.iowait_time_secs) iowait_time_secs,
       (h1.vm_in_bytes - h0.vm_in_bytes) vm_in_bytes,
       (h1.vm_out_bytes - h0.vm_out_bytes) vm_out_bytes
  FROM osstat_denorm_2 h0,
       osstat_denorm_2 h1,
       dba_hist_snapshot s0,
       dba_hist_snapshot s1
 WHERE h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND s0.snap_id = h0.snap_id
   AND s0.dbid = h0.dbid
   AND s0.instance_number = h0.instance_number
   AND s0.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s0.dbid = &&edb360_dbid.
   AND s1.snap_id = h1.snap_id
   AND s1.dbid = h1.dbid
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.startup_time = s0.startup_time
   AND s1.begin_interval_time > (s0.begin_interval_time + (1 / (24 * 60))) /* filter out snaps apart < 1 min */
)
SELECT snap_id,
       TO_CHAR(MIN(begin_interval_time), ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(MIN(end_interval_time), ''YYYY-MM-DD HH24:MI'') end_time,
       SUM(num_cpus) num_cpus,
       ROUND(SUM(load), 1) load,
       ROUND(100 * SUM(idle_time_secs / num_cpus) / SUM(interval_secs), 1) idle_time_perc,
       ROUND(100 * SUM(busy_time_secs / num_cpus) / SUM(interval_secs), 1) busy_time_perc,
       ROUND(100 * SUM(user_time_secs / num_cpus) / SUM(interval_secs), 1) user_time_perc,
       ROUND(100 * SUM(nice_time_secs / num_cpus) / SUM(interval_secs), 1) nice_time_perc,
       ROUND(100 * SUM(sys_time_secs / num_cpus) / SUM(interval_secs), 1) sys_time_perc,
       ROUND(100 * SUM(os_cpu_wait_time_secs / num_cpus) / SUM(interval_secs), 1) os_cpu_wait_time_perc,
       ROUND(100 * SUM(rsrc_mgr_cpu_wait_time_secs / num_cpus) / SUM(interval_secs), 1) rsrc_mgr_cpu_wait_perc,
       ROUND(100 * SUM(iowait_time_secs / num_cpus) / SUM(interval_secs), 1) iowait_perc,
       ROUND(SUM(vm_in_bytes) / POWER(2, 30), 3) vm_in_gb,
       ROUND(SUM(vm_out_bytes) / POWER(2, 30), 3) vm_out_gb,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM osstat_delta
 GROUP BY
       snap_id
 ORDER BY
       snap_id
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'CPU Time Percent for Cluster';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'instance_number');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'CPU Time Percent for Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'CPU Time Percent for Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'CPU Time Percent for Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'CPU Time Percent for Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'CPU Time Percent for Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'CPU Time Percent for Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'CPU Time Percent for Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'CPU Time Percent for Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU Load for Cluster';
DEF tit_01 = 'Num CPUs';
DEF tit_02 = 'Load';
DEF tit_03 = '';
DEF tit_04 = '';
DEF tit_05 = '';
DEF tit_06 = '';
DEF tit_07 = '';
DEF tit_08 = '';
DEF tit_09 = '';
DEF tit_10 = '';
DEF vaxis = 'Load';
DEF vbaseline = 'baseline:&&sum_cpu_count.,';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'instance_number');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Virtual Memory (VM) Pages for Cluster';
DEF tit_01 = '';
DEF tit_02 = '';
DEF tit_11 = 'VM Pages IN (GBs)';
DEF tit_12 = 'VM Pages OUT (GBs)';
DEF vaxis = 'Virtual Memory Pages IN and OUT (GBs)';
DEF vbaseline = '';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'instance_number');
@@edb360_9a_pre_one.sql

SET SERVEROUT ON;
SPO 99810_&&common_edb360_prefix._chart_setup_driver1.sql;
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
@99810_&&common_edb360_prefix._chart_setup_driver1.sql;
HOS zip -m &&edb360_main_filename._&&edb360_file_time. 99810_&&common_edb360_prefix._chart_setup_driver1.sql >> &&edb360_log3..txt

DEF main_table = 'DBA_HIST_OSSTAT';
DEF vaxis = 'Time as a Percent of Number of CPUs';
--DEF vbaseline = 'baseline: 100,';
BEGIN
  :sql_text_backup := '
WITH 
osstat_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       dbid,
       instance_number,
       SUM(CASE stat_name WHEN ''NUM_CPUS''               THEN value       ELSE 0 END) num_cpus,
       SUM(CASE stat_name WHEN ''LOAD''                   THEN value       ELSE 0 END) load,
       SUM(CASE stat_name WHEN ''IDLE_TIME''              THEN value / 100 ELSE 0 END) idle_time_secs,
       SUM(CASE stat_name WHEN ''BUSY_TIME''              THEN value / 100 ELSE 0 END) busy_time_secs,
       SUM(CASE stat_name WHEN ''USER_TIME''              THEN value / 100 ELSE 0 END) user_time_secs,
       SUM(CASE stat_name WHEN ''NICE_TIME''              THEN value / 100 ELSE 0 END) nice_time_secs,
       SUM(CASE stat_name WHEN ''SYS_TIME''               THEN value / 100 ELSE 0 END) sys_time_secs,
       SUM(CASE stat_name WHEN ''OS_CPU_WAIT_TIME''       THEN value / 100 ELSE 0 END) os_cpu_wait_time_secs,
       SUM(CASE stat_name WHEN ''RSRC_MGR_CPU_WAIT_TIME'' THEN value / 100 ELSE 0 END) rsrc_mgr_cpu_wait_time_secs,
       SUM(CASE stat_name WHEN ''IOWAIT_TIME''            THEN value / 100 ELSE 0 END) iowait_time_secs,
       SUM(CASE stat_name WHEN ''VM_IN_BYTES''            THEN value       ELSE 0 END) vm_in_bytes,
       SUM(CASE stat_name WHEN ''VM_OUT_BYTES''           THEN value       ELSE 0 END) vm_out_bytes
  FROM dba_hist_osstat
 --WHERE stat_name IN (''NUM_CPUS'', ''LOAD'', ''IDLE_TIME'', ''BUSY_TIME'', ''USER_TIME'', ''NICE_TIME'', ''SYS_TIME'', ''OS_CPU_WAIT_TIME'', ''RSRC_MGR_CPU_WAIT_TIME'', ''IOWAIT_TIME'', ''VM_IN_BYTES'', ''VM_OUT_BYTES'')
 WHERE stat_name IN (''NUM_CPUS'', UPPER(''@stat_name@''))
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
 GROUP BY
       snap_id,
       dbid,
       instance_number
),
osstat_delta AS (
SELECT /*+ &&sq_fact_hints. */
       h1.snap_id,
       h1.dbid,
       h1.instance_number,
       s1.begin_interval_time,
       s1.end_interval_time,
       ROUND((CAST(s1.end_interval_time AS DATE) - CAST(s1.begin_interval_time AS DATE)) * 24 * 60 * 60) interval_secs,
       h1.num_cpus,
       h1.load,
       (h1.idle_time_secs - h0.idle_time_secs) idle_time_secs,
       (h1.busy_time_secs - h0.busy_time_secs) busy_time_secs,
       (h1.user_time_secs - h0.user_time_secs) user_time_secs,
       (h1.nice_time_secs - h0.nice_time_secs) nice_time_secs,
       (h1.sys_time_secs - h0.sys_time_secs) sys_time_secs,
       (h1.os_cpu_wait_time_secs - h0.os_cpu_wait_time_secs) os_cpu_wait_time_secs,
       (h1.rsrc_mgr_cpu_wait_time_secs - h0.rsrc_mgr_cpu_wait_time_secs) rsrc_mgr_cpu_wait_time_secs,
       (h1.iowait_time_secs - h0.iowait_time_secs) iowait_time_secs,
       (h1.vm_in_bytes - h0.vm_in_bytes) vm_in_bytes,
       (h1.vm_out_bytes - h0.vm_out_bytes) vm_out_bytes
  FROM osstat_denorm_2 h0,
       osstat_denorm_2 h1,
       dba_hist_snapshot s0,
       dba_hist_snapshot s1
 WHERE h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND s0.snap_id = h0.snap_id
   AND s0.dbid = h0.dbid
   AND s0.instance_number = h0.instance_number
   AND s0.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s0.dbid = &&edb360_dbid.
   AND s1.snap_id = h1.snap_id
   AND s1.dbid = h1.dbid
   AND s1.instance_number = h1.instance_number
   AND s1.snap_id = s0.snap_id + 1
   AND s1.startup_time = s0.startup_time
   AND s1.begin_interval_time > (s0.begin_interval_time + (1 / (24 * 60))) /* filter out snaps apart < 1 min */
),
osstat_inst AS (
SELECT /*+ &&sq_fact_hints. */
       instance_number,
       snap_id,
       TO_CHAR(begin_interval_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(end_interval_time, ''YYYY-MM-DD HH24:MI'') end_time,
       num_cpus,
       ROUND(load, 1) load,
       ROUND(100 * idle_time_secs / num_cpus / interval_secs, 1) idle_time_perc,
       ROUND(100 * busy_time_secs / num_cpus / interval_secs, 1) busy_time_perc,
       ROUND(100 * user_time_secs / num_cpus / interval_secs, 1) user_time_perc,
       ROUND(100 * nice_time_secs / num_cpus / interval_secs, 1) nice_time_perc,
       ROUND(100 * sys_time_secs / num_cpus / interval_secs, 1) sys_time_perc,
       ROUND(100 * os_cpu_wait_time_secs / num_cpus / interval_secs, 1) os_cpu_wait_time_perc,
       ROUND(100 * rsrc_mgr_cpu_wait_time_secs / num_cpus / interval_secs, 1) rsrc_mgr_cpu_wait_time_perc,
       ROUND(100 * iowait_time_secs / num_cpus / interval_secs, 1) iowait_time_perc,
       ROUND(vm_in_bytes / POWER(2, 30), 3) vm_in_bytes,
       ROUND(vm_out_bytes / POWER(2, 30), 3) vm_out_bytes
  FROM osstat_delta
),
osstat_denorm_3 AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       begin_time,
       end_time,
       CASE instance_number WHEN 1 THEN @stat_name@_perc ELSE 0 END inst_01,
       CASE instance_number WHEN 2 THEN @stat_name@_perc ELSE 0 END inst_02,
       CASE instance_number WHEN 3 THEN @stat_name@_perc ELSE 0 END inst_03,
       CASE instance_number WHEN 4 THEN @stat_name@_perc ELSE 0 END inst_04,
       CASE instance_number WHEN 5 THEN @stat_name@_perc ELSE 0 END inst_05,
       CASE instance_number WHEN 6 THEN @stat_name@_perc ELSE 0 END inst_06,
       CASE instance_number WHEN 7 THEN @stat_name@_perc ELSE 0 END inst_07,
       CASE instance_number WHEN 8 THEN @stat_name@_perc ELSE 0 END inst_08
  FROM osstat_inst
)
SELECT snap_id,
       MIN(begin_time) begin_time,
       MIN(end_time) end_time,
       SUM(inst_01) inst_01,
       SUM(inst_02) inst_02,
       SUM(inst_03) inst_03,
       SUM(inst_04) inst_04,
       SUM(inst_05) inst_05,
       SUM(inst_06) inst_06,
       SUM(inst_07) inst_07,
       SUM(inst_08) inst_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM osstat_denorm_3
 GROUP BY
       snap_id
 ORDER BY
       snap_id
';
END;
/

DEF skip_lch = '';
DEF title = 'CPU Idle Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'idle_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU Busy Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'busy_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU User Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'user_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU Nice Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'nice_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU Sys Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'sys_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'OS CPU Wait Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'os_cpu_wait_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Resource Manager (RM) CPU Wait Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'rsrc_mgr_cpu_wait_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU IO Wait Time Percent per Instance';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@', 'iowait_time');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CPU Load per Instance';
DEF vaxis = 'Load';
DEF vbaseline = 'baseline:&&avg_cpu_count.,';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@_perc', 'load');
EXEC :sql_text := REPLACE(:sql_text, '@stat_name@', 'load');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

COL inst_01 FOR 999999999999990;
COL inst_02 FOR 999999999999990;
COL inst_03 FOR 999999999999990;
COL inst_04 FOR 999999999999990;
COL inst_05 FOR 999999999999990;
COL inst_06 FOR 999999999999990;
COL inst_07 FOR 999999999999990;
COL inst_08 FOR 999999999999990;

DEF skip_lch = '';
DEF title = 'Virtual Memory (VM) Pages IN per Instance';
DEF vaxis = 'Virtual Memory Pages IN (GBs)';
DEF vbaseline = '';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@_perc', 'vm_in_bytes');
EXEC :sql_text := REPLACE(:sql_text, '@stat_name@', 'vm_in_bytes');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Virtual Memory (VM) Pages OUT per Instance';
DEF vaxis = 'Virtual Memory Pages OUT (GBs)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name@_perc', 'vm_out_bytes');
EXEC :sql_text := REPLACE(:sql_text, '@stat_name@', 'vm_out_bytes');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

/*****************************************************************************************/

DEF skip_lch = 'Y';
DEF skip_pch = 'Y';
