@@&&edb360_0g.tkprof.sql
DEF section_id = '4g';
DEF section_name = 'I/O Waits Histogram for Top Wait Events';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

COL wait_class_01 NEW_V wait_class_01;
COL event_name_01 NEW_V event_name_01;
COL wait_class_02 NEW_V wait_class_02;
COL event_name_02 NEW_V event_name_02;
COL wait_class_03 NEW_V wait_class_03;
COL event_name_03 NEW_V event_name_03;
COL wait_class_04 NEW_V wait_class_04;
COL event_name_04 NEW_V event_name_04;
COL wait_class_05 NEW_V wait_class_05;
COL event_name_05 NEW_V event_name_05;
COL wait_class_06 NEW_V wait_class_06;
COL event_name_06 NEW_V event_name_06;
COL wait_class_07 NEW_V wait_class_07;
COL event_name_07 NEW_V event_name_07;
COL wait_class_08 NEW_V wait_class_08;
COL event_name_08 NEW_V event_name_08;
COL wait_class_09 NEW_V wait_class_09;
COL event_name_09 NEW_V event_name_09;
COL wait_class_10 NEW_V wait_class_10;
COL event_name_10 NEW_V event_name_10;
COL wait_class_11 NEW_V wait_class_11;
COL event_name_11 NEW_V event_name_11;
COL wait_class_12 NEW_V wait_class_12;
COL event_name_12 NEW_V event_name_12;

WITH
events AS (
SELECT /*+ &&sq_fact_hints. */
       h.wait_class,
       h.event_name,
       SUM(h.wait_time_milli * h.wait_count) time_waited
  FROM dba_hist_event_histogram h,
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.wait_class IN ('User I/O', 'System I/O')
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND s.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND s.dbid = &&edb360_dbid.
 GROUP BY
       h.wait_class,
       h.event_name
),
ranked AS (
SELECT wait_class, event_name,
       RANK () OVER (ORDER BY time_waited DESC) wrank
  FROM events
)
SELECT MIN(CASE wrank WHEN 01 THEN wait_class END) wait_class_01,
       MIN(CASE wrank WHEN 01 THEN event_name END) event_name_01,
       MIN(CASE wrank WHEN 02 THEN wait_class END) wait_class_02,
       MIN(CASE wrank WHEN 02 THEN event_name END) event_name_02,
       MIN(CASE wrank WHEN 03 THEN wait_class END) wait_class_03,
       MIN(CASE wrank WHEN 03 THEN event_name END) event_name_03,
       MIN(CASE wrank WHEN 04 THEN wait_class END) wait_class_04,
       MIN(CASE wrank WHEN 04 THEN event_name END) event_name_04,
       MIN(CASE wrank WHEN 05 THEN wait_class END) wait_class_05,
       MIN(CASE wrank WHEN 05 THEN event_name END) event_name_05,
       MIN(CASE wrank WHEN 06 THEN wait_class END) wait_class_06,
       MIN(CASE wrank WHEN 06 THEN event_name END) event_name_06,
       MIN(CASE wrank WHEN 07 THEN wait_class END) wait_class_07,
       MIN(CASE wrank WHEN 07 THEN event_name END) event_name_07,
       MIN(CASE wrank WHEN 08 THEN wait_class END) wait_class_08,
       MIN(CASE wrank WHEN 08 THEN event_name END) event_name_08,
       MIN(CASE wrank WHEN 09 THEN wait_class END) wait_class_09,
       MIN(CASE wrank WHEN 09 THEN event_name END) event_name_09,
       MIN(CASE wrank WHEN 10 THEN wait_class END) wait_class_10,
       MIN(CASE wrank WHEN 10 THEN event_name END) event_name_10,
       MIN(CASE wrank WHEN 11 THEN wait_class END) wait_class_11,
       MIN(CASE wrank WHEN 11 THEN event_name END) event_name_11,
       MIN(CASE wrank WHEN 12 THEN wait_class END) wait_class_12,
       MIN(CASE wrank WHEN 12 THEN event_name END) event_name_12
  FROM ranked
 WHERE wrank < 13;

COL recovery NEW_V recovery;
SELECT CHR(38)||' recovery' recovery FROM DUAL;
-- this above is to handle event "RMAN backup & recovery I/O"

DEF skip_lch = '';
DEF title = '&&wait_class_01. "&&event_name_01." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_01. "&&event_name_01." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_01. "&&event_name_01." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_01.'') AND event_name = TRIM(''&&event_name_01.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_02. "&&event_name_02." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_02. "&&event_name_02." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_02. "&&event_name_02." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_02.'') AND event_name = TRIM(''&&event_name_02.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_03. "&&event_name_03." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_03. "&&event_name_03." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_03. "&&event_name_03." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_03.'') AND event_name = TRIM(''&&event_name_03.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_04. "&&event_name_04." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_04. "&&event_name_04." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_04. "&&event_name_04." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_04.'') AND event_name = TRIM(''&&event_name_04.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_05. "&&event_name_05." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_05. "&&event_name_05." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_05. "&&event_name_05." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_05.'') AND event_name = TRIM(''&&event_name_05.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_06. "&&event_name_06." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_06. "&&event_name_06." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_06. "&&event_name_06." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_06.'') AND event_name = TRIM(''&&event_name_06.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_07. "&&event_name_07." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_07. "&&event_name_07." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_07. "&&event_name_07." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_07.'') AND event_name = TRIM(''&&event_name_07.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_08. "&&event_name_08." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_08. "&&event_name_08." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_08. "&&event_name_08." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_08.'') AND event_name = TRIM(''&&event_name_08.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_09. "&&event_name_09." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_09. "&&event_name_09." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_09. "&&event_name_09." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_09.'') AND event_name = TRIM(''&&event_name_09.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_10. "&&event_name_10." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_10. "&&event_name_10." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_10. "&&event_name_10." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_10.'') AND event_name = TRIM(''&&event_name_10.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_11. "&&event_name_11." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_11. "&&event_name_11." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_11. "&&event_name_11." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_11.'') AND event_name = TRIM(''&&event_name_11.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = '&&wait_class_12. "&&event_name_12." Waits - Histogram for Cluster';
DEF abstract = 'Percentage of &&wait_class_12. "&&event_name_12." Waits, taking less (or more) than N milliseconds.'
DEF vaxis = '&&wait_class_12. "&&event_name_12." Waits - Histogram as Percent of Waits (stacked)';
EXEC :sql_text := REPLACE(:sql_text_backup, '@filter_predicate@', 'wait_class = TRIM(''&&wait_class_12.'') AND event_name = TRIM(''&&event_name_12.'')');
@@&&skip_diagnostics.edb360_9a_pre_one.sql

/*****************************************************************************************/

DEF skip_lch = 'Y';
DEF skip_pch = 'Y';
   



