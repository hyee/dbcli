/*[[Show the AWR performance trend for a specific SQL. Usage: awrstat <sql_id>
    --[[
        &BASE : s={sql_id}, m={signature}
    --]]
]]*/

ORA _sqlstat
select max(tim) tim,sql_id,plan_hash,
       sum(exec)   exec,
       sum(parse)  parse,
       sum(ela)    "ELA(Mins)",
       round(sum(ela)/nullif(sum(exec),0),2) "ELA(Avg)",
       sum(iowait) iowait,
       sum(cpuwait) cpuwait,
       sum(ccwait) ccwait,
       sum(clwait) clwait,
       sum(apwait) apwait,
       max(px_count) px_count, 
       sum(bgs) "Buffer gets(MB)",
       sum(ior) "IO Reads(MB)",
       sum(wr)  "Writes(MB)",
       sum(rows#) rows#
from(       
    select to_char(a.end_interval_time,'YYYYMMDD HH24:MI') tim,
           a.sql_id,
           a.plan_hash_value plan_hash,
           a.executions EXEC,
           a.parse_calls parse,
           nvl(MIN(decode(executions,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
               MAX(decode(parse_calls,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap_id,
           round(a.elapsed_time/60,2) ela,
           ROUND(a.iowait/60,2) iowait,
           ROUND(a.cpu_time/60,2) cpuwait,
           ROUND(a.ccwait/60,2) ccwait,
           ROUND(a.clwait/60,2) clwait,
           ROUND(a.apwait/60,2) apwait,
           a.px_servers_execs px_count,
           round(buffer_gets,2) bgs,
           round(a.disk_reads,2) ior,
           round(a.direct_writes,2) wr,
           a.rows_processed rows#
     from &awr$sqlstat  a
    WHERE a.&BASE=:V1)
group by snap_id,sql_id,plan_hash order by 1 desc