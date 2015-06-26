DEF section_name = 'Performance';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;


DEF title = 'SQL Performance Summary';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       source, plan_hash_value, SUM(executions) execs, TRUNC(SUM(buffer_gets)/DECODE(SUM(executions),0,1,SUM(executions))) avg_buffer_gets, 
       TRUNC(SUM(elapsed_time)/1e6/DECODE(SUM(executions),0,1,SUM(executions)),3) avg_elapsed_time_secs, TRUNC(SUM(cpu_time)/1e6/DECODE(SUM(executions),0,1,SUM(executions)),3) avg_cpu_time_secs,
             MIN(first_load_time) first_load_time, MAX(last_load_time) last_load_time, MIN(optimizer_env_hash_value) min_cbo_env, max(optimizer_env_hash_value) max_cbo_env
  FROM (SELECT ''MEM'' source, plan_hash_value, executions, elapsed_time, cpu_time, buffer_gets, first_load_time, last_load_time, optimizer_env_hash_value
          FROM gv$sql
         WHERE sql_id = ''&&sqld360_sqlid.''
        UNION ALL
        SELECT ''HIST'' source, plan_hash_value, executions_delta executions, elapsed_time_delta elapsed_time, cpu_time_delta cpu_time, 
               buffer_gets_delta buffer_gets, null first_load_time, null last_load_time, optimizer_env_hash_value
          FROM dba_hist_sqlstat
         WHERE sql_id = ''&&sqld360_sqlid.''
           AND ''&&diagnostics_pack.'' = ''Y''
           AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.)
 GROUP BY source, plan_hash_value
';
END;
/
@@sqld360_9a_pre_one.sql



COL sql_text NOPRI
COL sql_fulltext NOPRI
COL optimizer_env NOPRI
COL bind_data NOPRI

DEF title = 'SQL Statistics from Memory';
DEF main_table = 'GV$SQL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sql
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, child_number
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI
COL sql_fulltext PRI
COL optimizer_env PRI
COL bind_data PRI



COL sql_text NOPRI
COL sql_fulltext NOPRI

DEF title = 'SQL Statistics from Memory (SQLSTATS)';
DEF main_table = 'GV$SQLSTATS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sqlstats
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI
COL sql_fulltext PRI



DEF title = 'SQL Plan Statistics from Memory';
DEF main_table = 'GV$SQL_PLAN_STATISTICS_ALL';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sql_plan_statistics_all
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, plan_hash_value, child_number, id
';
END;
/
@@sqld360_9a_pre_one.sql


COL sql_text NOPRI
COL sql_fulltext NOPRI

DEF title = 'SQL Plan Statistics from Memory (SQLSTATS)';
DEF main_table = 'GV$SQLSTATS_PLAN_HASH';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM gv$sqlstats_plan_hash
 WHERE sql_id = ''&&sqld360_sqlid.''
 ORDER BY inst_id, plan_hash_value
';
END;
/
@@sqld360_9a_pre_one.sql

COL sql_text PRI
COL sql_fulltext PRI


COL bind_data NOPRI

DEF title = 'SQL Statistics from History';
DEF main_table = 'DBA_HIST_SQLSTAT';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_hist_sqlstat
 WHERE sql_id = ''&&sqld360_sqlid.''
   AND ''&&diagnostics_pack.'' = ''Y''
   AND snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id. 
 ORDER BY snap_id desc, instance_number, plan_hash_value
';
END;
/
@@sqld360_9a_pre_one.sql

COL bind_data PRI



DEF title = 'SQL Plan Statistics from History';
DEF main_table = 'DBA_HIST_SQL_PLAN';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_hist_sql_plan
 WHERE sql_id = ''&&sqld360_sqlid.''
   AND ''&&diagnostics_pack.'' = ''Y''
 ORDER BY plan_hash_value, id
';
END;
/
@@sqld360_9a_pre_one.sql
