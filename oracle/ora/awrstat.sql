select * from(
select /*+no_expand*/ to_char(b.end_interval_time,'YYYYMMDD HH24:MI') tim,
       a.sql_id,
       a.plan_hash_value plan_hash,
       a.executions_total EXEC,
       a.parse_calls_total parse,
       round(a.elapsed_time_total*1e-6/60,2) ela,
       ROUND(a.iowait_total*1e-6/60,2) iowait,
       ROUND(a.cpu_time_total*1e-6/60,2) cpuwait,
       ROUND(a.ccwait_total*1e-6/60,2) ccwait,
       ROUND(a.clwait_total*1e-6/60,2) clwait,
       a.px_servers_execs_total px_count,
       a.buffer_gets_total+a.disk_reads_total READS,
       a.direct_writes_total writes,
       a.rows_processed_total rows#
 from dba_hist_sqlstat a,dba_hist_snapshot b
WHERE a.snap_id=b.snap_id
AND   b.instance_number=a.instance_number
AND   a.dbid=b.dbid
AND   (a.executions_delta>0 or fetches_delta>0)
AND   a.sql_id=:V1
ORDER BY 1 DESC) where rownum<=50