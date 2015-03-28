@@&&edb360_0g.tkprof.sql
DEF section_id = '4f';
DEF section_name = 'I/O Waits';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'I/O Average Latency per Class';
DEF main_table = 'GV$WAITCLASSMETRIC';
BEGIN
  :sql_text := '
-- inspired on http://www.oraclerealworld.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
SELECT /*+ &&top_level_hints. */
       m.inst_id,
       c.wait_class,
       ROUND(10 * m.time_waited / m.wait_count, 3) avg_ms,
       m.wait_count,
       m.time_waited
  FROM gv$waitclassmetric m,
       gv$system_wait_class c
 WHERE m.wait_count > 0
   AND c.inst_id = m.inst_id
   AND c.wait_class# = m.wait_class#
   AND c.wait_class LIKE ''%I/O''
 ORDER BY
       1, 2
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'I/O Average Latency per Event';
DEF main_table = 'GV$EVENTMETRIC';
BEGIN
  :sql_text := '
-- inspired on http://www.oraclerealworld.com/wait-event-and-wait-class-metrics-vs-vsystem_event/
SELECT /*+ &&top_level_hints. */
       m.inst_id,
       e.wait_class,
       e.name event,
       ROUND(10 * m.time_waited / m.wait_count, 3) avg_ms,
       m.wait_count,
       m.time_waited
  FROM gv$eventmetric m,
       gv$event_name e
 WHERE m.wait_count > 0
   AND e.inst_id = m.inst_id
   AND e.event_id = m.event_id
   AND e.wait_class LIKE ''%I/O''
 ORDER BY
       1,2,3
';
END;
/
@@edb360_9a_pre_one.sql


SET SERVEROUT ON;
SPO 99870_&&common_edb360_prefix._chart_setup_driver4.sql;
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
      DBMS_OUTPUT.PUT_LINE('COL inst_'||LPAD(i, 2, '0')||' HEA ''Inst '||i||''' FOR 999999999999990 PRI;');
      DBMS_OUTPUT.PUT_LINE('DEF tit_'||LPAD(i, 2, '0')||' = ''Inst '||i||''';');
    END IF;
  END LOOP;
END;
/
SPO OFF;
SET SERVEROUT OFF;
@99870_&&common_edb360_prefix._chart_setup_driver4.sql;
HOS zip -mq &&edb360_main_filename._&&edb360_file_time. 99870_&&common_edb360_prefix._chart_setup_driver4.sql

DEF title = 'User plus System I/O Waits Counts per Instance';
DEF main_table = 'DBA_HIST_EVENT_HISTOGRAM';
DEF skip_lch = '';
DEF chartype = 'AreaChart';
DEF stacked = 'isStacked: true,';
DEF vaxis = 'User plus System I/O Waits Counts (stacked)';
DEF vbaseline = '';
BEGIN
  :sql_text := '
WITH 
event_histogram_denorm_1 AS ( -- event_histogram_inst_v1 begin
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       dbid,
       instance_number,
       event_id,
       event_name,
       wait_class_id,
       wait_class,
       SUM(wait_count) total
  FROM dba_hist_event_histogram
 WHERE wait_count > 0
   AND wait_class IN (''User I/O'', ''System I/O'')
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
 GROUP BY
       snap_id,
       dbid,
       instance_number,
       event_id,
       event_name,
       wait_class_id,
       wait_class
),
event_histogram_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       h1.snap_id,
       h1.instance_number,
       TO_CHAR(s1.begin_interval_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(s1.end_interval_time, ''YYYY-MM-DD HH24:MI'') end_time,
       (h1.total - h0.total) total
  FROM event_histogram_denorm_1 h0,
       event_histogram_denorm_1 h1,
       dba_hist_snapshot s0,
       dba_hist_snapshot s1
 WHERE h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND h1.event_id = h0.event_id
   AND h1.event_name = h0.event_name
   AND h1.wait_class_id = h0.wait_class_id
   AND h1.wait_class = h0.wait_class
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
   AND (h1.total - h0.total) > 0
)
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       MIN(begin_time) begin_time,
       MIN(end_time) end_time,
       SUM(CASE instance_number WHEN 1 THEN total ELSE 0 END) inst_01,
       SUM(CASE instance_number WHEN 2 THEN total ELSE 0 END) inst_02,
       SUM(CASE instance_number WHEN 3 THEN total ELSE 0 END) inst_03,
       SUM(CASE instance_number WHEN 4 THEN total ELSE 0 END) inst_04,
       SUM(CASE instance_number WHEN 5 THEN total ELSE 0 END) inst_05,
       SUM(CASE instance_number WHEN 6 THEN total ELSE 0 END) inst_06,
       SUM(CASE instance_number WHEN 7 THEN total ELSE 0 END) inst_07,
       SUM(CASE instance_number WHEN 8 THEN total ELSE 0 END) inst_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM event_histogram_denorm_2
 GROUP BY
       snap_id
 ORDER BY
       snap_id
';
END;
/
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF main_table = 'DBA_HIST_EVENT_HISTOGRAM';
COL less_1_perc FOR 999990.0;
COL less_2_perc FOR 999990.0;
COL less_4_perc FOR 999990.0;
COL less_8_perc FOR 999990.0;
COL less_16_perc FOR 999990.0;
COL less_32_perc FOR 999990.0;
COL less_64_perc FOR 999990.0;
COL less_128_perc FOR 999990.0;
COL less_256_perc FOR 999990.0;
COL less_512_perc FOR 999990.0;
COL less_1024_perc FOR 999990.0;
COL less_2048_perc FOR 999990.0;
COL less_4096_perc FOR 999990.0;
COL less_8192_perc FOR 999990.0;
COL more_8192_perc FOR 999990.0;
DEF tit_01 = '% < 1ms';
DEF tit_02 = '% < 2ms';
DEF tit_03 = '% < 4ms';
DEF tit_04 = '% < 8ms';
DEF tit_05 = '% < 16ms';
DEF tit_06 = '% < 32ms';
DEF tit_07 = '% < 64ms';
DEF tit_08 = '% < 128ms';
DEF tit_09 = '% < 256ms';
DEF tit_10 = '% < 512ms';
DEF tit_11 = '% < 1.024s';
DEF tit_12 = '% < 2.048s';
DEF tit_13 = '% < 4.096s';
DEF tit_14 = '% < 8.192s';
DEF tit_15 = '% > 8.192s';
BEGIN
  :sql_text_backup := '
WITH 
event_histogram_denorm_1 AS ( 
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       dbid,
       instance_number,
       event_id,
       event_name,
       wait_class_id,
       wait_class,
       SUM(wait_count) total,       
       SUM(CASE wait_time_milli WHEN POWER(2,00)   THEN wait_count ELSE 0 END) less_1_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,01)   THEN wait_count ELSE 0 END) less_2_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,02)   THEN wait_count ELSE 0 END) less_4_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,03)   THEN wait_count ELSE 0 END) less_8_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,04)   THEN wait_count ELSE 0 END) less_16_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,05)   THEN wait_count ELSE 0 END) less_32_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,06)   THEN wait_count ELSE 0 END) less_64_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,07)   THEN wait_count ELSE 0 END) less_128_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,08)   THEN wait_count ELSE 0 END) less_256_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,09)   THEN wait_count ELSE 0 END) less_512_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,10)   THEN wait_count ELSE 0 END) less_1024_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,11)   THEN wait_count ELSE 0 END) less_2048_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,12)   THEN wait_count ELSE 0 END) less_4096_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,13)   THEN wait_count ELSE 0 END) less_8192_ms,
       SUM(CASE WHEN wait_time_milli > POWER(2,13) THEN wait_count ELSE 0 END) more_8192_ms
       /*
       SUM(CASE wait_time_milli WHEN POWER(2,14)   THEN wait_count ELSE 0 END) less_16384_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,15)   THEN wait_count ELSE 0 END) less_32768_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,16)   THEN wait_count ELSE 0 END) less_65536_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,17)   THEN wait_count ELSE 0 END) less_131072_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,18)   THEN wait_count ELSE 0 END) less_262144_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,19)   THEN wait_count ELSE 0 END) less_524288_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,20)   THEN wait_count ELSE 0 END) less_1048576_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,21)   THEN wait_count ELSE 0 END) less_2097152_ms,
       SUM(CASE wait_time_milli WHEN POWER(2,22)   THEN wait_count ELSE 0 END) less_4194304_ms,
       SUM(CASE WHEN wait_time_milli > POWER(2,22) THEN wait_count ELSE 0 END) more_4194304_ms
       */
  FROM dba_hist_event_histogram
 WHERE wait_count > 0
   AND wait_class IN (''User I/O'', ''System I/O'')
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND @filter_predicate@
 GROUP BY
       snap_id,
       dbid,
       instance_number,
       event_id,
       event_name,
       wait_class_id,
       wait_class
),
event_histogram_denorm_2 AS (
SELECT /*+ &&sq_fact_hints. */
       h1.snap_id,
       TO_CHAR(s1.begin_interval_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(s1.end_interval_time, ''YYYY-MM-DD HH24:MI'') end_time,
       GREATEST((h1.total - h0.total), 0) total,
       GREATEST((h1.less_1_ms - h0.less_1_ms), 0) less_1_ms,
       GREATEST((h1.less_2_ms - h0.less_2_ms), 0) less_2_ms,
       GREATEST((h1.less_4_ms - h0.less_4_ms), 0) less_4_ms,
       GREATEST((h1.less_8_ms - h0.less_8_ms), 0) less_8_ms,
       GREATEST((h1.less_16_ms - h0.less_16_ms), 0) less_16_ms,
       GREATEST((h1.less_32_ms - h0.less_32_ms), 0) less_32_ms,
       GREATEST((h1.less_64_ms - h0.less_64_ms), 0) less_64_ms,
       GREATEST((h1.less_128_ms - h0.less_128_ms), 0) less_128_ms,
       GREATEST((h1.less_256_ms - h0.less_256_ms), 0) less_256_ms,
       GREATEST((h1.less_512_ms - h0.less_512_ms), 0) less_512_ms,
       GREATEST((h1.less_1024_ms - h0.less_1024_ms), 0) less_1024_ms,
       GREATEST((h1.less_2048_ms - h0.less_2048_ms), 0) less_2048_ms,
       GREATEST((h1.less_4096_ms - h0.less_4096_ms), 0) less_4096_ms,
       GREATEST((h1.less_8192_ms - h0.less_8192_ms), 0) less_8192_ms,
       GREATEST((h1.more_8192_ms - h0.more_8192_ms), 0) more_8192_ms
       /*
       GREATEST((h1.less_16384_ms - h0.less_16384_ms), 0) less_16384_ms,
       GREATEST((h1.less_32768_ms - h0.less_32768_ms), 0) less_32768_ms,
       GREATEST((h1.less_65536_ms - h0.less_65536_ms), 0) less_65536_ms,
       GREATEST((h1.less_131072_ms - h0.less_131072_ms), 0) less_131072_ms,
       GREATEST((h1.less_262144_ms - h0.less_262144_ms), 0) less_262144_ms,
       GREATEST((h1.less_524288_ms - h0.less_524288_ms), 0) less_524288_ms,
       GREATEST((h1.less_1048576_ms - h0.less_1048576_ms), 0) less_1048576_ms,
       GREATEST((h1.less_2097152_ms - h0.less_2097152_ms), 0) less_2097152_ms,
       GREATEST((h1.less_4194304_ms - h0.less_4194304_ms), 0) less_4194304_ms,
       GREATEST((h1.more_4194304_ms - h0.more_4194304_ms), 0) more_4194304_ms
       */
  FROM event_histogram_denorm_1 h0,
       event_histogram_denorm_1 h1,
       dba_hist_snapshot s0,
       dba_hist_snapshot s1
 WHERE h1.snap_id = h0.snap_id + 1
   AND h1.dbid = h0.dbid
   AND h1.instance_number = h0.instance_number
   AND h1.event_id = h0.event_id
   AND h1.event_name = h0.event_name
   AND h1.wait_class_id = h0.wait_class_id
   AND h1.wait_class = h0.wait_class
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
   AND (h1.total - h0.total) > 0
),
event_histogram_denorm_3 AS ( 
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       MIN(begin_time) begin_time,
       MIN(end_time) end_time,
       SUM(total)            total,
       SUM(less_1_ms)        less_1_ms,
       SUM(less_2_ms)        less_2_ms,
       SUM(less_4_ms)        less_4_ms,
       SUM(less_8_ms)        less_8_ms,
       SUM(less_16_ms)       less_16_ms,
       SUM(less_32_ms)       less_32_ms,
       SUM(less_64_ms)       less_64_ms,
       SUM(less_128_ms)      less_128_ms,
       SUM(less_256_ms)      less_256_ms,
       SUM(less_512_ms)      less_512_ms,
       SUM(less_1024_ms)     less_1024_ms,
       SUM(less_2048_ms)     less_2048_ms,
       SUM(less_4096_ms)     less_4096_ms,
       SUM(less_8192_ms)     less_8192_ms,
       SUM(more_8192_ms)     more_8192_ms
       /*
       SUM(less_16384_ms)    less_16384_ms,
       SUM(less_32768_ms)    less_32768_ms,
       SUM(less_65536_ms)    less_65536_ms,
       SUM(less_131072_ms)   less_131072_ms,
       SUM(less_262144_ms)   less_262144_ms,
       SUM(less_524288_ms)   less_524288_ms,
       SUM(less_1048576_ms)  less_1048576_ms,
       SUM(less_2097152_ms)  less_2097152_ms,
       SUM(less_4194304_ms)  less_4194304_ms,
       SUM(more_4194304_ms)  more_4194304_ms
       */
  FROM event_histogram_denorm_2
 GROUP BY
       snap_id
)
SELECT snap_id,
       begin_time,
       end_time,
       /*
       total,
       less_1_ms,
       less_2_ms,
       less_4_ms,
       less_8_ms,
       less_16_ms,
       less_32_ms,
       less_64_ms,
       less_128_ms,
       less_256_ms,
       less_512_ms,
       less_1024_ms,
       less_2048_ms,
       less_4096_ms,
       less_8192_ms,
       more_8192_ms,
       less_16384_ms,
       less_32768_ms,
       less_65536_ms,
       less_131072_ms,
       less_262144_ms,
       less_524288_ms,
       less_1048576_ms,
       less_2097152_ms,
       less_4194304_ms,
       more_4194304_ms,
       */
       ROUND(100 * less_1_ms / total, 1) less_1_perc,
       ROUND(100 * less_2_ms / total, 1) less_2_perc,
       ROUND(100 * less_4_ms / total, 1) less_4_perc,
       ROUND(100 * less_8_ms / total, 1) less_8_perc,
       ROUND(100 * less_16_ms / total, 1) less_16_perc,
       ROUND(100 * less_32_ms / total, 1) less_32_perc,
       ROUND(100 * less_64_ms / total, 1) less_64_perc,
       ROUND(100 * less_128_ms / total, 1) less_128_perc,
       ROUND(100 * less_256_ms / total, 1) less_256_perc,
       ROUND(100 * less_512_ms / total, 1) less_512_perc,
       ROUND(100 * less_1024_ms / total, 1) less_1024_perc,
       ROUND(100 * less_2048_ms / total, 1) less_2048_perc,
       ROUND(100 * less_4096_ms / total, 1) less_4096_perc,
       ROUND(100 * less_8192_ms / total, 1) less_8192_perc,
       ROUND(100 * more_8192_ms / total, 1) more_8192_perc
       /*
       ROUND(100 * less_16384_ms / total, 1) less_16384_perc,
       ROUND(100 * less_32768_ms / total, 1) less_32768_perc,
       ROUND(100 * less_65536_ms / total, 1) less_65536_perc,
       ROUND(100 * less_131072_ms / total, 1) less_131072_perc,
       ROUND(100 * less_262144_ms / total, 1) less_262144_perc,
       ROUND(100 * less_524288_ms / total, 1) less_524288_perc,
       ROUND(100 * less_1048576_ms / total, 1) less_1048576_perc,
       ROUND(100 * less_2097152_ms / total, 1) less_2097152_perc,
       ROUND(100 * less_4194304_ms / total, 1) less_4194304_perc,
       ROUND(100 * more_4194304_ms / total, 1) more_4194304_perc
       */
  FROM event_histogram_denorm_3
 ORDER BY
       snap_id
';
END;
/

DEF skip_lch = '';
DEF title = 'User plus System I/O Waits - Histogram for Cluster';
DEF abstract = 'Percentage of User + System I/O Waits, taking less (or more) than N milliseconds.'
DEF vaxis = 'User + System I/O Waits Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', '1 = 1');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

   



