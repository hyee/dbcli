/*[[Show AWR Top events for a specific period. Usage: awrevent [0|a|<inst_id>] [yymmddhh24mi] [yymmddhh24mi]
    
]]*/

SELECT *
FROM   (SELECT  inst,event_name, wait_class, SUM(total_Waits * flag) counts,
                SUM(total_timeouts * flag) timeouts,
                round(SUM(time_waited_micro * 1e-6 / 60 * flag), 2) waited_mins,
                round(SUM(time_waited_micro * flag) / nullif(SUM(total_Waits * flag), 0) * 1e-3, 2) avg_milli,
                SUM(total_Waits_fg * flag) fg_counts, SUM(total_timeouts_fg * flag) fg_timeouts,
                round(SUM(time_waited_micro * 1e-6 / 60 * flag), 2) fg_waited_mins
         FROM   (SELECT DECODE(snap_id, min_id, -1, 1) flag, a.*
                  FROM   (SELECT  hs1.*, MIN(s.snap_id) OVER(PARTITION BY s.dbid) min_id,
                                  MAX(s.snap_id) OVER(PARTITION BY s.dbid) max_id,
                                  decode(nvl(LOWER(:V1),'a'),'a','A',to_char(s.instance_number)) inst
                           FROM   dba_hist_system_event hs1, dba_hist_snapshot s
                           WHERE  s.snap_id = hs1.snap_id
                           AND    s.instance_number = hs1.instance_number
                           AND    (nvl(LOWER(:V1),'a') in('0','a') or s.instance_number = :V1)
                           AND    s.dbid = hs1.dbid
                           AND    s.end_interval_time BETWEEN nvl(to_date(:V2,'YYMMDDHH24MI'),SYSDATE - 7) AND nvl(to_date(:V3,'YYMMDDHH24MI'),SYSDATE)
                           AND    wait_class != 'Idle') a
                  WHERE  snap_id IN (max_id, min_id))
         GROUP  BY inst,event_name, wait_class
         ORDER  BY waited_mins DESC)
WHERE  ROWNUM <= 50
