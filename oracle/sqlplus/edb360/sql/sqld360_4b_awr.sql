DEF chartype = 'LineChart';
DEF stacked = '';
DEF tit_01 = '&&sqld360_sqlid.';
DEF tit_02 = 'Total System Elapsed Time';
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

COL db_name FOR A9;
COL host_name FOR A64;
COL instance_name FOR A16;
COL db_unique_name FOR A30;
COL platform_name FOR A101;
COL version FOR A17;

COL sql_elapsed FOR 999999990.000;
COL system_elapsed FOR 999999990.000;

DEF main_table = 'DBA_HIST_SQLSTAT';
DEF vaxis = 'SQL Execute Elapsed Time';
DEF vbaseline = '';
BEGIN
  :sql_text_backup := '
SELECT MIN(a.snap_id) snap_id, 
       TO_CHAR(c.begin_interval_time, ''YYYY-MM-DD HH24:MI'')  begin_time, 
	   TO_CHAR(c.end_interval_time, ''YYYY-MM-DD HH24:MI'')  end_time,
	   SUM(NVL(b.sql_val,0))/1000000 sql_elapsed,
       SUM(a.system_val)/1000000 system_elapsed, 
       TRUNC((SUM(NVL(b.sql_val,0))/SUM(a.system_val))*100,3) sql_impact_percentage,
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
  FROM (SELECT snap_id, instance_number, value-LAG(value,1) OVER (PARTITION BY instance_number ORDER BY snap_id ) system_val 
          FROM dba_hist_sys_time_model 
         WHERE stat_name LIKE ''sql execute%'') a,
       (SELECT snap_id, instance_number, elapsed_time_delta sql_val
          FROM dba_hist_sqlstat
         WHERE sql_id = ''&&sqld360_sqlid.'') b,
       (SELECT snap_id, instance_number, begin_interval_time, end_interval_time
          FROM dba_hist_snapshot
	     WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.) c
 WHERE a.snap_id = b.snap_id(+)
   AND a.instance_number = b.instance_number(+)
   AND a.instance_number = @instance_number@
   AND a.snap_id = c.snap_id
   AND ''&&diagnostics_pack.'' = ''Y''
   AND a.instance_number = c.instance_number
   AND a.system_val > 0 -- skip the first snapshot where we can''t compute DELTA
                        -- and those where the value would be negative (restart in between)
 GROUP BY
       TO_CHAR(c.begin_interval_time, ''YYYY-MM-DD HH24:MI''), 
	   TO_CHAR(c.end_interval_time, ''YYYY-MM-DD HH24:MI'')
 ORDER BY
       TO_CHAR(c.end_interval_time, ''YYYY-MM-DD HH24:MI'')
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'SQL Execute Time for Cluster';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'a.instance_number');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'SQL Execute Time for Instance 1';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'SQL Execute Time for Instance 2';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'SQL Execute Time for Instance 3';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'SQL Execute Time for Instance 4';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'SQL Execute Time for Instance 5';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'SQL Execute Time for Instance 6';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'SQL Execute Time for Instance 7';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'SQL Execute Time for Instance 8';
DEF abstract = 'SQL Execute Time for SQL ID &&sqld360_sqlid. compared to the total System SQL Execute Time'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = 'Y';
DEF skip_pch = 'Y';

------------------------------------
------------------------------------

DEF chartype = 'LineChart';
DEF stacked = '';
DEF tit_01 = 'Elapsed Time';
DEF tit_02 = 'CPU Time';
DEF tit_03 = 'IO Wait Time';
DEF tit_04 = 'Cluster Wait Time';
DEF tit_05 = 'Application Wait Time';
DEF tit_06 = 'Concurrency Wait Time';
DEF tit_07 = '';
DEF tit_08 = '';
DEF tit_09 = '';
DEF tit_10 = '';
DEF tit_11 = '';
DEF tit_12 = '';
DEF tit_13 = '';
DEF tit_14 = '';
DEF tit_15 = '';

COL elapsed_time FOR 999999990.000;
COL cpu_time FOR 999999990.000;
COL io_time FOR 999999990.000;
COL cluster_time FOR 999999990.000;
COL application_time FOR 999999990.000;
COL concurrency_time FOR 999999990.000;


DEF main_table = 'DBA_HIST_SQLSTAT';
DEF vaxis = 'SQL Execute Elapsed Time';
DEF vbaseline = '';
BEGIN
  :sql_text_backup := '
SELECT MIN(a.snap_id) snap_id, 
       TO_CHAR(a.begin_interval_time, ''YYYY-MM-DD HH24:MI'')  begin_time, 
	   TO_CHAR(a.end_interval_time, ''YYYY-MM-DD HH24:MI'')  end_time,
	   SUM(NVL(b.elapsed_time_delta,0))/1000000 elapsed_time,
       SUM(NVL(b.cpu_time_delta,0))/1000000 cpu_time, 
       SUM(NVL(b.iowait_delta,0))/1000000 io_time,
       SUM(NVL(b.clwait_delta,0))/1000000 cluster_time,
       SUM(NVL(b.apwait_delta,0))/1000000 application_time,
       SUM(NVL(b.ccwait_delta,0))/1000000 concurrency_time,
       0 dummy_07,
       0 dummy_08,
       0 dummy_09,
       0 dummy_10,
       0 dummy_11,
       0 dummy_12,
       0 dummy_13,
       0 dummy_14,
       0 dummy_15
  FROM (SELECT snap_id, instance_number, 
	           elapsed_time_delta, cpu_time_delta, iowait_delta, clwait_delta, apwait_delta, ccwait_delta 
          FROM dba_hist_sqlstat
         WHERE sql_id = ''&&sqld360_sqlid.'') b,
       (SELECT snap_id, instance_number, begin_interval_time, end_interval_time
          FROM dba_hist_snapshot
	     WHERE snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.) a
 WHERE a.snap_id = b.snap_id(+)
   AND a.instance_number = b.instance_number(+)
   AND ''&&diagnostics_pack.'' = ''Y''
   AND a.instance_number = @instance_number@
 GROUP BY
       TO_CHAR(a.begin_interval_time, ''YYYY-MM-DD HH24:MI''), 
	   TO_CHAR(a.end_interval_time, ''YYYY-MM-DD HH24:MI'')
 ORDER BY
       TO_CHAR(a.end_interval_time, ''YYYY-MM-DD HH24:MI'')
';
END;
/

DEF skip_lch = '';
DEF skip_all = '&&is_single_instance.';
DEF title = 'SQL Execute Time by Wait Class for Cluster';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', 'a.instance_number');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 1;
DEF title = 'SQL Execute Time by Wait Class for Instance 1';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '1');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 2;
DEF title = 'SQL Execute Time by Wait Class for Instance 2';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '2');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 3;
DEF title = 'SQL Execute Time by Wait Class for Instance 3';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '3');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 4;
DEF title = 'SQL Execute Time by Wait Class for Instance 4';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '4');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 5;
DEF title = 'SQL Execute Time by Wait Class for Instance 5';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '5');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 6;
DEF title = 'SQL Execute Time by Wait Class for Instance 6';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '6');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 7;
DEF title = 'SQL Execute Time by Wait Class for Instance 7';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '7');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = '';
DEF skip_all = 'Y';
SELECT NULL skip_all FROM gv$instance WHERE instance_number = 8;
DEF title = 'SQL Execute Time by Wait Class for Instance 8';
DEF abstract = 'SQL Execute Time compared by Wait Class'
DEF foot = 'SQL Execute Elapsed Time'
EXEC :sql_text := REPLACE(:sql_text_backup, '@instance_number@', '8');
@@&&skip_all.&&skip_diagnostics.sqld360_9a_pre_one.sql

DEF skip_lch = 'Y';
DEF skip_pch = 'Y';
