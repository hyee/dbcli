@@&&edb360_0g.tkprof.sql
DEF section_id = '3f';
DEF section_name = 'Interconnect Ping Latency Stats';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_INTERCONNECT_PINGS';
DEF chartype = 'LineChart';
DEF stacked = '';
DEF vaxis = 'Average Ping Latencies in Milliseconds';
DEF vbaseline = '';

BEGIN
  :sql_text_backup := '
WITH
interconnect_pings AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       h.snap_id,
       h.dbid,
       h.instance_number,
       h.target_instance,
       s.end_interval_time,
       s.startup_time - LAG(s.startup_time) OVER (PARTITION BY h.dbid, h.instance_number, h.target_instance ORDER BY h.snap_id) startup_time_interval,
       h.cnt_500b - LAG(h.cnt_500b) OVER (PARTITION BY h.dbid, h.instance_number, h.target_instance ORDER BY h.snap_id) cnt_500b,
       h.cnt_8k - LAG(h.cnt_8k) OVER (PARTITION BY h.dbid, h.instance_number, h.target_instance ORDER BY h.snap_id) cnt_8k,
       h.wait_500b - LAG(h.wait_500b) OVER (PARTITION BY h.dbid, h.instance_number, h.target_instance ORDER BY h.snap_id) wait_500b,
       h.wait_8k - LAG(h.wait_8k) OVER (PARTITION BY h.dbid, h.instance_number, h.target_instance ORDER BY h.snap_id) wait_8k
  FROM dba_hist_interconnect_pings h,
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.cnt_500b > 100 -- else too small
   AND h.cnt_8k > 100 -- else too small
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND s.end_interval_time - s.begin_interval_time > TO_DSINTERVAL(''+00 00:01:00.000000'') -- exclude snaps less than 1m appart
),
per_source_and_target AS (
SELECT /*+ &&sq_fact_hints. */
       MAX(snap_id) snap_id,
       instance_number,
       target_instance,
       TRUNC(end_interval_time, ''HH'') end_time,
       SUM(cnt_500b) cnt_500b,
       SUM(cnt_8k) cnt_8k,
       SUM(wait_500b) wait_500b,
       SUM(wait_8k) wait_8k,
       ROUND(SUM(wait_500b) / SUM(cnt_500b) / 1000, 2) Avg_Latency_500B_msg,
       ROUND(SUM(wait_8k) / SUM(cnt_8k) / 1000, 2) Avg_Latency_8K_msg
  FROM interconnect_pings
 WHERE startup_time_interval = TO_DSINTERVAL(''+00 00:00:00.000000'') -- include only contiguous snaps
   AND cnt_500b > 0
   AND cnt_8k > 0 
   AND wait_500b > 0
   AND wait_8k > 0
 GROUP BY
       instance_number,
       target_instance,
       TRUNC(end_interval_time, ''HH'')
),
per_source AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       instance_number,
       -1 target_instance,
       end_time,
       SUM(cnt_500b) cnt_500b,
       SUM(cnt_8k) cnt_8k,
       SUM(wait_500b) wait_500b,
       SUM(wait_8k) wait_8k,
       ROUND(SUM(wait_500b) / SUM(cnt_500b) / 1000, 2) Avg_Latency_500B_msg,
       ROUND(SUM(wait_8k) / SUM(cnt_8k) / 1000, 2) Avg_Latency_8K_msg
  FROM per_source_and_target
 GROUP BY
       snap_id,
       instance_number,
       end_time
),
per_target AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       -1 instance_number,
       target_instance,
       end_time,
       SUM(cnt_500b) cnt_500b,
       SUM(cnt_8k) cnt_8k,
       SUM(wait_500b) wait_500b,
       SUM(wait_8k) wait_8k,
       ROUND(SUM(wait_500b) / SUM(cnt_500b) / 1000, 2) Avg_Latency_500B_msg,
       ROUND(SUM(wait_8k) / SUM(cnt_8k) / 1000, 2) Avg_Latency_8K_msg
  FROM per_source_and_target
 GROUP BY
       snap_id,
       target_instance,
       end_time
),
per_cluster AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       -1 instance_number,
       -1 target_instance,
       end_time,
       SUM(cnt_500b) cnt_500b,
       SUM(cnt_8k) cnt_8k,
       SUM(wait_500b) wait_500b,
       SUM(wait_8k) wait_8k,
       ROUND(SUM(wait_500b) / SUM(cnt_500b) / 1000, 2) Avg_Latency_500B_msg,
       ROUND(SUM(wait_8k) / SUM(cnt_8k) / 1000, 2) Avg_Latency_8K_msg
  FROM per_source_and_target
 GROUP BY
       snap_id,
       end_time
),
source_and_target_extended AS (
SELECT /*+ &&sq_fact_hints. LEADING(st) */
       st.snap_id,
       st.instance_number,
       st.target_instance,
       st.end_time,
       st.Avg_Latency_500B_msg,
       st.Avg_Latency_8K_msg,
       s.Avg_Latency_500B_msg s_Avg_Latency_500B_msg,
       s.Avg_Latency_8K_msg s_Avg_Latency_8K_msg,
       t.Avg_Latency_500B_msg t_Avg_Latency_500B_msg,
       t.Avg_Latency_8K_msg t_Avg_Latency_8K_msg,
       c.Avg_Latency_500B_msg c_Avg_Latency_500B_msg,
       c.Avg_Latency_8K_msg c_Avg_Latency_8K_msg
  FROM per_source_and_target st,
       per_source s,
       per_target t,
       per_cluster c
 WHERE s.snap_id = st.snap_id
   AND s.instance_number = st.instance_number
   AND s.end_time = st.end_time
   AND t.snap_id = st.snap_id
   AND t.target_instance = st.target_instance
   AND t.end_time = st.end_time
   AND c.snap_id = st.snap_id
   AND c.end_time = st.end_time
-- automatic transitivity does not apply to joins
-- added predicates in case LEADING hint is not obeyed 
   AND t.snap_id = s.snap_id
   AND t.end_time = s.end_time
   AND c.snap_id = s.snap_id
   AND c.end_time = s.end_time
   AND c.snap_id = t.snap_id
   AND c.end_time = t.end_time
 UNION ALL
SELECT s.snap_id,
       s.instance_number,
       s.target_instance,
       s.end_time,
       s.Avg_Latency_500B_msg,
       s.Avg_Latency_8K_msg,
       0 s_Avg_Latency_500B_msg,
       0 s_Avg_Latency_8K_msg,
       0 t_Avg_Latency_500B_msg,
       0 t_Avg_Latency_8K_msg,
       c.Avg_Latency_500B_msg c_Avg_Latency_500B_msg,
       c.Avg_Latency_8K_msg c_Avg_Latency_8K_msg
  FROM per_source s,
       per_cluster c
 WHERE c.snap_id = s.snap_id
   AND c.end_time = s.end_time
 UNION ALL
SELECT t.snap_id,
       t.instance_number,
       t.target_instance,
       t.end_time,
       t.Avg_Latency_500B_msg,
       t.Avg_Latency_8K_msg,
       0 s_Avg_Latency_500B_msg,
       0 s_Avg_Latency_8K_msg,
       0 t_Avg_Latency_500B_msg,
       0 t_Avg_Latency_8K_msg,
       c.Avg_Latency_500B_msg c_Avg_Latency_500B_msg,
       c.Avg_Latency_8K_msg c_Avg_Latency_8K_msg
  FROM per_target t,
       per_cluster c
 WHERE c.snap_id = t.snap_id
   AND c.end_time = t.end_time
),
denorm_target AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       end_time,
       instance_number inst_num,
       SUM(CASE target_instance WHEN 1 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i1,
       SUM(CASE target_instance WHEN 1 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i1,
       SUM(CASE target_instance WHEN 2 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i2,
       SUM(CASE target_instance WHEN 2 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i2,
       SUM(CASE target_instance WHEN 3 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i3,
       SUM(CASE target_instance WHEN 3 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i3,
       SUM(CASE target_instance WHEN 4 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i4,
       SUM(CASE target_instance WHEN 4 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i4,
       SUM(CASE target_instance WHEN 5 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i5,
       SUM(CASE target_instance WHEN 5 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i5,
       SUM(CASE target_instance WHEN 6 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i6,
       SUM(CASE target_instance WHEN 6 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i6,
       SUM(CASE target_instance WHEN 7 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i7,
       SUM(CASE target_instance WHEN 7 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i7,
       SUM(CASE target_instance WHEN 8 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i8,
       SUM(CASE target_instance WHEN 8 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i8,
       MAX(s_Avg_Latency_500B_msg) i_Avg_Latency_500B_msg,
       MAX(s_Avg_Latency_8K_msg) i_Avg_Latency_8K_msg,
       MAX(c_Avg_Latency_500B_msg) c_Avg_Latency_500B_msg,
       MAX(c_Avg_Latency_8K_msg) c_Avg_Latency_8K_msg
  FROM source_and_target_extended
 WHERE instance_number = @instance_number@
 GROUP BY
       snap_id,
       end_time,
       instance_number
),
denorm_source AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       end_time,
       target_instance inst_num,
       SUM(CASE instance_number WHEN 1 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i1,
       SUM(CASE instance_number WHEN 1 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i1,
       SUM(CASE instance_number WHEN 2 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i2,
       SUM(CASE instance_number WHEN 2 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i2,
       SUM(CASE instance_number WHEN 3 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i3,
       SUM(CASE instance_number WHEN 3 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i3,
       SUM(CASE instance_number WHEN 4 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i4,
       SUM(CASE instance_number WHEN 4 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i4,
       SUM(CASE instance_number WHEN 5 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i5,
       SUM(CASE instance_number WHEN 5 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i5,
       SUM(CASE instance_number WHEN 6 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i6,
       SUM(CASE instance_number WHEN 6 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i6,
       SUM(CASE instance_number WHEN 7 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i7,
       SUM(CASE instance_number WHEN 7 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i7,
       SUM(CASE instance_number WHEN 8 THEN Avg_Latency_500B_msg ELSE 0 END) Avg_Latency_500B_msg_i8,
       SUM(CASE instance_number WHEN 8 THEN Avg_Latency_8K_msg ELSE 0 END) Avg_Latency_8K_msg_i8,
       MAX(t_Avg_Latency_500B_msg) i_Avg_Latency_500B_msg,
       MAX(t_Avg_Latency_8K_msg) i_Avg_Latency_8K_msg,
       MAX(c_Avg_Latency_500B_msg) c_Avg_Latency_500B_msg,
       MAX(c_Avg_Latency_8K_msg) c_Avg_Latency_8K_msg
  FROM source_and_target_extended
 WHERE target_instance = @instance_number@
 GROUP BY
       snap_id,
       end_time,
       target_instance
)
SELECT snap_id,
       TO_CHAR(end_time - (1/24), ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(end_time, ''YYYY-MM-DD HH24:MI'') end_time,
       c_Avg_Latency_@msg@_msg cluster_avg,
       i_Avg_Latency_@msg@_msg instance_avg,
       Avg_Latency_@msg@_msg_i1 inst_1,
       Avg_Latency_@msg@_msg_i2 inst_2,
       Avg_Latency_@msg@_msg_i3 inst_3,
       Avg_Latency_@msg@_msg_i4 inst_4,
       Avg_Latency_@msg@_msg_i5 inst_5,
       Avg_Latency_@msg@_msg_i6 inst_6,
       Avg_Latency_@msg@_msg_i7 inst_7,
       Avg_Latency_@msg@_msg_i8 inst_8,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM denorm_@denorm@
 ORDER BY       
       snap_id,
       end_time
';
END;
/

SET SERVEROUT ON;
SPO 99800_&&common_edb360_prefix._chart_setup_driver2.sql;
DECLARE
  l_count NUMBER;
BEGIN
  FOR i IN 1 .. 13
  LOOP
    SELECT COUNT(*) INTO l_count FROM gv$instance WHERE instance_number = i;
    IF l_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('COL inst_'||LPAD(i, 2, '0')||' NOPRI;');
      DBMS_OUTPUT.PUT_LINE('DEF tit_'||LPAD(i + 2, 2, '0')||' = '''';');
    ELSE
      DBMS_OUTPUT.PUT_LINE('COL inst_'||LPAD(i, 2, '0')||' HEA ''Inst '||i||''' FOR 999990.0 PRI;');
      DBMS_OUTPUT.PUT_LINE('DEF tit_'||LPAD(i + 2, 2, '0')||' = ''Inst '||i||''';');
    END IF;
  END LOOP;
END;
/
SPO OFF;
SET SERVEROUT OFF;
@99800_&&common_edb360_prefix._chart_setup_driver2.sql;
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. 99800_&&common_edb360_prefix._chart_setup_driver2.sql

DEF tit_01 = 'Cluster Avg';
DEF tit_02 = '';

DEF skip_lch = '';
DEF title = '8K msg pings from all Instances';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '-1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '8K msg pings sent to all Instances';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '-1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '500B msg pings from all Instances';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '-1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '500B msg pings sent to all Instances';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '-1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF tit_02 = 'Inst Avg';

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = '8K msg pings received from Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = '8K msg pings sent to Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = '500B msg pings received from Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = '500B msg pings sent to Instance 1';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = '8K msg pings received from Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = '8K msg pings sent to Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = '500B msg pings received from Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = '500B msg pings sent to Instance 2';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = '8K msg pings received from Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = '8K msg pings sent to Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = '500B msg pings received from Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = '500B msg pings sent to Instance 3';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = '8K msg pings received from Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = '8K msg pings sent to Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = '500B msg pings received from Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = '500B msg pings sent to Instance 4';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = '8K msg pings received from Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = '8K msg pings sent to Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = '500B msg pings received from Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = '500B msg pings sent to Instance 5';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = '8K msg pings received from Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = '8K msg pings sent to Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = '500B msg pings received from Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = '500B msg pings sent to Instance 6';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = '8K msg pings received from Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = '8K msg pings sent to Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = '500B msg pings received from Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = '500B msg pings sent to Instance 7';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql


DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = '8K msg pings received from Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = '8K msg pings sent to Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '8K');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = '500B msg pings received from Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'target');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = '500B msg pings sent to Instance 8';
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
EXEC :sql_text := REPLACE(:sql_text, '@msg@', '500B');
EXEC :sql_text := REPLACE(:sql_text, '@denorm@', 'source');
@@&&skip_all.&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = 'Y';

