@@&&edb360_0g.tkprof.sql
DEF section_id = '6c';
DEF section_name = 'Active Session History (ASH) - Top SQL';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'GV$ACTIVE_SESSION_HISTORY';
BEGIN
  :sql_text_backup := '
WITH
hist AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       sql_id,
       ROW_NUMBER () OVER (ORDER BY COUNT(*) DESC) rn,
       COUNT(*) samples
  FROM gv$active_session_history
 WHERE @filter_predicate@
   AND sql_id IS NOT NULL
 GROUP BY
       sql_id
),
total AS (
SELECT /*+ &&sq_fact_hints. */ SUM(samples) samples FROM hist
)
SELECT h.sql_id,
       h.samples,
       ROUND(100 * h.samples / t.samples, 1) percent,
       (SELECT v2.sql_text FROM gv$sql v2 WHERE v2.sql_id = h.sql_id AND ROWNUM = 1) sql_text
  FROM hist h,
       total t
 WHERE h.samples >= t.samples / 1000 AND rn <= 14
 UNION ALL
SELECT ''Others'',
       NVL(SUM(h.samples), 0) samples,
       NVL(ROUND(100 * SUM(h.samples) / AVG(t.samples), 1), 0) percent,
       NULL sql_text
  FROM hist h,
       total t
 WHERE h.samples < t.samples / 1000 OR rn > 14
 ORDER BY 2 DESC NULLS LAST
';
END;
/

/*****************************************************************************************/

DEF skip_pch = '';
DEF title = 'ASH Top SQL for Cluster from MEM';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', '1 = 1 /* all instances */');
@@edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 1;
DEF title = 'ASH Top SQL for Instance 1 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 1');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 2;
DEF title = 'ASH Top SQL for Instance 2 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 2');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 3;
DEF title = 'ASH Top SQL for Instance 3 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 3');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 4;
DEF title = 'ASH Top SQL for Instance 4 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 4');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 5;
DEF title = 'ASH Top SQL for Instance 5 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 5');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 6;
DEF title = 'ASH Top SQL for Instance 6 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 6');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 7;
DEF title = 'ASH Top SQL for Instance 7 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 7');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE inst_id = 8;
DEF title = 'ASH Top SQL for Instance 8 from MEM';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'inst_id = 8');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

DEF main_table = 'DBA_HIST_ACTIVE_SESS_HISTORY';
BEGIN
  :sql_text_backup := '
WITH
hist AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       sql_id,
       dbid,
       ROW_NUMBER () OVER (ORDER BY COUNT(*) DESC) rn,
       COUNT(*) samples
  FROM dba_hist_active_sess_history
 WHERE @filter_predicate@
   AND sql_id IS NOT NULL
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
 GROUP BY
       sql_id,
       dbid
),
total AS (
SELECT /*+ &&sq_fact_hints. */ SUM(samples) samples FROM hist
)
SELECT h.sql_id,
       h.samples,
       ROUND(100 * h.samples / t.samples, 1) percent,
       (SELECT DBMS_LOB.SUBSTR(s.sql_text, 1000) FROM dba_hist_sqltext s WHERE s.sql_id = h.sql_id AND s.dbid = h.dbid AND ROWNUM = 1) sql_text
  FROM hist h,
       total t
 WHERE h.samples >= t.samples / 1000 AND rn <= 14
 UNION ALL
SELECT ''Others'',
       NVL(SUM(h.samples), 0) samples,
       NVL(ROUND(100 * SUM(h.samples) / AVG(t.samples), 1), 0) percent,
       NULL sql_text
  FROM hist h,
       total t
 WHERE h.samples < t.samples / 1000 OR rn > 14
 ORDER BY 2 DESC NULLS LAST
';
END;
/

/*****************************************************************************************/

SELECT ', between '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 1, 'YYYY-MM-DD HH24:MM:SS')||' and '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS'), 'YYYY-MM-DD HH24:MM:SS') between_times FROM DUAL;

DEF skip_pch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'ASH Top SQL for Cluster for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'ASH Top SQL for Instance 1 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 1 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'ASH Top SQL for Instance 2 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 2 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'ASH Top SQL for Instance 3 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 3 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'ASH Top SQL for Instance 4 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 4 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'ASH Top SQL for Instance 5 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 5 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'ASH Top SQL for Instance 6 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 6 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'ASH Top SQL for Instance 7 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 7 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'ASH Top SQL for Instance 8 for 1 day';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 8 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 1 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

SELECT ', between '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 7, 'YYYY-MM-DD HH24:MM:SS')||' and '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS'), 'YYYY-MM-DD HH24:MM:SS')||', and between &&edb360_conf_work_time_from. and &&edb360_conf_work_time_to. hours' between_times FROM DUAL;

DEF skip_pch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'ASH Top SQL for Cluster for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'ASH Top SQL for Instance 1 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 1 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'ASH Top SQL for Instance 2 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 2 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'ASH Top SQL for Instance 3 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 3 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'ASH Top SQL for Instance 4 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 4 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'ASH Top SQL for Instance 5 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 5 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'ASH Top SQL for Instance 6 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 6 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'ASH Top SQL for Instance 7 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 7 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'ASH Top SQL for Instance 8 for 5 working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 8 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

SELECT ', between '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 7, 'YYYY-MM-DD HH24:MM:SS')||' and '||TO_CHAR(TO_TIMESTAMP('&&tool_sysdate.', 'YYYYMMDDHH24MISS'), 'YYYY-MM-DD HH24:MM:SS') between_times FROM DUAL;

DEF skip_pch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'ASH Top SQL for Cluster for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'ASH Top SQL for Instance 1 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 1 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'ASH Top SQL for Instance 2 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 2 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'ASH Top SQL for Instance 3 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 3 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'ASH Top SQL for Instance 4 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 4 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'ASH Top SQL for Instance 5 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 5 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'ASH Top SQL for Instance 6 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 6 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'ASH Top SQL for Instance 7 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 7 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'ASH Top SQL for Instance 8 for 7 days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 8 AND sample_time BETWEEN TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'') - 7 AND TO_TIMESTAMP(''&&tool_sysdate.'', ''YYYYMMDDHH24MISS'')');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

SELECT '&&between_dates., and between &&edb360_conf_work_time_from. and &&edb360_conf_work_time_to. hours' between_times FROM DUAL;

DEF skip_pch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'ASH Top SQL for Cluster for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'ASH Top SQL for Instance 1 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 1 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'ASH Top SQL for Instance 2 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 2 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'ASH Top SQL for Instance 3 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 3 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'ASH Top SQL for Instance 4 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 4 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'ASH Top SQL for Instance 5 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 5 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'ASH Top SQL for Instance 6 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 6 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'ASH Top SQL for Instance 7 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 7 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'ASH Top SQL for Instance 8 for &&hist_work_days. working days';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 8 AND TO_CHAR(sample_time, ''D'') BETWEEN ''&&edb360_conf_work_day_from.'' AND ''&&edb360_conf_work_day_to.'' AND TO_CHAR(sample_time, ''HH24'') BETWEEN ''&&edb360_conf_work_time_from.'' AND ''&&edb360_conf_work_time_to.''');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

SELECT '&&between_dates.' between_times FROM DUAL;

DEF skip_pch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'ASH Top SQL for Cluster for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', '1 = 1');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'ASH Top SQL for Instance 1 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 1');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'ASH Top SQL for Instance 2 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 2');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'ASH Top SQL for Instance 3 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 3');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'ASH Top SQL for Instance 4 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 4');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'ASH Top SQL for Instance 5 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 5');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'ASH Top SQL for Instance 6 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 6');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'ASH Top SQL for Instance 7 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 7');
@@&&skip_all.edb360_9a_pre_one.sql

DEF skip_pch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'ASH Top SQL for Instance 8 for &&history_days. days of history';
DEF title_suffix = '&&between_times.';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'instance_number = 8');
@@&&skip_all.edb360_9a_pre_one.sql

/*****************************************************************************************/

DEF skip_lch = 'Y';
DEF skip_pch = 'Y';