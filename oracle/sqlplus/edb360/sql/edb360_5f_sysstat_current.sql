@@&&edb360_0g.tkprof.sql
DEF section_id = '5f';
DEF section_name = 'System Statistics (Current) per Hour';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF main_table = 'DBA_HIST_SYSSTAT';
DEF chartype = 'LineChart';
DEF vbaseline = ''; 
DEF stacked = '';

BEGIN
  :sql_text_backup := '
WITH
selected_stat_name AS (
SELECT /*+ &&sq_fact_hints. &&ds_hint. */
       h.snap_id,
       h.instance_number,
       s.begin_interval_time,
       s.startup_time,
       h.stat_id,
       h.stat_name,
       h.value,
       ROW_NUMBER () OVER (PARTITION BY h.dbid, h.instance_number, h.stat_id, TRUNC(s.begin_interval_time, ''HH'') ORDER BY h.snap_id) rn -- row_number within each hour
  FROM dba_hist_sysstat h,
       dba_hist_snapshot s
 WHERE h.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
   AND h.dbid = &&edb360_dbid.
   AND h.stat_name IN (''@stat_name_01@'', ''@stat_name_02@'', ''@stat_name_03@'', ''@stat_name_04@'', ''@stat_name_05@'', ''@stat_name_06@'', ''@stat_name_07@'', ''@stat_name_08@'', ''@stat_name_09@'', ''@stat_name_10@'', ''@stat_name_11@'', ''@stat_name_12@'', ''@stat_name_13@'', ''@stat_name_14@'', ''@stat_name_15@'')
   AND s.snap_id = h.snap_id
   AND s.dbid = h.dbid
   AND s.instance_number = h.instance_number
   AND s.end_interval_time - s.begin_interval_time > TO_DSINTERVAL(''+00 00:01:00.000000'') -- exclude snaps less than 1m appart
),
stat_name_per_instance_n_hour AS (
SELECT /*+ &&sq_fact_hints. */
       snap_id,
       instance_number,
       TRUNC(begin_interval_time, ''HH'') begin_time_hh,
       startup_time - LAG(startup_time) OVER (PARTITION BY /*dbid,*/ instance_number, stat_id ORDER BY snap_id) startup_time_interval,
       stat_name,
       value     
  FROM selected_stat_name
 WHERE rn = 1 -- select only first snap from each hour
),
stat_name_per_hour AS (
SELECT /*+ &&sq_fact_hints. */
       MIN(snap_id) snap_id,
       begin_time_hh,
       stat_name,
       SUM(value) value
  FROM stat_name_per_instance_n_hour
 WHERE startup_time_interval = TO_DSINTERVAL(''+00 00:00:00.000000'') -- include only snaps from same startup
   AND value >= 0 
 GROUP BY
       begin_time_hh,
       stat_name
)
SELECT /*+ &&top_level_hints. */
       snap_id,
       TO_CHAR(begin_time_hh, ''YYYY-MM-DD HH24:MI'') begin_time,
       TO_CHAR(begin_time_hh + (1/24), ''YYYY-MM-DD HH24:MI'') end_time,
       SUM(CASE stat_name WHEN ''@stat_name_01@'' THEN value ELSE 0 END) dummy_01,
       SUM(CASE stat_name WHEN ''@stat_name_02@'' THEN value ELSE 0 END) dummy_02,
       SUM(CASE stat_name WHEN ''@stat_name_03@'' THEN value ELSE 0 END) dummy_03,
       SUM(CASE stat_name WHEN ''@stat_name_04@'' THEN value ELSE 0 END) dummy_04,
       SUM(CASE stat_name WHEN ''@stat_name_05@'' THEN value ELSE 0 END) dummy_05,
       SUM(CASE stat_name WHEN ''@stat_name_06@'' THEN value ELSE 0 END) dummy_06,
       SUM(CASE stat_name WHEN ''@stat_name_07@'' THEN value ELSE 0 END) dummy_07,
       SUM(CASE stat_name WHEN ''@stat_name_08@'' THEN value ELSE 0 END) dummy_08,
       SUM(CASE stat_name WHEN ''@stat_name_09@'' THEN value ELSE 0 END) dummy_09,
       SUM(CASE stat_name WHEN ''@stat_name_10@'' THEN value ELSE 0 END) dummy_10,
       SUM(CASE stat_name WHEN ''@stat_name_11@'' THEN value ELSE 0 END) dummy_11,
       SUM(CASE stat_name WHEN ''@stat_name_12@'' THEN value ELSE 0 END) dummy_12,
       SUM(CASE stat_name WHEN ''@stat_name_13@'' THEN value ELSE 0 END) dummy_13,
       SUM(CASE stat_name WHEN ''@stat_name_14@'' THEN value ELSE 0 END) dummy_14,
       SUM(CASE stat_name WHEN ''@stat_name_15@'' THEN value ELSE 0 END) dummy_15
  FROM stat_name_per_hour
 GROUP BY
       snap_id,
       begin_time_hh
 ORDER BY
       snap_id,
       begin_time_hh
';
END;
/

DEF skip_lch = '';
DEF title = 'Sessions';
DEF vaxis = 'Sessions';
DEF tit_01 = 'logons current';
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
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name_01@', '&&tit_01.');
EXEC :sql_text := REPLACE(:sql_text, 'dummy_01', '"'||SUBSTR('&&tit_01.',1,30)||'"');
@@edb360_9a_pre_one.sql

DEF skip_lch = '';
DEF title = 'Cursors';
DEF vaxis = 'Cursors';
DEF tit_01 = 'opened cursors current';
DEF tit_02 = 'pinned cursors current';
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
EXEC :sql_text := REPLACE(:sql_text_backup, '@stat_name_01@', '&&tit_01.');
EXEC :sql_text := REPLACE(:sql_text, '@stat_name_02@', '&&tit_02.');
EXEC :sql_text := REPLACE(:sql_text, 'dummy_01', '"'||SUBSTR('&&tit_01.',1,30)||'"');
EXEC :sql_text := REPLACE(:sql_text, 'dummy_02', '"'||SUBSTR('&&tit_02.',1,30)||'"');
@@edb360_9a_pre_one.sql

DEF tit_01 = '';
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

DEF skip_lch = 'Y';

/*****************************************************************************************/
