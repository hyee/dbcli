/*[[
    Show AWR Top events for a specific period. Usage: @@NAME {[0|a|<inst_id>|event_name_key|wait_class] [yymmddhh24mi] [yymmddhh24mi] [-avg] [-c]}
    -avg: compute as per second, instead of total
    -c:   compute the percentage of histogram with wait_count, instead of wait_count*log(2,slot_time)
    
    Sample Output:
    ==============
    INST              EVENT                 WAIT_CLASS     COUNTS    TIMEOUTS WAITED  % DB   AVG_WAIT  <1us  <2us  <4us  <8us <16us <32us <64us <128us <256us <512us  <1ms  <2ms  <4ms
    ---- -------------------------------- -------------- ----------- -------- ------ ------- -------- ----- ----- ----- ----- ----- ----- ----- ------ ------ ------ ----- ----- -----
    A    - * ON CPU *                                            576           5.28d 129.43%   1.32ms                                                                                 
    A    - Wait Class: All                               913,805,670   72.70%  1.35d  33.20% 128.07us  0.08  0.47  5.41 32.26 20.34  8.26  4.78   5.93   6.70   6.90  4.50  3.08  0.35
    A    - Wait Class: Other                             888,573,719   74.76%  1.29d  31.68% 125.66us  0.05  0.41  5.60 33.53 20.99  8.32  4.63   5.90   6.12   5.36  4.57  3.20  0.36
    A    - Wait Class: System I/O                         12,399,340    0.00% 44.20m   0.75% 213.90us  0.08  1.14  0.16  1.65  7.30  8.84  2.18   0.18  28.81  47.31  1.87  0.05  0.18
    A    - Wait Class: User I/O                            4,267,451    0.01% 29.46m   0.50% 414.21us              0.09  0.69  2.00  1.55  0.60   1.25   7.65  79.68  5.40  0.28  0.31
    A    - Wait Class: Cluster                             1,735,296    0.00%  5.84m   0.10% 201.97us              0.01  0.01  0.03  0.05  2.90  25.24  46.91  21.19  3.30  0.26  0.06
    A    - Wait Class: Administrative                          2,263    0.00%  3.92m   0.07% 104.06ms              0.10  0.13        0.03  0.42   0.06          0.02                  
    A    - Wait Class: Network                             2,662,119    0.00%  2.79m   0.05%  62.95us  0.31     1  1.22  0.32  0.19 14.89 50.10  31.91   0.03   0.01                  
    A    - Wait Class: Concurrency                         4,019,062    0.74%  2.42m   0.04%  36.19us  8.91 15.40  5.48  3.69  5.88  7.55 27.13  15.33   1.27   3.92  5.03  0.27  0.02
    A    - Wait Class: Commit                                  7,093    0.00% 24.84s   0.01%   3.50ms                          0.05  0.27  0.99   2.96   5.32  13.21 15.50 10.22  9.61
    A    - Wait Class: Application                           134,310    0.21% 19.67s   0.01% 146.43us        0.02  8.27 18.09  0.96  1.72  8.82  42.64  12.63   5.01  1.66  0.02  0.03
    A    - Wait Class: Configuration                           5,017   85.11%  3.41s   0.00% 680.58us              0.03  0.60  0.05  0.27  0.23   2.00  33.28  42.32    16  0.15  0.11
    A    RMA: IPC0 completion sync        Other            2,604,551    0.00% 14.04h  14.34%  19.40ms                    0.25  0.64  0.10                0.01   0.01  0.03  0.07  0.02
    A    latch free                       Other           24,895,059    0.00%  7.57h   7.73%   1.09ms                                             0.05   1.95   4.78 37.65 50.15  5.37
    A    enq: PS - contention             Other           24,794,480   24.39%  2.48h   2.53% 359.47us                    0.01  0.01  0.04  0.25   3.61  28.98  46.11 20.92  0.04  0.01
    A    PX Deq: Join ACK                 Other           33,185,978    0.00%  1.41h   1.44% 152.95us  0.03  0.99  2.56  0.77  0.31  1.27 19.78  20.45  31.41  16.19  6.15  0.08      
    A    PX Deq: reap credit              Other          572,080,422  100.00%  1.29h   1.32%   8.11us        0.28  7.78 44.66 33.04 12.01  2.16   0.05                                
    A    PX Deq: Slave Session Stats      Other           24,132,318    0.00% 55.26m   0.94% 137.38us  0.30  3.59  4.61  3.79  1.90  1.92  5.30  15.36  39.97  21.12  1.86  0.23  0.01
    A    Sync ASM rebalance               Other              569,492    0.00% 35.29m   0.60%   3.72ms              0.04 15.35  5.03  3.25  1.03   2.14   2.49   9.93  2.65        9.34
    ...
    --[[
         &avg: default={1} avg={max(secs)}
         &unit: default={log(2,slot_time*2)} c={1}
         @ver: {11={,histogram as(
              SELECT *
              FROM   (SELECT inst,nvl(event, '- Wait Class: ' || nvl(wait_class, 'All')) event,'|' "|",
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
                            '>=1m' ">1m")))}, 
              default={}
         }
         @ver1: 11={} default={--}
    --]]
]]*/

col waited,fg_waited format smhd2
col "% DB" for pct2
col avg_wait for usmhd2
col fg_timeouts,timeouts for pct2
set feed off sep4k on COLAUTOSIZE trim
PRO The percentage of the histogram is based on wait_count*&unit
PRO ================================================================================
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
               AND    s.end_interval_time BETWEEN nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MI'),SYSDATE+1)
               ) a
      WHERE  snap_id IN (max_id, min_id)
      AND    max_id!=min_id
),
db_time as(select /*+materialize*/ inst,sum(value*flag) db_time from time_model where stat_name='DB time' group by inst)
&ver
SELECT /*+opt_param('optimizer_dynamic_sampling' 11)*/
       inst, '- * ON CPU *' event,null wait_class,max(cpu_count) counts,null timeouts,sum(value*flag)* 1e-6/&avg waited,
       sum(value*flag)/(select db_time from db_time b where b.inst=a.inst) "% DB",
       round(sum(value*flag)/max(secs)/max(cpu_count),6) avg_wait
       &ver1,'|' "|" ,null "<1us",null "<2us",null "<4us",null "<8us",null "<16us",null "<32us",null "<64us",null "<128us",null "<256us",null "<512us",null "<1ms",null "<2ms",null "<4ms",null "<8ms",null "<16ms",null "<32ms",null "<64ms",null "<128ms",null "<256ms",null "<512ms",null "<1s",null "<2s",null "<4s",null "<8s",null "<16s",null "<32s",null "<1m",null ">1m"
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