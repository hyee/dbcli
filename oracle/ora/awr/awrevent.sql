/*[[Show AWR Top events for a specific period. Usage: @@NAME {[0|a|<inst_id>|event_name_key|wait_class] [yymmddhh24mi] [yymmddhh24mi] [-avg]}
    -avg: compute as per second, instead of total
    --[[
    @FIELD :{
                11.0={,SUM(total_Waits_fg * flag)/&avg fg_counts, SUM(total_timeouts_fg * flag)/nullif(SUM(total_Waits_fg * flag),0) fg_timeouts,
                       round(SUM(time_waited_micro * 1e-6 * flag), 2)/&avg fg_waited},
                10.0={}
            }
    @FIELD1 :{
                11.0={,null fg_counts, null fg_timeouts,SUM(decode(stat_name,'DB CPU',value) * 1e-6* flag)/&avg fg_waited},
                10.0={}
            }
    &avg: default={1} avg={max(secs)}
    --]]
]]*/

col waited,fg_waited format smhd2
col "% DB" for pct2
col avg_wait for usmhd2
col fg_timeouts,timeouts for pct2
set feed off sep4k on

with time_model as(
     SELECT DECODE(snap_id, max_id, 1, -1) flag, a.*,
            86400*((max(end_interval_time) over(partition by inst)+0)-(min(end_interval_time) over(partition by inst)+0)) secs
      FROM   (SELECT  hs1.*, s.end_interval_time,
                      s.STARTUP_TIME,
                      sum(p.value) over(partition by s.dbid,decode(nvl(LOWER(:V1),'a'),'a','A',to_char(s.instance_number)),s.snap_id) cpu_count,
                      max(STARTUP_TIME) over(partition by s.dbid,s.instance_number) stime,
                      MIN(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) min_id,
                      MAX(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) max_id,
                      decode(nvl(LOWER(:V1),'a'),'a','A',to_char(s.instance_number)) inst
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

SELECT inst, '- * ON CPU *' event,null wait_class,max(cpu_count) counts,null timeouts,sum(value*flag)* 1e-6/&avg waited,
       sum(value*flag)/(select db_time from db_time b where b.inst=a.inst) "% DB",
       round(sum(value*flag)/max(secs)/max(cpu_count),6) avg_wait &FIELD1
from   time_model a 
where stat_name!='DB time'
and   (regexp_like(:V1,'^\d+$') or nvl(LOWER(:V1),'a') in('0','a')) 
group  by inst
UNION  ALL
SELECT *
FROM   (SELECT  inst,nvl(event_name,'- Wait Class: '||nvl(wait_class,'All')) event, 
                nvl2(event_name,wait_class,''),
                SUM(total_Waits * flag)/&avg counts,
                SUM(total_timeouts * flag)/nullif(SUM(total_Waits * flag),0) timeouts,
                round(SUM(time_waited_micro * 1e-6  * flag), 2)/&avg waited,
                sum(time_waited_micro * flag)/(select db_time from db_time b where b.inst=a.inst) db_time,
                round(SUM(time_waited_micro * flag) / nullif(SUM(total_Waits * flag), 0) , 2) avg_wait
                &FIELD
         FROM   (SELECT DECODE(snap_id, max_id, 1, -1) flag, a.*,
                        86400*((max(end_interval_time) over(partition by inst)+0)-(min(end_interval_time) over(partition by inst)+0)) secs
                  FROM   (SELECT  hs1.*, end_interval_time,
                                  s.STARTUP_TIME,
                                  max(STARTUP_TIME) over(partition by s.dbid,s.instance_number) stime,
                                  MIN(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) min_id,
                                  MAX(s.snap_id) OVER(PARTITION BY s.dbid,s.instance_number,s.STARTUP_TIME) max_id,
                                  decode(nvl(LOWER(:V1),'a'),'a','A',to_char(s.instance_number)) inst
                           FROM   dba_hist_system_event hs1, dba_hist_snapshot s
                           WHERE  s.snap_id = hs1.snap_id
                           AND    s.instance_number = hs1.instance_number
                           AND    s.dbid=hs1.dbid
                           AND    (nvl(LOWER(:V1),'a') in('0','a') 
                                  or to_char(s.instance_number) = :V1
                                  or instr(lower(event_name),lower(:V1))>0
                                  or instr(lower(wait_class),lower(:V1))>0)
                           AND    s.dbid = hs1.dbid
                           AND    s.end_interval_time BETWEEN nvl(to_date(nvl(:V2,:starttime),'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(nvl(:V3,:endtime),'YYMMDDHH24MI'),SYSDATE)
                           AND    wait_class != 'Idle') a
                  WHERE  snap_id IN (max_id, min_id)
                  AND    max_id!=min_id) a
         GROUP  BY inst,rollup(wait_class,event_name)
         HAVING SUM(time_waited_micro *flag)>0
         ORDER  BY grouping_id(wait_class,event_name) desc,abs(waited) DESC)
WHERE  ROWNUM <= 50
