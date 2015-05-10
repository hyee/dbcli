@@&&edb360_0g.tkprof.sql
DEF section_id = '3d';
DEF section_name = 'Performance Summaries';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'AAS for past minute';
DEF main_table = 'GV$WAITCLASSMETRIC';
COL aas FOR 999990.000;
BEGIN
  :sql_text := '
-- inspired by Kyle Hailey blogs
-- http://www.kylehailey.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
-- http://www.kylehailey.com/oracle-cpu-time/
WITH 
ora_cpu_used AS (
SELECT /*+ &&sq_fact_hints. */
       ''2'' row_type,
       ''Oracle CPU used'' timed_event,
       sm.inst_id,
       sm.begin_time,
       sm.end_time,
       ROUND(sm.value / 100, 3) aas --(/ 100 is to convert from cs to sec)
  FROM gv$sysmetric sm
 WHERE sm.metric_name=''CPU Usage Per Sec''
   AND sm.group_id = 2 -- 1 minute
),
system_cpu_used AS (
SELECT /*+ &&sq_fact_hints. */
       ''4'' row_type,
       ''System CPU used'' timed_event,
       sm.inst_id,
       sm.begin_time,
       sm.end_time,
       ROUND((sm.value / 100) * TO_NUMBER(p.value), 3) aas -- (/ 100 is to convert % to fraction)
  FROM gv$sysmetric sm,
       gv$system_parameter2 p
 WHERE sm.metric_name=''Host CPU Utilization (%)''
   AND sm.group_id = 2 -- 1 minute
   AND sm.inst_id = p.inst_id
   AND p.name = ''cpu_count''
),
non_idle_waits AS (
SELECT /*+ &&sq_fact_hints. */
       ''6'' row_type,
       wc.wait_class timed_event,
       wcm.inst_id,
       wcm.begin_time,
       wcm.end_time,
       ROUND(wcm.time_waited/wcm.intsize_csec, 3) aas
  FROM gv$waitclassmetric wcm,
       gv$system_wait_class wc
 WHERE wcm.inst_id = wc.inst_id
   AND wcm.wait_class_id = wc.wait_class_id
   AND wcm.wait_class# = wc.wait_class#
   AND wcm.time_waited > 0
   AND wcm.wait_count > 0
   AND wc.wait_class != ''Idle''
   AND ROUND(wcm.time_waited/wcm.intsize_csec, 3) >= 0.001
),
time_window AS ( -- one row with oldest and newest date sample
SELECT MIN(begin_time) begin_time, MAX(end_time) end_time FROM (
SELECT MIN(begin_time) begin_time, MAX(end_time) end_time FROM ora_cpu_used
 UNION ALL
SELECT MIN(begin_time) begin_time, MAX(end_time) end_time FROM system_cpu_used
 UNION ALL
SELECT MIN(begin_time) begin_time, MAX(end_time) end_time FROM non_idle_waits
)),
ora_dem_cpu AS (
SELECT /*+ &&sq_fact_hints. */
       ''1'' row_type,
       ''Oracle demand for CPU'' timed_event,
       ash.inst_id,
       tw.begin_time,
       tw.end_time,
       ROUND(COUNT(*) / ((tw.end_time - tw.begin_time) * 24 * 60 * 60), 3) aas -- samples over time in secs
  FROM gv$active_session_history ash,
       time_window tw
 WHERE ash.session_state = ''ON CPU''
   AND CAST(sample_time AS DATE) BETWEEN tw.begin_time AND tw.end_time
   AND ''&&diagnostics_pack.'' = ''Y''
 GROUP BY
       ash.inst_id,
       tw.begin_time,
       tw.end_time
),
ora_wait_cpu AS (
SELECT ''3'' row_type,
       ''Oracle wait for CPU (demand - used)'' timed_event,
       d.inst_id,
       LEAST(d.begin_time, u.begin_time) begin_time,
       GREATEST(d.end_time, u.end_time) end_time,
       CASE WHEN d.aas > u.aas THEN d.aas - u.aas ELSE 0 END aas
  FROM ora_dem_cpu d,
       ora_cpu_used u
 WHERE d.inst_id = u.inst_id
),
system_cpu_used_no_ora AS (
SELECT ''5'' row_type,
       ''System CPU used (excludes Oracle)'' timed_event,
       s.inst_id,
       LEAST(s.begin_time, u.begin_time) begin_time,
       GREATEST(s.end_time, u.end_time) end_time,
       CASE WHEN s.aas > u.aas THEN s.aas - u.aas ELSE 0 END aas
  FROM system_cpu_used s,
       ora_cpu_used u
 WHERE s.inst_id = u.inst_id
),
all_pieces AS (
SELECT * FROM ora_dem_cpu
 UNION ALL
SELECT * FROM ora_cpu_used
 UNION ALL
SELECT * FROM ora_wait_cpu
 UNION ALL
SELECT * FROM system_cpu_used
 UNION ALL
SELECT * FROM system_cpu_used_no_ora
 UNION ALL
SELECT * FROM non_idle_waits
)
SELECT /*+ &&top_level_hints. */
       inst_id,
       timed_event,
       aas
  FROM all_pieces
 ORDER BY
       inst_id,
       row_type,
       aas DESC,
       timed_event
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql       

DEF title = 'Wait Class Metric for past minute';
DEF main_table = 'GV$WAITCLASSMETRIC';
BEGIN
  :sql_text := '
-- inspired by Kyle Hailey blogs
-- http://www.kylehailey.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
-- http://www.kylehailey.com/oracle-cpu-time/
SELECT /*+ &&top_level_hints. */
       wc.wait_class,
       wcm.*,
       ROUND(wcm.time_waited/wcm.intsize_csec, 3) aas,
       CASE WHEN wc.wait_class = ''User I/O'' THEN 
       ROUND(10 * wcm.time_waited  / wcm.wait_count, 3) END avg_io_ms
  FROM gv$waitclassmetric wcm,
       gv$system_wait_class wc
 WHERE wcm.inst_id = wc.inst_id
   AND wcm.wait_class_id = wc.wait_class_id
   AND wcm.wait_class# = wc.wait_class#
   AND wcm.time_waited > 0
   AND wcm.wait_count > 0
   AND wc.wait_class != ''Idle''
   AND ROUND(wcm.time_waited/wcm.intsize_csec, 3) >= 0.001
 ORDER BY
       wcm.inst_id,
       wc.wait_class
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Event Metric for past minute';
DEF main_table = 'GV$EVENTMETRIC';
BEGIN
  :sql_text := '
-- inspired by Kyle Hailey blogs
-- http://www.kylehailey.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
-- http://www.kylehailey.com/oracle-cpu-time/
SELECT /*+ &&top_level_hints. */
       en.wait_class,
       en.name event,
       em.*,
       ROUND(em.time_waited / em.intsize_csec, 3) aas,
       CASE WHEN en.wait_class = ''User I/O'' THEN 10 * em.time_waited  / em.wait_count END avg_io_ms
  FROM gv$eventmetric em,
       gv$event_name en
 WHERE em.inst_id = en.inst_id
   AND em.event_id = en.event_id
   AND em.event# = en.event#
   AND em.time_waited > 0
   AND em.wait_count > 0
   AND en.wait_class != ''Idle''
 ORDER BY
       em.inst_id,
       en.wait_class,
       en.name';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'System Metric for past minute';
DEF main_table = 'GV$SYSMETRIC';
BEGIN
  :sql_text := '
-- inspired by Kyle Hailey blogs
-- http://www.kylehailey.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
-- http://www.kylehailey.com/oracle-cpu-time/
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sysmetric
 WHERE group_id = 2 -- 1 minute
 ORDER BY
       inst_id,
       metric_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'System Metric Summary for past hour';
DEF main_table = 'GV$SYSMETRIC_SUMMARY';
BEGIN
  :sql_text := '
-- inspired by Kyle Hailey blogs
-- http://www.kylehailey.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
-- http://www.kylehailey.com/oracle-cpu-time/
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sysmetric_summary
 ORDER BY
       inst_id,
       metric_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Wait Statistics';
DEF main_table = 'GV$WAITSTAT';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$waitstat
 WHERE count > 0
 ORDER BY
       class,
       inst_id
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'System Wait Class';
DEF main_table = 'GV$SYSTEM_WAIT_CLASS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$system_wait_class
 ORDER BY
       inst_id,
       time_waited DESC
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Segment Statistics';
DEF main_table = 'GV$SEGSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       statistic_name, SUM(value) value
  FROM gv$segstat
 GROUP BY 
       statistic_name
 ORDER BY 1
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'SQL Monitor Recent Executions Detail';
DEF abstract = 'Aggregated by SQL_ID and SQL Execution. Sorted by SQL_ID and Execution Start Time.';
DEF main_table = 'GV$SQL_MONITOR';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       sql_id,
       sql_exec_start,
       sql_exec_id,
       NVL(MAX(px_qcinst_id), MAX(inst_id)) inst_id,
       MAX(sql_plan_hash_value) sql_plan_hash_value,
       MAX(username) username,
       MAX(service_name) service_name,
       MAX(module) module,
       MAX(px_is_cross_instance) px_is_cross_instance,
       MAX(px_maxdop) px_maxdop,
       MAX(px_maxdop_instances) px_maxdop_instances,
       MAX(px_servers_requested) px_servers_requested,
       MAX(px_servers_allocated) px_servers_allocated,
       MAX(error_number) error_number,
       MAX(error_facility) error_facility,
       MAX(error_message) error_message,
       COUNT(*) processes,
       1 executions,
       SUM(fetches) fetches,
       SUM(buffer_gets) buffer_gets,
       SUM(disk_reads) disk_reads,
       SUM(direct_writes) direct_writes,
       SUM(io_interconnect_bytes) io_interconnect_bytes,
       SUM(physical_read_requests) physical_read_requests,
       SUM(physical_read_bytes) physical_read_bytes,
       SUM(physical_write_requests) physical_write_requests,
       SUM(physical_write_bytes) physical_write_bytes,
       SUM(elapsed_time) elapsed_time,
       SUM(queuing_time) queuing_time,
       SUM(cpu_time) cpu_time,
       SUM(application_wait_time) application_wait_time,
       SUM(concurrency_wait_time) concurrency_wait_time,
       SUM(cluster_wait_time) cluster_wait_time,
       SUM(user_io_wait_time) user_io_wait_time,
       SUM(plsql_exec_time) plsql_exec_time,
       SUM(java_exec_time) java_exec_time,
       MAX(sql_text) sql_text
  FROM gv$sql_monitor
 WHERE status LIKE ''DONE%''
 GROUP BY
       sql_id,
       sql_exec_start,
       sql_exec_id
HAVING MAX(sql_text) IS NOT NULL
 ORDER BY
       sql_id,
       sql_exec_start,
       sql_exec_id
';
END;
/
@@&&skip_tuning.&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'SQL Monitor Recent Executions Summary';
DEF abstract = 'Aggregated by SQL_ID and sorted by Total Elapsed Time.';
DEF main_table = 'GV$SQL_MONITOR';
BEGIN
  :sql_text := '
WITH
monitored_sql AS (
SELECT /*+ &&sq_fact_hints. */
       sql_id,
       sql_exec_start,
       sql_exec_id,
       NVL(MAX(px_qcinst_id), MAX(inst_id)) inst_id,
       MAX(sql_plan_hash_value) sql_plan_hash_value,
       MAX(username) username,
       MAX(service_name) service_name,
       MAX(module) module,
       MAX(px_is_cross_instance) px_is_cross_instance,
       MAX(px_maxdop) px_maxdop,
       MAX(px_maxdop_instances) px_maxdop_instances,
       MAX(px_servers_requested) px_servers_requested,
       MAX(px_servers_allocated) px_servers_allocated,
       MAX(error_number) error_number,
       MAX(error_facility) error_facility,
       MAX(error_message) error_message,
       COUNT(*) processes,
       1 executions,
       SUM(fetches) fetches,
       SUM(buffer_gets) buffer_gets,
       SUM(disk_reads) disk_reads,
       SUM(direct_writes) direct_writes,
       SUM(io_interconnect_bytes) io_interconnect_bytes,
       SUM(physical_read_requests) physical_read_requests,
       SUM(physical_read_bytes) physical_read_bytes,
       SUM(physical_write_requests) physical_write_requests,
       SUM(physical_write_bytes) physical_write_bytes,
       SUM(elapsed_time) elapsed_time,
       SUM(queuing_time) queuing_time,
       SUM(cpu_time) cpu_time,
       SUM(application_wait_time) application_wait_time,
       SUM(concurrency_wait_time) concurrency_wait_time,
       SUM(cluster_wait_time) cluster_wait_time,
       SUM(user_io_wait_time) user_io_wait_time,
       SUM(plsql_exec_time) plsql_exec_time,
       SUM(java_exec_time) java_exec_time,
       MAX(sql_text) sql_text
  FROM gv$sql_monitor
 WHERE status LIKE ''DONE%''
 GROUP BY
       sql_id,
       sql_exec_start,
       sql_exec_id
HAVING MAX(sql_text) IS NOT NULL
)
SELECT /*+ &&top_level_hints. */
       sql_id,
       SUM(executions) executions,
       MIN(sql_exec_start) min_sql_exec_start,
       MAX(sql_exec_start) max_sql_exec_start,
       SUM(elapsed_time) sum_elapsed_time,
       ROUND(AVG(elapsed_time)) avg_elapsed_time,
       ROUND(MIN(elapsed_time)) min_elapsed_time,
       ROUND(MAX(elapsed_time)) max_elapsed_time,
       SUM(cpu_time) sum_cpu_time,
       ROUND(AVG(cpu_time)) avg_cpu_time,
       ROUND(MIN(cpu_time)) min_cpu_time,
       ROUND(MAX(cpu_time)) max_cpu_time,
       SUM(user_io_wait_time) sum_user_io_wait_time,
       ROUND(AVG(user_io_wait_time)) avg_user_io_wait_time,
       ROUND(MIN(user_io_wait_time)) min_user_io_wait_time,
       ROUND(MAX(user_io_wait_time)) max_user_io_wait_time,
       SUM(buffer_gets) sum_buffer_gets,
       ROUND(AVG(buffer_gets)) avg_buffer_gets,
       ROUND(MIN(buffer_gets)) min_buffer_gets,
       ROUND(MAX(buffer_gets)) max_buffer_gets,
       SUM(disk_reads) sum_disk_reads,
       ROUND(AVG(disk_reads)) avg_disk_reads,
       ROUND(MIN(disk_reads)) min_disk_reads,
       ROUND(MAX(disk_reads)) max_disk_reads,
       SUM(processes) sum_processes,
       ROUND(AVG(processes)) avg_processes,
       ROUND(MIN(processes)) min_processes,
       ROUND(MAX(processes)) max_processes,
       COUNT(DISTINCT inst_id) distinct_inst_id,
       MIN(inst_id) min_inst_id,
       MAX(inst_id) max_inst_id,
       COUNT(DISTINCT sql_plan_hash_value) distinct_sql_plan_hash_value,
       MIN(sql_plan_hash_value) min_sql_plan_hash_value,
       MAX(sql_plan_hash_value) max_sql_plan_hash_value,
       COUNT(DISTINCT username) distinct_username,
       MAX(username) max_username,
       COUNT(DISTINCT service_name) distinct_service_name,
       MAX(service_name) max_service_name,
       COUNT(DISTINCT module) distinct_module,
       MAX(module) max_module,
       MAX(px_is_cross_instance) max_px_is_cross_instance,
       MIN(px_is_cross_instance) min_px_is_cross_instance,
       MAX(px_maxdop) max_px_maxdop,
       MIN(px_maxdop) min_px_maxdop,
       MAX(px_maxdop_instances) max_px_maxdop_instances,
       MIN(px_maxdop_instances) min_px_maxdop_instances,
       MAX(px_servers_requested) max_px_servers_requested,
       MIN(px_servers_requested) min_px_servers_requested,
       MAX(px_servers_allocated) max_px_servers_allocated,
       MIN(px_servers_allocated) min_px_servers_allocated,
       MAX(error_number) max_error_number,
       MAX(error_facility) max_error_facility,
       MAX(error_message) max_error_message,
       MAX(sql_text) sql_text
  FROM monitored_sql
 GROUP BY
       sql_id
 ORDER BY
       sum_elapsed_time DESC,
       sql_id
';
END;
/
@@&&skip_tuning.&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'SQL Monitor Recent Executions DONE (ERROR)';
DEF abstract = 'Aggregated by SQL_ID and Error.';
DEF main_table = 'GV$SQL_MONITOR';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       sql_id,
       error_number,
       error_facility,
       error_message,
       COUNT(*) executions
  FROM gv$sql_monitor
 WHERE status = ''DONE (ERROR)''
 GROUP BY
       sql_id,
       error_number,
       error_facility,
       error_message
HAVING MAX(sql_text) IS NOT NULL
 ORDER BY
       sql_id,
       error_number,
       error_facility,
       error_message
';
END;
/
@@&&skip_tuning.&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'SQL Monitor (QUEUED)';
DEF main_table = 'GV$SQL_MONITOR';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       sql_id,
       username,
       service_name,
       module,
       px_is_cross_instance,
       px_maxdop,
       px_maxdop_instances,
       px_servers_requested,
       px_servers_allocated,
       elapsed_time,
       queuing_time,
       sql_text
  FROM gv$sql_monitor
 WHERE status = ''QUEUED''
 ORDER BY
       sql_id,
       queuing_time
';
END;
/
@@&&skip_tuning.&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'SQL with changing Elapsed Time per Execution (list)';
DEF abstract = 'SQL Statements with "Elapsed Time per Execution" changing over time.';
DEF main_table = 'DBA_HIST_SQLSTAT';
DEF days_of_history_accessed = '31';
DEF captured_at_least_x_times = '10';
DEF captured_at_least_x_days_apart = '5';
DEF med_elap_microsecs_threshold = '1e4';
DEF min_slope_threshold = '0.1';
DEF max_num_rows_x = '20';

COL med_secs_per_exec HEA 'Median Secs|Per Exec';
COL std_secs_per_exec HEA 'Std Dev Secs|Per Exec';
COL avg_secs_per_exec HEA 'Avg Secs|Per Exec';
COL min_secs_per_exec HEA 'Min Secs|Per Exec';
COL max_secs_per_exec HEA 'Max Secs|Per Exec';
COL plans FOR 9999;
BEGIN
  :sql_text := '
WITH
per_time AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE) days_ago,
       SUM(h.elapsed_time_total) / SUM(h.executions_total) time_per_exec
  FROM dba_hist_sqlstat h, 
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.executions_total > 0 
   AND h.plan_hash_value > 0
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND CAST(s.end_interval_time AS DATE) > SYSDATE - &&days_of_history_accessed. 
 GROUP BY
       h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE)
),
avg_time AS (
SELECT /*+ &&sq_fact_hints. */
       dbid,
       sql_id, 
       MEDIAN(time_per_exec) med_time_per_exec,
       STDDEV(time_per_exec) std_time_per_exec,
       AVG(time_per_exec)    avg_time_per_exec,
       MIN(time_per_exec)    min_time_per_exec,
       MAX(time_per_exec)    max_time_per_exec       
  FROM per_time
 GROUP BY
       dbid,
       sql_id
HAVING COUNT(*) >= &&captured_at_least_x_times. 
   AND MAX(days_ago) - MIN(days_ago) >= &&captured_at_least_x_days_apart.
   AND MEDIAN(time_per_exec) > &&med_elap_microsecs_threshold.
),
time_over_median AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.sql_id,
       h.days_ago,
       (h.time_per_exec / a.med_time_per_exec) time_per_exec_over_med,
       a.med_time_per_exec,
       a.std_time_per_exec,
       a.avg_time_per_exec,
       a.min_time_per_exec,
       a.max_time_per_exec
  FROM per_time h, avg_time a
 WHERE a.sql_id = h.sql_id
),
ranked AS (
SELECT /*+ &&sq_fact_hints. */
       RANK () OVER (ORDER BY ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) DESC) rank_num,
       t.dbid,
       t.sql_id,
       CASE WHEN REGR_SLOPE(t.time_per_exec_over_med, t.days_ago) > 0 THEN ''IMPROVING'' ELSE ''REGRESSING'' END change,
       ROUND(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago), 3) slope,
       ROUND(AVG(t.med_time_per_exec)/1e6, 3) med_secs_per_exec,
       ROUND(AVG(t.std_time_per_exec)/1e6, 3) std_secs_per_exec,
       ROUND(AVG(t.avg_time_per_exec)/1e6, 3) avg_secs_per_exec,
       ROUND(MIN(t.min_time_per_exec)/1e6, 3) min_secs_per_exec,
       ROUND(MAX(t.max_time_per_exec)/1e6, 3) max_secs_per_exec
  FROM time_over_median t
 GROUP BY
       t.dbid,
       t.sql_id
HAVING ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) > &&min_slope_threshold.
)
SELECT /*+ &&top_level_hints. */
       r.sql_id,
       r.change,
       r.slope,
       r.med_secs_per_exec med_secs_per_exec,
       r.std_secs_per_exec std_secs_per_exec,
       r.avg_secs_per_exec avg_secs_per_exec,
       r.min_secs_per_exec min_secs_per_exec,
       r.max_secs_per_exec max_secs_per_exec,
       (SELECT COUNT(DISTINCT p.plan_hash_value) FROM dba_hist_sql_plan p WHERE p.dbid = r.dbid AND p.sql_id = r.sql_id) plans,
       REPLACE((SELECT DBMS_LOB.SUBSTR(s.sql_text, 4000) FROM dba_hist_sqltext s WHERE s.dbid = r.dbid AND s.sql_id = r.sql_id), CHR(10)) sql_text
  FROM ranked r
 WHERE r.rank_num <= &&max_num_rows_x.
 ORDER BY
       r.rank_num
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'SQL with changing Elapsed Time per Execution (time series)';
DEF abstract = 'SQL Statements with "Elapsed Time per Execution" changing over time.';
DEF main_table = 'DBA_HIST_SQLSTAT';
DEF days_of_history_accessed = '31';
DEF captured_at_least_x_times = '10';
DEF captured_at_least_x_days_apart = '5';
DEF med_elap_microsecs_threshold = '1e4';
DEF min_slope_threshold = '0.1';
DEF max_num_rows_x = '20';

COL rank_num FOR 9999 HEA 'Rank';
COL instance_number_x FOR 9999 HEA 'Inst';
COL end_time_x HEA 'End Time';
COL plan_hash_value_x HEA 'Plan|Hash Value';
COL executions_total_x FOR 999,999,999 HEA 'Execs|Total';
COL rows_per_exec HEA 'Rows Per Exec';
COL et_secs_per_exec HEA 'Elap Secs|Per Exec';
COL cpu_secs_per_exec HEA 'CPU Secs|Per Exec';
COL io_secs_per_exec HEA 'IO Secs|Per Exec';
COL cl_secs_per_exec HEA 'Clus Secs|Per Exec';
COL ap_secs_per_exec HEA 'App Secs|Per Exec';
COL cc_secs_per_exec HEA 'Conc Secs|Per Exec';
COL pl_secs_per_exec HEA 'PLSQL Secs|Per Exec';
COL ja_secs_per_exec HEA 'Java Secs|Per Exec';
COL bg_per_exec HEA 'Buffer Gets|Per Exec';
COL dr_per_exec HEA 'Disk Reads|Per Exec';
COL dw_per_exec HEA 'Direct Writes|Per Exec';
COL prr_per_exec HEA 'Phy Read Reqs|Per Exec';
COL prb_per_exec HEA 'Phy Read Bytes|Per Exec';
COL pwr_per_exec HEA 'Phy Write Reqs|Per Exec';
COL pwb_per_exec HEA 'Phy Write Bytes|Per Exec';
COL ofb_per_exec HEA 'IO Offl  Eleg Bytes|Per Exec';
COL icb_per_exec HEA 'IO Interc Bytes|Per Exec';
COL opr_per_exec HEA 'Opt Phy Reads|Per Exec';
COL unb_per_exec HEA 'Cell Uncomp Bytes|Per Exec';
COL orb_per_exec HEA 'IO Offl Rtn Bytes|Per Exec';

BEGIN
  :sql_text := '
WITH
per_time AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE) days_ago,
       SUM(h.elapsed_time_total) / SUM(h.executions_total) time_per_exec
  FROM dba_hist_sqlstat h, 
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.executions_total > 0 
   AND h.plan_hash_value > 0
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND CAST(s.end_interval_time AS DATE) > SYSDATE - &&days_of_history_accessed. 
 GROUP BY
       h.dbid,
       h.sql_id,
       SYSDATE - CAST(s.end_interval_time AS DATE)
),
avg_time AS (
SELECT /*+ &&sq_fact_hints. */
       dbid,
       sql_id, 
       MEDIAN(time_per_exec) med_time_per_exec,
       STDDEV(time_per_exec) std_time_per_exec,
       AVG(time_per_exec)    avg_time_per_exec,
       MIN(time_per_exec)    min_time_per_exec,
       MAX(time_per_exec)    max_time_per_exec       
  FROM per_time
 GROUP BY
       dbid,
       sql_id
HAVING COUNT(*) >= &&captured_at_least_x_times. 
   AND MAX(days_ago) - MIN(days_ago) >= &&captured_at_least_x_days_apart.
   AND MEDIAN(time_per_exec) > &&med_elap_microsecs_threshold.
),
time_over_median AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.sql_id,
       h.days_ago,
       (h.time_per_exec / a.med_time_per_exec) time_per_exec_over_med,
       a.med_time_per_exec,
       a.std_time_per_exec,
       a.avg_time_per_exec,
       a.min_time_per_exec,
       a.max_time_per_exec
  FROM per_time h, avg_time a
 WHERE a.sql_id = h.sql_id
),
ranked AS (
SELECT /*+ &&sq_fact_hints. */
       RANK () OVER (ORDER BY ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) DESC) rank_num,
       t.dbid,
       t.sql_id,
       CASE WHEN REGR_SLOPE(t.time_per_exec_over_med, t.days_ago) > 0 THEN ''IMPROVING'' ELSE ''REGRESSING'' END change,
       ROUND(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago), 3) slope,
       ROUND(AVG(t.med_time_per_exec)/1e6, 3) med_secs_per_exec,
       ROUND(AVG(t.std_time_per_exec)/1e6, 3) std_secs_per_exec,
       ROUND(AVG(t.avg_time_per_exec)/1e6, 3) avg_secs_per_exec,
       ROUND(MIN(t.min_time_per_exec)/1e6, 3) min_secs_per_exec,
       ROUND(MAX(t.max_time_per_exec)/1e6, 3) max_secs_per_exec
  FROM time_over_median t
 GROUP BY
       t.dbid,
       t.sql_id
HAVING ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) > &&min_slope_threshold.
)
SELECT /*+ &&top_level_hints. */
         r.rank_num
       , h.sql_id
       , h.instance_number instance_number_x
       , TO_CHAR(CAST(s.end_interval_time AS DATE), ''YYYY-MM-DD HH24:MI'') end_time_x
       , h.plan_hash_value plan_hash_value_x
       , h.executions_total executions_total_x
       , ROUND(h.rows_processed_total / h.executions_total) rows_per_exec
       , ROUND(h.elapsed_time_total   / h.executions_total / 1e6, 3) et_secs_per_exec
       , ROUND(h.cpu_time_total       / h.executions_total / 1e6, 3) cpu_secs_per_exec
       , ROUND(h.iowait_total         / h.executions_total / 1e6, 3) io_secs_per_exec
       , ROUND(h.clwait_total         / h.executions_total / 1e6, 3) cl_secs_per_exec
       , ROUND(h.apwait_total         / h.executions_total / 1e6, 3) ap_secs_per_exec
       , ROUND(h.ccwait_total         / h.executions_total / 1e6, 3) cc_secs_per_exec
       , ROUND(h.plsexec_time_total   / h.executions_total / 1e6, 3) pl_secs_per_exec
       , ROUND(h.javexec_time_total   / h.executions_total / 1e6, 3) ja_secs_per_exec
       , ROUND(h.buffer_gets_total    / h.executions_total) bg_per_exec
       , ROUND(h.disk_reads_total     / h.executions_total) dr_per_exec
       , ROUND(h.direct_writes_total  / h.executions_total) dw_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.physical_read_requests_total   / h.executions_total) prr_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.physical_read_bytes_total      / h.executions_total) prb_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.physical_write_requests_total  / h.executions_total) pwr_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.physical_write_bytes_total     / h.executions_total) pwb_per_exec	
       &&skip_10g.&&skip_11r1., ROUND(h.io_offload_elig_bytes_total    / h.executions_total) ofb_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.io_interconnect_bytes_total    / h.executions_total) icb_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.optimized_physical_reads_total / h.executions_total) opr_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.cell_uncompressed_bytes_total  / h.executions_total) unb_per_exec
       &&skip_10g.&&skip_11r1., ROUND(h.io_offload_return_bytes_total  / h.executions_total) orb_per_exec
  FROM ranked r,
       dba_hist_sqlstat h, 
       dba_hist_snapshot s
 WHERE r.rank_num <= &&max_num_rows_x.
   AND h.sql_id = r.sql_id
   AND h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.executions_total > 0 
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
 ORDER BY
       r.rank_num,
       h.sql_id,
       h.instance_number,
       s.end_interval_time,
       h.plan_hash_value
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'SQL with multiple Execution Plans';
DEF abstract = 'SQL Statements with multiple Execution Plans performing significantly different';
DEF main_table = 'DBA_HIST_SQLSTAT';
DEF days_of_history_accessed = '31';
DEF max_num_rows_x = '20';

COL plans FOR 9999;
COL aprox_tot_secs HEA 'Approx|Total Secs';
COL med_secs_per_exec HEA 'Median Secs|Per Exec';
COL std_secs_per_exec HEA 'Std Dev Secs|Per Exec';
COL avg_secs_per_exec HEA 'Avg Secs|Per Exec';
COL min_secs_per_exec HEA 'Min Secs|Per Exec';
COL max_secs_per_exec HEA 'Max Secs|Per Exec';
BEGIN
  :sql_text := '
WITH
per_phv AS (
SELECT /*+ &&sq_fact_hints. */
       h.dbid,
       h.sql_id,
       h.plan_hash_value, 
       MIN(s.begin_interval_time) min_time,
       MAX(s.end_interval_time) max_time,
       MEDIAN(h.elapsed_time_total / h.executions_total) med_time_per_exec,
       STDDEV(h.elapsed_time_total / h.executions_total) std_time_per_exec,
       AVG(h.elapsed_time_total / h.executions_total)    avg_time_per_exec,
       MIN(h.elapsed_time_total / h.executions_total)    min_time_per_exec,
       MAX(h.elapsed_time_total / h.executions_total)    max_time_per_exec,
       STDDEV(h.elapsed_time_total / h.executions_total) / AVG(h.elapsed_time_total / h.executions_total) std_dev,
       MAX(h.executions_total) executions_total,
       MEDIAN(h.elapsed_time_total / h.executions_total) * MAX(h.executions_total) total_elapsed_time
  FROM dba_hist_sqlstat h, 
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.executions_total > 1 
   AND h.plan_hash_value > 0
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND CAST(s.end_interval_time AS DATE) > SYSDATE - &&days_of_history_accessed. 
 GROUP BY
       h.dbid,
       h.sql_id,
       h.plan_hash_value
),
ranked1 AS (
SELECT /*+ &&sq_fact_hints. */
       RANK () OVER (ORDER BY STDDEV(med_time_per_exec)/AVG(med_time_per_exec) DESC) rank_num1,
       dbid,
       sql_id,
       COUNT(*) plans,
       SUM(total_elapsed_time) total_elapsed_time,
       MIN(med_time_per_exec) min_med_time_per_exec,
       MAX(med_time_per_exec) max_med_time_per_exec
  FROM per_phv
 GROUP BY
       dbid,
       sql_id
HAVING COUNT(*) > 1
),
ranked2 AS (
SELECT /*+ &&sq_fact_hints. */
       RANK () OVER (ORDER BY r.total_elapsed_time DESC) rank_num2,
       r.rank_num1,
       r.sql_id,
       r.plans,
       p.plan_hash_value,
       TO_CHAR(CAST(p.min_time AS DATE), ''YYYY-MM-DD/HH24'') min_time,
       TO_CHAR(CAST(p.max_time AS DATE), ''YYYY-MM-DD/HH24'') max_time,
       ROUND(p.med_time_per_exec / 1e6, 3) med_secs_per_exec,
       p.executions_total executions,
       ROUND(p.med_time_per_exec * p.executions_total / 1e6, 3) aprox_tot_secs,
       ROUND(p.std_time_per_exec / 1e6, 3) std_secs_per_exec,
       ROUND(p.avg_time_per_exec / 1e6, 3) avg_secs_per_exec,
       ROUND(p.min_time_per_exec / 1e6, 3) min_secs_per_exec,
       ROUND(p.max_time_per_exec / 1e6, 3) max_secs_per_exec,
       REPLACE((SELECT DBMS_LOB.SUBSTR(s.sql_text, 4000) FROM dba_hist_sqltext s WHERE s.dbid = r.dbid AND s.sql_id = r.sql_id), CHR(10)) sql_text
  FROM ranked1 r,
       per_phv p
 WHERE r.rank_num1 <= &&max_num_rows_x. * 5
   AND p.dbid = r.dbid
   AND p.sql_id = r.sql_id
)
SELECT /*+ &&top_level_hints. */
       r.sql_id,
       r.plans,
       r.plan_hash_value,
       r.min_time,
       r.max_time,
       r.med_secs_per_exec,
       r.executions,
       r.aprox_tot_secs,
       r.std_secs_per_exec,
       r.avg_secs_per_exec,
       r.min_secs_per_exec,
       r.max_secs_per_exec,
       r.sql_text
  FROM ranked2 r
 WHERE rank_num2 <= &&max_num_rows_x.
 ORDER BY
       r.rank_num2,
       r.sql_id,
       r.min_time,
       r.plan_hash_value
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF title = 'Result Cache related parameters';
DEF main_table = 'GV$SYSTEM_PARAMETER2';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       inst_id, name "PARAMETER", value, isdefault, ismodified
  FROM gv$system_parameter2
 WHERE name IN (''result_cache_mode'',''result_cache_max_size'',''result_cache_max_result'')
 ORDER BY 2,1,3
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Result Cache status';
DEF main_table = 'DBMS_RESULT_CACHE';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT dbms_result_cache.status FROM dual
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Result Cache memory';
DEF main_table = 'GV$RESULT_CACHE_MEMORY';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       inst_id, free, count(*)
  FROM gv$result_cache_memory
 GROUP BY inst_id, free
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Result Cache statistics';
DEF main_table = 'GV$RESULT_CACHE_STATISTICS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       inst_id, name, value
  FROM gv$result_cache_statistics
 ORDER BY 1, 2
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql

DEF title = 'Client Result Cache statistics';
DEF main_table = 'CLIENT_RESULT_CACHE_STATS$';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       stat_id, SUBSTR(name,1,20), value, cache_id
  FROM client_result_cache_stats$
 ORDER BY cache_id, stat_id
';
END;
/
@@&&skip_10g.&&skip_11r1.edb360_9a_pre_one.sql
