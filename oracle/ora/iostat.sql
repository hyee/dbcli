/*[[Show IO Stats. Usage: @@NAME [<inst_id>] [-d [YYMMDDHH24MI] [YYMMDDHH24MI]]
   -d: Show data from dba_hist_* instead of v$* views
    --[[
    &V1: default={&instance}
    &V2: default={&starttime}
    &V3: default={&endtime}
    &iod: {
        default={select a.*,1 r,1 snap_id from gv$iostat_function_detail A}
        d={
            SELECT A.*,decode(a.snap_id,s.max_snap_id,1,-1) r,s.inst_id
            FROM   snap s,dba_hist_iostat_detail A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id IN(s.min_snap_id,s.max_snap_id)
        }

    }
    &iof: {
        default={select DISTINCT FUNCTION_ID, FUNCTION_NAME FUNC from v$iostat_function A}
        d={
            SELECT DISTINCT FUNCTION_ID, FUNCTION_NAME FUNC 
            FROM   snap s,dba_hist_iostat_function A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id=s.max_snap_id
        }
    }
    &env: {
        default={select a.*,1 r,1 snap_id from gv$system_event A}
        d={
            SELECT A.*,decode(a.snap_id,s.max_snap_id,1,-1) r,s.inst_id,event_name event
            FROM   snap s,dba_hist_system_event A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id IN(s.min_snap_id,s.max_snap_id)    
        }
    }
    &snap: {
        default={}
        d={WITH snap AS(
            SELECT dbid, instance_number inst_id, MAX(snap_id) max_snap_id, NULLIF(MIN(snap_id), min_snap_id) min_snap_id
            FROM   (SELECT a.*,
                           CASE
                               WHEN MIN(begin_interval_time)
                                OVER(PARTITION BY dbid, instance_number, startup_time) <= startup_time - 5 / 1440 THEN
                                MIN(snap_id) OVER(PARTITION BY dbid, instance_number, startup_time)
                           END min_snap_id
                    FROM   DBA_HIST_SNAPSHOT a)
            WHERE  end_interval_time + 0 BETWEEN NVL(to_date(:V2, 'yymmddhh24miss'), SYSDATE - 7) - 1.2 / 24 AND
                   NVL(to_date(:V3, 'yymmddhh24miss'), SYSDATE + 1)
            GROUP BY dbid,instance_number,startup_time,min_snap_id)
        }
    }
    --]]
]]*/

col reqs,total,timeouts for tmb
col avg_wait,wait_time for usmhd2
col waits,reads,<128K,Time%,fg for pct
col bytes,avg_io for kmg2
col func break skip ~
grid {[[--grid:{topic='IO Stats Function Detail'}
    &snap
    SELECT Nvl(FUNC,' ** TOTAL **') Func,
           regexp_replace(FILETYPE_NAME,' File$') ftype,
           SUM(reqs) reqs,
           round(SUM(r*number_of_waits) / SUM(reqs), 4) WAITS,
           round(SUM(r*small_read_reqs + r*large_read_reqs) / SUM(reqs), 4) reads,
           round(SUM(r*small_write_reqs + r*small_read_reqs) / SUM(reqs), 4) "<128K",
           SUM(mbs * 1024) bytes,
           ROUND(SUM(mbs) * 1024 / SUM(reqs), 2) avg_io,
           SUM(r*wait_time) * 1000 wait_time,
           round(SUM(r*wait_time) / NULLIF(SUM(r*number_of_waits), 0) * 1000, 2) avg_Wait,
           round(ratio_to_report(SUM(r*wait_time)) OVER(PARTITION BY GROUPING_ID(FUNC)), 4) "Time%"
    FROM   (SELECT A.*,
                   r*NULLIF(small_read_reqs + small_write_reqs + large_read_reqs + large_write_reqs, 0) REQS,
                   r*(small_read_megabytes + small_write_megabytes + large_read_megabytes + large_write_megabytes) mbs
            FROM   (SELECT *
                    FROM   (&iod) A --wrong FUNCTION_NAME
                    JOIN   (&iof) B
                    USING  (function_id)
                    WHERE  inst_id=NVL(0+:V1,inst_id)) A)
    GROUP  BY ROLLUP(FUNC), regexp_replace(FILETYPE_NAME,' File$')
    HAVING SUM(reqs)>0
    ORDER  BY 1, 2
]],'|',[[--grid:{topic='Database I/O Event'}
    &snap
    SELECT nvl(event,'* '||wait_class||' *') event_or_class,
           SUM(r*total_waits) total,
           round(SUM(r*total_waits_fg) / SUM(r*total_waits), 4) fg,
           SUM(r*total_timeouts) timeouts,
           SUM(r*time_waited_micro) wait_time,
           round(SUM(r*time_waited_micro) / SUM(r*total_waits), 2) avg_wait,
           round(ratio_to_report(SUM(r*time_waited_micro)) OVER(PARTITION BY GROUPING_ID(EVENT)), 4) "Time%"
    FROM   (&env)
    WHERE  wait_class IN ('User I/O', 'System I/O')
    AND    inst_id=NVL(0+:V1,inst_id)
    GROUP  BY wait_class, ROLLUP(event)
    HAVING SUM(r*total_waits)>0
    ORDER  BY event NULLS FIRST
]]}