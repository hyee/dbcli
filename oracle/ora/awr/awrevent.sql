/*[[
    Show AWR Top events for a specific period. Usage: @@NAME [0|a|<inst_id>|cpu|"<event>"|"<wait_class>"] {[yymmddhh24mi] [yymmddhh24mi]} [-avg] [-c]
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
         &avg: default={adj} avg={secs}
         &rd : default={0} avg={2}
         &unit: default={log(2,slot_time*2)} c={1}
         &V2   : default={&STARTTIME}
         &V3   : default={&ENDTIME}   
         @histogram: {11={,histogram as(
            SELECT *
            FROM   (SELECT  grouping_id(inst,wait_class,event) grp,
                            nvl(inst,'*') inst,
                            nvl(event, '- Wait Class: ' || nvl(wait_class, 'All')) event,'|' "|",
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
                            nullif(round(SUM(c * &unit)/nullif(sum(SUM(c * &unit)) OVER(PARTITION BY inst,wait_class,event),0) * 100, 2), 0) pct
                    FROM   (SELECT event_name event, 
                                    wait_class, 
                                    wait_time_milli*1024 slot_time, 
                                    (WAIT_COUNT-lag(WAIT_COUNT,1,0) OVER(PARTITION BY pkey,wait_time_milli,event_name ORDER BY etime))/secs c,
                                    CASE WHEN f=0 THEN ''||inst ELSE to_char(etime,'YYMMDD HH24:MI') END inst
                            FROM   time_model s
                            JOIN   dba_hist_event_histogram hs1
                            USING  (snap_id, instance_number, dbid)
                            WHERE  (f=0 and wait_class!='Idle' OR hs1.wait_class=w AND (f=2 OR event_name=e))
                            AND    wait_count>0
                            AND    f>=0
                            AND    dbid=:dbid)
                    WHERE  c!=0
                    GROUP  BY 
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
                            rollup(inst),
                            rollup(wait_class,event)
                    HAVING grouping_id(inst,wait_class,event) in(
                            decode(f,0,7,1,5,4),
                            decode(f,0,5,1,0,1),
                            decode(f,0,0,1,-1,5))) 
            PIVOT (MAX(nvl2(pct,lpad(to_char(pct,'fm990.00'),5)||'%','')) FOR unit IN('<1us' "<1us",
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

col "timeouts,% DB" for pct2
col waited,avg_wait for usmhd2
col r,grp noprint
set feed off verify off sep4k on COLAUTOSIZE trim

var c REFCURSOR "The percentage of the histogram is based on wait_count*&unit"

DECLARE
    v1 VARCHAR2(128):=:V1;
    e  VARCHAR2(300);
    w  VARCHAR2(300);
    f  PLS_INTEGER;
BEGIN
    IF upper(v1) IN('CPU','ON CPU') THEN
        f:=-1;
    ELSE
        SELECT NVL(MAX(CASE upper(v1) WHEN upper(wait_class) THEN 2 WHEN upper(event_name) THEN 1 END),0),
               NVL(MAX(CASE upper(v1) WHEN upper(event_name) THEN event_name END),V1),
               NVL(MAX(wait_class),'%')
        INTO   f,e,w
        FROM   DBA_HIST_EVENT_NAME
        WHERE  dbid=dbid
        AND    length(v1)>2
        AND    upper(v1) IN(upper(event_name),upper(wait_class))
        AND    rownum<2;
    END IF;

    OPEN :c FOR
        WITH snap AS(
            SELECT a.*,
                   MAX(snap_id) over(PARTITION BY pkey ORDER BY etime RANGE BETWEEN UNBOUNDED PRECEDING AND diff PRECEDING) min_snap,
                   round(86400*(etime-LAG(etime,1,stime) OVER(PARTITION BY pkey ORDER BY snap_id))) secs
            FROM   (SELECT /*+no_merge no_expand no_or_expand opt_param('optimizer_dynamic_sampling' 0)*/ 
                           snap_id,
                           dbid,
                           instance_number,
                           CASE WHEN V1 IN('0',''||instance_number) THEN ''||instance_number ELSE '*' END inst,
                           MAX(begin_interval_time+0) OVER(PARTITION BY snap_id) btime,
                           MAX(end_interval_time+0)   OVER(PARTITION BY snap_id) etime,
                           startup_time+0 stime,
                           (dbid+to_char(startup_time,'yymmddhh24mi'))*1e3+instance_number pkey,
                           (end_interval_time+0) - GREATEST(startup_time+0, MIN(end_interval_time+0) over(PARTITION BY instance_number,startup_time)) diff
                    FROM   dba_hist_snapshot
                    WHERE  dbid=:dbid
                     AND   end_interval_time+0 BETWEEN 
                           NVL(to_date(:V2,'yymmddhh24miss'),sysdate-7) AND 
                           NVL(to_date(:V3,'yymmddhh24miss'),sysdate+1)
                     AND  (V1 IS NULL OR f!=0 OR lower(V1) IN ('0', 'a') OR instance_number = regexp_substr(V1,'^\d+$' ))) a),
        time_model as(
             SELECT dbid,snap_id,pkey,instance_number,inst,secs,etime,adj,cpu_count,
                    (ela-lag(ela,1,0) over(partition by pkey order by etime)) ela,
                    (cpu-lag(cpu,1,0) over(partition by pkey order by etime)) cpu,
                    &avg div
             FROM (
                 SELECT s.*, p.value cpu_count
                 FROM   dba_hist_parameter p,(
                     SELECT DISTINCT
                            s.*,
                            decode(s.snap_id,s.min_snap,secs/86400/(etime-btime),1) adj,
                            sum(case when hs.stat_name     in('DB CPU','background cpu time') then hs.value end) over(partition by pkey,s.snap_id) cpu,
                            sum(case when hs.stat_name not in('DB CPU','background cpu time') then hs.value end) over(partition by pkey,s.snap_id) ela
                     FROM   snap s,dba_hist_sys_time_model hs
                     WHERE  s.snap_id=hs.snap_id
                     AND    s.instance_number=hs.instance_number
                     AND    s.dbid=hs.dbid
                     AND    hs.dbid=:dbid
                     AND    hs.stat_name in('DB time','background elapsed time','DB CPU','background cpu time')) s
                 WHERE  s.snap_id=p.snap_id(+)
                 AND    s.instance_number=p.instance_number(+)
                 AND    s.dbid=p.dbid(+)
                 AND    p.parameter_name(+)='cpu_count'
                 AND    p.dbid(+)=:dbid)),
        event as(
            SELECT grouping_id(inst,wait_class,event) grp,nvl(inst,'*') inst,
                   nvl(event,'- Wait Class: '||nvl(wait_class,'All')) event,
                   nvl2(event,wait_class,'') wait_class,
                   round(sum(waits/div),&rd) counts,
                   nullif(round(sum(timeouts/div)/nullif(sum(waits/div),0),4),0) timeouts,
                   round(sum(micro/div),&rd) waited,
                   round(sum(micro/div)/sum(distinct ela),4) db,
                   round(sum(micro/div)/sum(waits/div),2) avg_wait
            FROM (
                SELECT event_name event,wait_class,div,decode(f,0,''||inst,to_char(etime,'YYMMDD HH24:MI')) inst,
                       (total_Waits-lag(total_Waits,1,0) over(partition by pkey,event_name order by etime)) waits,
                       (total_timeouts-lag(total_timeouts,1,0) over(partition by pkey,event_name order by etime)) timeouts,
                       (time_waited_micro-lag(time_waited_micro,1,0) over(partition by pkey,event_name order by etime)) micro,
                       sum(distinct ela/div) over(partition by snap_id,inst) ela
                FROM   time_model 
                JOIN   dba_hist_system_event e USING(dbid,instance_number,snap_id)
                WHERE  (f=0 and wait_class!='Idle' OR e.wait_class=w AND (f=2 OR event_name=e))
                AND    f>=0
                AND    dbid=:dbid) a
            GROUP BY rollup(inst),rollup(wait_class,event)
            HAVING  grouping_id(inst,wait_class,event) in(
                        decode(f,0,7,1,5,4),
                        decode(f,0,5,1,0,1),
                        decode(f,0,0,1,-1,5)) 
                
            )
        &histogram
        SELECT null grp,
               decode(f,0,''||inst,to_char(etime,'YYMMDD HH24:MI')) inst, 
               '- * ON CPU *' event,null wait_class,sum(cpu_count*secs/div) counts,null timeouts,sum(cpu/div) waited,
               sum(cpu/div)/sum(ela/div) "% DB",
               round(sum(cpu/adj/cpu_count)/sum(secs/adj),6) avg_wait
               &ver1,'|' "|" ,null "<1us",null "<2us",null "<4us",null "<8us",null "<16us",null "<32us",null "<64us",null "<128us",null "<256us",null "<512us",null "<1ms",null "<2ms",null "<4ms",null "<8ms",null "<16ms",null "<32ms",null "<64ms",null "<128ms",null "<256ms",null "<512ms",null "<1s",null "<2s",null "<4s",null "<8s",null "<16s",null "<32s",null "<1m",null ">1m"
        FROM   time_model a
        WHERE  f<1
        GROUP  BY decode(f,0,''||inst,to_char(etime,'YYMMDD HH24:MI'))
        UNION ALL
        SELECT * FROM(
            select /*+use_hash(a b) outline_leaf*/ * from event a
            &ver1 left join histogram b using(grp,inst,event)
            ORDER BY bitand(grp,1) desc,nullif(inst,'*') desc nulls first,waited desc
        ) WHERE ROWNUM<decode(f,0,65,4086);
END;
/
print c
