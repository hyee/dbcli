@@&&edb360_0g.tkprof.sql
DEF section_id = '4i';
DEF section_name = 'System Metric History';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_SYSMETRIC_HISTORY';
DEF chartype = 'LineChart';
DEF vbaseline = ''; 
DEF stacked = '';
DEF tit_01 = 'Max';
DEF tit_02 = '95th Percentile';
DEF tit_03 = '90th Percentile';
DEF tit_04 = '85th Percentile';
DEF tit_05 = '80th Percentile';
DEF tit_06 = '75th Percentile';
DEF tit_07 = 'Median';
DEF tit_08 = 'Avg';
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
per_instance_and_hour AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       MIN(snap_id) snap_id,
       instance_number,
       TRUNC(begin_time, ''HH'') begin_time,
       MAX(value) value_max,
       PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY value) value_95p,
       PERCENTILE_DISC(0.90) WITHIN GROUP (ORDER BY value) value_90p,
       PERCENTILE_DISC(0.85) WITHIN GROUP (ORDER BY value) value_85p,
       PERCENTILE_DISC(0.80) WITHIN GROUP (ORDER BY value) value_80p,
       PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY value) value_75p,
       MEDIAN(value) value_med,
       AVG(value) value_avg
  FROM dba_hist_sysmetric_history
 WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND dbid = &&edb360_dbid.
   AND group_id = 2 /* 1 minute intervals */
   AND metric_name = ''@metric_name@''
 GROUP BY
       instance_number,
       TRUNC(begin_time, ''HH'')
 ORDER BY
       instance_number,
       TRUNC(begin_time, ''HH'')
)
SELECT MIN(snap_id) snap_id,
       TO_CHAR(begin_time, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(begin_time + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       ROUND(SUM(value_max), 1) "Max",
       ROUND(SUM(value_95p), 1) "95th Percentile",
       ROUND(SUM(value_90p), 1) "90th Percentile",
       ROUND(SUM(value_85p), 1) "85th Percentile",
       ROUND(SUM(value_80p), 1) "80th Percentile",
       ROUND(SUM(value_75p), 1) "75th Percentile",
       ROUND(SUM(value_med), 1) "Median",
       ROUND(SUM(value_avg), 1) "Avg",
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM per_instance_and_hour
 GROUP BY
       begin_time
 ORDER BY
       begin_time
';
END;
/

DEF skip_lch = '';
DEF title = 'Average Active Sessions';
DEF vaxis = 'Active Sessions';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Average Synchronous Single-Block Read Latency';
DEF vaxis = 'Milliseconds';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'DB Block Changes Per Txn';
DEF vaxis = 'Blocks Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Enqueue Requests Per Txn';
DEF vaxis = 'Requests Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Executions Per Sec';
DEF vaxis = 'Executes Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'I/O Megabytes per Second';
DEF vaxis = 'Megabtyes per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'I/O Requests per Second';
DEF vaxis = 'Requests per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Logical Reads Per Txn';
DEF vaxis = 'Reads Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Logons Per Sec';
DEF vaxis = 'Logons Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Network Traffic Volume Per Sec';
DEF vaxis = 'Bytes Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Physical Reads Per Sec';
DEF vaxis = 'Reads Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Physical Reads Per Txn';
DEF vaxis = 'Reads Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Physical Writes Per Sec';
DEF vaxis = 'Writes Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Redo Generated Per Sec';
DEF vaxis = 'Bytes Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Redo Generated Per Txn';
DEF vaxis = 'Bytes Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Response Time Per Txn';
DEF vaxis = 'CentiSeconds Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'SQL Service Response Time';
DEF vaxis = 'CentiSeconds Per Call';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Total Parse Count Per Txn';
DEF vaxis = 'Parses Per Txn';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'User Calls Per Sec';
DEF vaxis = 'Calls Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'User Transaction Per Sec';
DEF vaxis = 'Transactions Per Second';
DEF abstract = '"&&title." with unit of "&&vaxis.", based on 1-minute appart samples. Max/Perc/Med/Avg refer to statistics within each hour.'
DEF foot = 'Max values represent the peak of the metric within each hour and among the 60 samples on it. Each sample represents in turn an average within a 1-minute interval.'
EXEC :sql_text := REPLACE(:sql_text_backup, '@metric_name@', '&&title.');
@@edb360_9a_pre_one.sql


DEF skip_lch = 'Y';

/*****************************************************************************************/
