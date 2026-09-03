/*[[
    Show the AWR performance trend for a specific SQL. Usage: @@NAME <sql_id|plan_hash_value|signature> [-d|-p] [-avg] [-m]
    -d  : Group by day, otherwise group in detail
    -m  : Group by signature, otherwise group by sql id
    -p  : Group by plan_hash_value
    -phf: Group by plan_hash_full
    -avg: Show average stats

    --[[
        &BASE : s={sql_id}, m={signature}
        &TIM  : t={YYYYMMDD HH24:MI}, d={YYYYMMDD} p={" "}
        &avg  : default={1}, avg={nullif(SUM(nvl(nullif(exec,0),parse)),0)}
        &phf1 : {
                     default={null} 
                     phf={nvl(
                        (select extractvalue(dbms_xmlgen.getxmltype(q'~
                           select nullif(to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'0') phf
                           from  dba_hist_sql_plan b
                           where b.dbid=~'||a.dbid||'
                           and   b.plan_hash_value='||a.plan_hash||'
                           and   b.other_xml is not null
                           and   rownum<2'),'/ROWSET/ROW/PHF')+0 from dual),a.plan_hash)}
                }
        &phf2 : default={plan_hash} phf={max(plan_hash) keep(dense_rank last order by ela) top_plan}
        &phf3:  default={plan_hash} phf={plan_full}
        @ver  : 11.2={} default={--}
        @ARGS : 1
    --]]
]]*/

ORA _sqlstat
col ela,ELA(Avg),cost/io format usmhd2
col iowait,cpuwait,ccwait,clwait,apwait,plsql,Flash% for pct1
Col buff,read,avg_read,write,cellio,oflin,oflout format kmg
set autohide col
SELECT time,
       &BASE,
       plan_full,&phf2,
       sum(exec)   exec,
       sum(parse)  parse,
       sum(invalids) invalid,
       max(vers)  vers,
       count(1)    seens,
       sum(ela)    ela,
       round(sum(ela)/greatest(sum(exec),1),2) "ELA(Avg)",
       sum(iowait)/nullif(sum(ioreqs),0) "Cost/IO",
       nullif(sum(iowait)/sum(ela),0) iowait,
       nullif(sum(cpuwait)/sum(ela),0) cpuwait,
       nullif(sum(ccwait)/sum(ela),0) ccwait,
       nullif(sum(clwait)/sum(ela),0) clwait,
       nullif(sum(apwait)/sum(ela),0)  apwait,
       nullif(sum(plsql)/sum(ela),0)  plsql,
       nullif(round(sum(buff)/&avg,2),0) buff,
       nullif(round(sum(cellio)/&avg,2),0) cellio, 
       nullif(round(sum(oflin)/&avg,2),0) oflin, 
       nullif(round(sign(sum(oflin))*sum(oflout)/&avg,2),0) oflout,
       nullif(round(sum(read)/&avg,2),0) read,
       nullif(sum(optread)/nullif(sum(readreq),0),0) "Flash%",
       nullif(round(sum(write)/&avg,2),0)  write,
       nullif(round(sum(rows#)/&avg,2),0) rows#,
       nullif(round(sum(fetches)/&avg,2),0) fetches,
       nullif(max(px_count),0) px
FROM(
    SELECT /*+outline_leaf*/
           to_char(max(tim),'&TIM') time,
           &BASE,plan_hash, &phf1 plan_full,
           sum(exec)   exec,
           sum(parse)  parse,
           max(vers)  vers,
           count(1)    seens,
           sum(ela)    ela,
           sum(iowait) iowait,
           sum(ioreqs) ioreqs,
           sum(cpuwait) cpuwait,
           sum(ccwait) ccwait,
           sum(clwait) clwait,
           sum(apwait) apwait,
           max(px_count) px_count,
           sum(buff) buff,
           sum(read) read,
           sum(optread) optread,
           sum(readreq) readreq,
           sum(phyread) phyread,
           sum(write) write,
           sum(cellio) cellio,
           sum(oflin) oflin,
           sum(oflout) oflout,
           sum(rows#) rows#,
           sum(fetches) fetches,
           sum(plsql) plsql,
           sum(invalids) invalids
    FROM(
        SELECT a.end_interval_time tim,
               a.&BASE,
               dbid,
               a.plan_hash_value plan_hash,
               a.executions+CASE WHEN flag_=1 AND first_value(flag_) over(PARTITION BY dbid,instance_number,sql_id,plan_hash_value,instance_start ORDER BY snap_id RANGE BETWEEN 1 FOLLOWING AND 1 FOLLOWING) IS NULL then 1 else 0 end exec,
               a.version_count vers,
               a.parse_calls parse,
               nvl(min(decode(executions,0,NULL,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
                   max(decode(parse_calls,0,NULL,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap_id,
               round(a.elapsed_time,2) ela,
               a.iowait,
               round(a.cpu_time,2) cpuwait,
               round(a.ccwait,2) ccwait,
               round(a.clwait,2) clwait,
               round(a.apwait,2) apwait,
               a.ioreqs,
               a.px_servers_execs px_count,
               plsexec_time+javexec_time plsql,
               cellio,oflin,oflout,
               greatest(disk_reads,phyread) read,
               optread,
               nvl(phywrite,0)+nvl(direct_writes*512*1024,0) write,
               buffer_gets buff,
               a.rows_processed rows#,
               a.fetches,
               readreq,
               phyread,
               invalidations invalids
         FROM &awr$sqlstat  a --/* only capture sqls with the full set of execution stats */ BITAND (NVL(flag, 0), 1) = 0
        WHERE '&V1' IN(sql_id,''||plan_hash_value,''||signature)
          AND  end_interval_time BETWEEN nvl(to_date('&starttime','YYMMDDHH24MISS'),sysdate-90) AND nvl(to_date('&endtime','YYMMDDHH24MISS'),sysdate+1)
    ) a      
    --WHERE execs_>0 and delta_flag>0 OR execs_=0 AND delta_flag=0
    GROUP BY dbid,snap_id,&BASE,plan_hash
    HAVING sum(ela)>0)
 GROUP BY time,&BASE,plan_full,&phf3
 ORDER BY 1 DESC