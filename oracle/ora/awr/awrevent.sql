/*[[Show AWR Top events for a specific period. Usage: @@NAME {[0|a|<inst_id>|event_name_key|wait_class] [yymmddhh24mi] [yymmddhh24mi] [-avg] [-c]}
    -avg: compute as per second, instead of total
    -c:   compute the percentage of histogram with wait_count, instead of wait_count*log(2,slot_time)
    --[[
         &avg: default={1} avg={max(secs)}
         &unit: default={log(2,slot_time*2)} c={1}
         @ver: {
             11={,histogram as(
       SELECT *
       FROM   (SELECT inst,nvl(event, '- Wait Class: ' || nvl(wait_class, 'All')) event,
                     CASE
                     WHEN slot_time <= 512 THEN
                     '<' || slot_time || 'us'
                     WHEN slot_time <= 524288 THEN
                     '<' || round(slot_time / 1024) || 'ms'
                     WHEN slot_time <= 33554432 THEN
                     '<' || round(slot_time / 1024 / 1024) || 's'
                     WHEN slot_time <= 67108864 THEN
                     '<' || round(slot_time / 1024 / 1024 / 64) || 'm'
                     ELSE
                     '>=1m'
                     END unit,
                     nullif(round(SUM(c * flag * &unit)/nullif(sum(SUM(c * flag * &unit)) OVER(PARTITION BY inst,wait_class,event),0) * 100, 2), 0) pct
              FROM   (SELECT event_name event, wait_class, WAIT_TIME_MILLI * 1024 slot_time, WAIT_COUNT c, flag,inst
                     FROM   (SELECT DISTINCT snap_id, dbid, instance_number, inst, flag FROM time_model) s
                     JOIN   dba_hist_event_histogram hs1
                     USING  (snap_id, instance_number, dbid)
                     WHERE  wait_class != 'Idle')
              GROUP  BY inst,
                     CASE
                            WHEN slot_time <= 512 THEN
                            '<' || slot_time || 'us'
                            WHEN slot_time <= 524288 THEN
                            '<' || round(slot_time / 1024) || 'ms'
                            WHEN slot_time <= 33554432 THEN
                            '<' || round(slot_time / 1024 / 1024) || 's'
                            WHEN slot_time <= 67108864 THEN
                            '<' || round(slot_time / 1024 / 1024 / 64) || 'm'
                            ELSE
                            '>=1m'
                     END,
                     ROLLUP(wait_class,event))
       PIVOT (MAX(pct) FOR unit IN('<1us' "<1us",
                      '<2us' "<2us",
                      '<4us' "<4us",
                      '<8us' "<8us",
                      '<16us' "<16us",
                      '<32us' "<32us",
                      '<64us' "<64us",
                      '<128us' "<128us",
                      '<256us' "<256us",
                      '<512us' "<512us",
                      '<1ms' "<1ms",
                      '<2ms' "<2ms",
                      '<4ms' "<4ms",
                      '<8ms' "<8ms",
                      '<16ms' "<16ms",
                      '<32ms' "<32ms",
                      '<64ms' "<64ms",
                      '<128ms' "<128ms",
                      '<256ms' "<256ms",
                      '<512ms' "<512ms",
                      '<1s' "<1s",
                      '<2s' "<2s",
                      '<4s' "<4s",
                      '<8s' "<8s",
                      '<16s' "<16s",
                      '<32s' "<32s",
                      '<1m' "<1m",
                      '>=1m' ">1m"))       
)}, default={}

         }
         @ver1: 11={} default={--}
    --]]
]]*/

col waited,fg_waited format smhd2
col "% DB" for pct2
col avg_wait for usmhd2
col fg_timeouts,timeouts for pct2
set feed off sep4k on COLAUTOSIZE trim

with time_model as(
     SELECT DECODE(snap_id, max_id, 1, -1) flag, a.*,
            86400*((max(end_interval_time) over(partition by inst)+0)-(min(end_interval_time) over(partition by inst)+0)) secs
      FROM   (SELECT  hs1.*, s.end_interval_time,
                      s.STARTUP_TIME,
                      sum(p.value) over(partition by s.dbid,decode(LOWER(:V1),'0',to_char(s.instance_number),'A'),s.snap_id) cpu_count,
                      max(STARTUP_TIME) over(partition by s.dbid,s.instance_number) stime,
                      MIN(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) min_id,
                      MAX(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) max_id,
                      decode(LOWER(:V1),'0',to_char(s.instance_number),to_char(s.instance_number),to_char(s.instance_number),'A') inst
               FROM   dba_hist_sys_time_model hs1, dba_hist_snapshot s,dba_hist_parameter p
               WHERE  s.snap_id = hs1.snap_id
               AND    s.instance_number = hs1.instance_number
               AND    s.dbid=hs1.dbid
               AND    s.snap_id = p.snap_id(+)
               AND    s.instance_number = p.instance_number(+)
               AND    s.dbid=p.dbid(+)
               AND    p.parameter_name(+)='cpu_count'
               AND    hs1.stat_name in('DB time','DB CPU','background cpu time')
               AND    (nvl(LOWER(:V1),'a') in('0','a') 
                      or to_char(s.instance_number) = :V1
                      or not regexp_like(:V1,'^\d+$'))
               AND    s.dbid = hs1.dbid
               AND    s.end_interval_time BETWEEN nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MI'),SYSDATE)
               ) a
      WHERE  snap_id IN (max_id, min_id)
      AND    max_id!=min_id
),
db_time as(select /*+materialize*/ inst,sum(value*flag) db_time from time_model where stat_name='DB time' group by inst)
&ver
SELECT inst, '- * ON CPU *' event,null wait_class,max(cpu_count) counts,null timeouts,sum(value*flag)* 1e-6/&avg waited,
       sum(value*flag)/(select db_time from db_time b where b.inst=a.inst) "% DB",
       round(sum(value*flag)/max(secs)/max(cpu_count),6) avg_wait
       &ver1 ,null "<1us",null "<2us",null "<4us",null "<8us",null "<16us",null "<32us",null "<64us",null "<128us",null "<256us",null "<512us",null "<1ms",null "<2ms",null "<4ms",null "<8ms",null "<16ms",null "<32ms",null "<64ms",null "<128ms",null "<256ms",null "<512ms",null "<1s",null "<2s",null "<4s",null "<8s",null "<16s",null "<32s",null "<1m",null ">1m"
from   time_model a 
where stat_name!='DB time'
and   (regexp_like(:V1,'^\d+$') or nvl(LOWER(:V1),'a') in('0','a')) 
group  by inst
UNION  ALL
SELECT * FROM (
    SELECT * FROM (
        SELECT  inst,nvl(event_name,'- Wait Class: '||nvl(wait_class,'All')) event, 
                nvl2(event_name,wait_class,'') w_class,
                SUM(total_Waits * flag)/&avg counts,
                SUM(total_timeouts * flag)/nullif(SUM(total_Waits * flag),0) timeouts,
                round(SUM(time_waited_micro * 1e-6  * flag), 2)/&avg waited,
                sum(time_waited_micro * flag)/(select db_time from db_time b where b.inst=a.inst) db_time,
                round(SUM(time_waited_micro * flag) / nullif(SUM(total_Waits * flag), 0) , 2) avg_wait
        FROM   (SELECT  *
                FROM   (select distinct snap_id,max_id, min_id,secs,dbid,instance_number,inst,flag from time_model) s
                join   dba_hist_system_event hs1
                using  (snap_id,instance_number,dbid)
                WHERE  wait_class != 'Idle'
                AND    (nvl(LOWER(:V1),'a') in (lower(event_name),lower(wait_class),'a') or regexp_like(:V1,'^\d+$'))) a
        GROUP  BY inst,rollup(wait_class,event_name)
        HAVING SUM(time_waited_micro *flag)>0)
    &ver1 NATURAL JOIN histogram
    ORDER BY nvl2(w_class,2,1),waited desc
) WHERE ROWNUM <=64