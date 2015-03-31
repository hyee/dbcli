@@&&edb360_0g.tkprof.sql
DEF section_id = '4j';
DEF section_name = 'System Metric Summary per Hour';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_SYSMETRIC_SUMMARY';
DEF chartype = 'LineChart';
DEF vbaseline = ''; 
DEF stacked = '';
DEF tit_01 = 'Max Value';
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

BEGIN
  :sql_text_backup := '
WITH
per_instance AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       snap_id,
       instance_number,
       TRUNC(begin_time, ''HH'') begin_time_hh,
       maxval,
       ROW_NUMBER () OVER (PARTITION BY dbid, instance_number, group_id, metric_id, TRUNC(begin_time, ''HH'') ORDER BY maxval DESC NULLS LAST, begin_time DESC) rn
  FROM dba_hist_sysmetric_summary
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND group_id = 2 /* 1 minute intervals */
   AND metric_name = ''@metric_name@''
)
SELECT /*+ &&top_level_hints. */
       MIN(snap_id) snap_id,
       TO_CHAR(begin_time_hh, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(begin_time_hh + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(SUM(maxval), 1) "Max Value",
       0 dummy_02,
       0 dummy_03,
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
  FROM per_instance
 WHERE rn = 1
 GROUP BY
       begin_time_hh
 ORDER BY
       begin_time_hh
';
END;
/

DEF skip_lch = '';
DEF title = 'Active Parallel Sessions';
DEF vaxis = 'Sessions';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Active Serial Sessions';
DEF vaxis = 'Sessions';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Branch Node Splits Per Sec';
DEF vaxis = 'Splits Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Cell Physical IO Interconnect Bytes';
DEF vaxis = 'bytes';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CR Blocks Created Per Sec';
DEF vaxis = 'Blocks Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'CR Undo Records Applied Per Sec';
DEF vaxis = 'Undo Records Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Current Logons Count';
DEF vaxis = 'Logons';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'DB Block Gets Per Sec';
DEF vaxis = 'Blocks Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'DB Block Gets Per Txn';
DEF vaxis = 'Blocks Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Disk Sort Per Sec';
DEF vaxis = 'Sorts Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Enqueue Deadlocks Per Sec';
DEF vaxis = 'Deadlocks Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Enqueue Deadlocks Per Txn';
DEF vaxis = 'Deadlocks Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Enqueue Waits Per Sec';
DEF vaxis = 'Waits Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Enqueue Waits Per Txn';
DEF vaxis = 'Waits Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Executions Per Sec';
DEF vaxis = 'Executes Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Executions Per Txn';
DEF vaxis = 'Executes Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Global Cache Average CR Get Time';
DEF vaxis = 'CentiSeconds Per Get';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Global Cache Average Current Get Time';
DEF vaxis = 'CentiSeconds Per Get';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Hard Parse Count Per Sec';
DEF vaxis = 'Parses Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'I/O Megabytes per Second';
DEF vaxis = 'Megabtyes per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'I/O Requests per Second';
DEF vaxis = 'Requests per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Leaf Node Splits Per Sec';
DEF vaxis = 'Splits Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Logical Reads Per Sec';
DEF vaxis = 'Reads Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Logical Reads Per Txn';
DEF vaxis = 'Reads Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Parse Failure Count Per Sec';
DEF vaxis = 'Parses Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX downgraded 1 to 25% Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX downgraded 25 to 50% Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX downgraded 50 to 75% Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX downgraded 75 to 99% Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX downgraded to serial Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'PX operations not downgraded Per Sec';
DEF vaxis = 'PX Operations Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Queries parallelized Per Sec';
DEF vaxis = 'Queries Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'User Commits Per Sec';
DEF vaxis = 'Commits Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute samples. Max value is within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql


DEF skip_lch = 'Y';

/*****************************************************************************************/
