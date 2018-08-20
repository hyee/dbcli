/*[[ SQL performance over time: Usage: @@NAME <sql_id> [days]   
    --[[
    @BASE:11.2 ={}, 10.1={--}
    ]]--
   
]]*/

PROMPT
PROMPT
PROMPT &V1 performance over AWR for &V2 day[s]
PROMPT
PROMPT
SELECT s.instance_number inst_id,
       ss.snap_id,
       --  ss.sql_id,
       to_char(s.begin_interval_time, 'Dy DD-MON HH24:MI') snap_time,
       SS.PLAN_HASH_VALUE phv,
       ss.executions_delta execs,
       round((ss.elapsed_time_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) ETIME,
       round(ss.buffer_gets_delta / decode(ss.executions_delta, 0, 1, ss.executions_delta), 0) LIO,
       round(ss.disk_reads_delta / decode(ss.executions_delta, 0, 1, ss.executions_delta), 0) PIO,
       round(SS.FETCHES_DELTA / nullif(ss.executions_delta, 1), 0) Fetches_Ex,
       &BASE round((ss.IO_INTERCONNECT_BYTES_DELTA / 1024 / 1024) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 0) ICNT,
       round((ss.iowait_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) IOTIME,
       round((ss.ccwait_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) CCTIME,
       round((ss.clwait_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) CLTIME,
       round((ss.apwait_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) ATIME,
       round((ss.cpu_time_delta / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) CPUTIME,
       round((ss.PLSEXEC_TIME_DELTA / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) PLSQLTIME,
       round((ss.JAVEXEC_TIME_DELTA / 1000000) / decode(ss.executions_delta, 0, 1, ss.executions_delta), 6) JAVATIME
--   ,round(percent_rank() over (order by ceil(ss.elapsed_time_delta/ss.executions_delta))*100, 2) as percentile
FROM   dba_hist_snapshot s, dba_hist_sqlstat ss
WHERE  ss.dbid = s.dbid
AND    ss.instance_number = s.instance_number
AND    ss.snap_id = s.snap_id
AND    ss.sql_id = :V1
AND    ss.executions_delta > 0
AND    s.begin_interval_time >= SYSDATE - nvl(:V2, 15)
ORDER  BY s.snap_id;

SELECT inst_id,
       plan_hash_value || ' (' &BASE || nvl(sql_plan_baseline, NULL) || ' / ' || nvl(s.sql_profile, NULL) || ')' plan,
       -- 'SQL_'||lower(to_char(exact_matching_signature,'FMXXXXXXXXXXXXXXXX')) SQL_HANDLE,
       nullif(executions, 0) "Executions",
       ROUND(elapsed_time / (1e6 * nullif(executions, 0)), 3) "ela_per_exec (s)",
       round(buffer_gets / nullif(executions, 0), 0) gets_per_exec,
       --PARSE_CALLS,
       --S.LOADS,
       --S.INVALIDATIONS,
       S.version_count "Versions" /* Number of child cursors that have been marked to be kept using the DBMS_SHARED_POOL package*/,
       round(sharable_mem / 1024 / 1024, 2) "Sharable Mem (MB)",
       TO_CHAR(last_active_time, 'MM/DD/YYYY HH24:MI:SS') "last active time",
       S.LAST_LOAD_TIME,
       S.ADDRESS /*Address of the handle to the parent for this cursor*/,
       &BASE S.IS_BIND_SENSITIVE "Bind Sensitive" /* A query is considered bind-sensitive if the optimizer peeked at one of its bind variable values when computing predicate selectivities and where a change in a bind variable value may cause the optimizer to generate a different plan*/,
       &BASE S.IS_BIND_AWARE "Bind Aware" /* A query is considered bind-aware if it has been marked to use extended cursor sharing. The query would already have been marked as bind-sensitive. */,
       &BASE S.IS_OBSOLETE "Is Obsolete" /* Indicates whether the cursor has become obsolete (Y) or not (N). This can happen if the number of child cursors is too large. */,
       round(fetches / nullif(executions, 0), 2) F_to_E_Ratio,
       ROUND(CONCURRENCY_WAIT_TIME / 1000000 / nullif(executions, 0), 4) CONC_WT,
       ROUND(APPLICATION_WAIT_TIME / 1000000 / nullif(executions, 0), 2) APPL_WT,
       ROUND(CLUSTER_WAIT_TIME / 1000000 / nullif(executions, 0), 2) CLUSTER_WT,
       ROUND(USER_IO_WAIT_TIME / 1000000 / nullif(executions, 0), 2) UIO_WT,
       ROUND(cpu_time / 1000000 / nullif(executions, 0), 2) CPU_T,
       -- round(elapsed_time/1000000,2) ELA_T,
       &BASE          ROUND(PHYSICAL_READ_BYTES / 1024 / 1024 / nullif(executions, 0), 2) "PHYRD(M)",
       &BASE          ROUND(IO_INTERCONNECT_BYTES / 1024 / 1024 / nullif(executions, 0), 2) "IO_INTERCONNECT(M)",
       &BASE          ROUND(PHYSICAL_WRITE_BYTES / 1024 / 1024, 2) "PHYWR(M)",
       rows_processed
FROM   gv$sqlarea s
WHERE  sql_id = :V1
ORDER  BY 1;


WITH EMS AS
 (SELECT /*+ MATERIALIZE */
           exact_matching_signature
          FROM   gv$sql
          WHERE  sql_id = :V1
          AND    rownum < 2) &BASE
SELECT /*+ NO_MERGE */
         SQL_HANDLE      "NAME",
         PLAN_NAME,
         ENABLED,
         ACCEPTED,
         FIXED,
         &BASE           substr(CREATED, 1, 18) created,
         OPTIMIZER_COST,
         EXECUTIONS,
         ORIGIN,
         S.LAST_MODIFIED,
         S.LAST_VERIFIED &BASE
FROM   dba_sql_plan_baselines s, EMS &BASE
WHERE  sql_handle = 'SQL_' || lower(to_char(exact_matching_signature, 'FMXXXXXXXXXXXXXXXX')) &BASE
UNION ALL
SELECT /*+ NO_MERGE */
         NAME "NAME",
         'N/A' "PLAN_NAME",
         status "ENABLED",
         'N/A' "ACCEPTED",
         'N/A' "FIXED",
         to_char(created) created,
         NULL "OPTIMIZER_COST",
         NULL "EXECUTIONS",
         NULL "ORIGIN",
         last_modified,
         NULL "LAST_VERIFIED"
FROM   dba_sql_profiles a, EMS
WHERE  a.signature = ems.exact_matching_signature;








