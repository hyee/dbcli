/*[[Show the AWR performance trend for a specific SQL. Usage: @@NAME <sql_id> [-d] [-m]
    -d: Group by day, otherwise group in detail
    -m: Group by signature, otherwise group by sql id
    --[[
        &BASE : s={sql_id}, m={signature}
        &TIM  : t={HH24:MI}, d={}
    --]]
]]*/

ORA _sqlstat
col ela,ELA(Avg),iowait,cpuwait,clwait,apwait format smhd2
Col "Buffer gets,IO Reads,IO Writes" format kmg

select time,sql_id,plan_hash,
       sum(exec)   exec,
       sum(parse)  parse,
       count(1)    SEENS,
       sum(ela)    ELA,
       round(sum(ela)/nullif(sum(exec),0),2) "ELA(Avg)",
       sum(iowait) iowait,
       sum(cpuwait) cpuwait,
       sum(ccwait) ccwait,
       sum(clwait) clwait,
       sum(apwait) apwait,
       max(px_count) px_count,
       sum(bgs) "Buffer gets",
       sum(ior) "IO Reads",
       sum(wr)  "IO Writes",
       sum(rows#) rows#
FROM(
    select /*+no_expand*/
           to_char(max(tim),'YYYYMMDD &TIM') time,sql_id,plan_hash,
           sum(exec)   exec,
           sum(parse)  parse,
           count(1)    SEENS,
           sum(ela)    ELA,
           sum(iowait) iowait,
           sum(cpuwait) cpuwait,
           sum(ccwait) ccwait,
           sum(clwait) clwait,
           sum(apwait) apwait,
           max(px_count) px_count,
           sum(bgs) bgs,
           sum(ior) ior,
           sum(wr)  wr,
           sum(rows#) rows#
    from(
        select a.end_interval_time tim,
               a.sql_id,
               a.plan_hash_value plan_hash,
               a.executions EXEC,
               a.parse_calls parse,
               nvl(MIN(decode(executions,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
                   MAX(decode(parse_calls,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap_id,
               round(a.elapsed_time,2) ela,
               ROUND(a.iowait,2) iowait,
               ROUND(a.cpu_time,2) cpuwait,
               ROUND(a.ccwait,2) ccwait,
               ROUND(a.clwait,2) clwait,
               ROUND(a.apwait,2) apwait,
               a.px_servers_execs px_count,
               round(buffer_gets,2) bgs,
               round(a.disk_reads,2) ior,
               round(a.direct_writes,2) wr,
               a.rows_processed rows#
         from &awr$sqlstat  a
        WHERE a.&BASE=:V1)
    group by snap_id,sql_id,plan_hash)
 group by time,sql_id,plan_hash
 order by 1 desc