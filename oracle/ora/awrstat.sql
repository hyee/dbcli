select /*+no_expand*/ to_char(b.end_interval_time,'YYYYMMDD HH24:MI') tim,
       a.sql_id,
       a.plan_hash_value plan_hash,
       a.executions_delta EXEC,
       a.parse_calls_delta parse,
       round(a.elapsed_time_delta*1e-6/60,2) ela,
       ROUND(a.iowait_delta*1e-6/60,2) iowait,
       ROUND(a.cpu_time_delta*1e-6/60,2) cpuwait,
       ROUND(a.ccwait_delta*1e-6/60,2) ccwait,
       ROUND(a.clwait_delta*1e-6/60,2) clwait,
       a.px_servers_execs_delta px_count,
       round(buffer_gets_delta*8/1024,2) "Buffer gets(MB)",
       round((a.disk_reads_delta)*8/1024,2) "IO Reads(MB)",
       round((a.direct_writes_delta)*8/1024,2) "Writes(MB)",
       a.rows_processed_delta rows#
 from dba_hist_sqlstat a,dba_hist_snapshot b
WHERE a.snap_id=b.snap_id
AND   b.instance_number=a.instance_number
AND   a.dbid=b.dbid
AND   (a.executions_delta>0 or fetches_delta>0 or b.snap_id=(select max(snap_id) from dba_hist_snapshot))
AND   a.sql_id=:V1
ORDER BY 1 DESC