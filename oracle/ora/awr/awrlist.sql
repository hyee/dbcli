/*[[show summary of the AWR repository
  --[[
     @con: 12.2={con_id,} default={}
  --]]
]]*/
SET FEED OFF

PRO AWR Config:
PRO ===========
SELECT * FROM DBA_HIST_WR_CONTROL;


PRO Snapshot Info:
PRO ==============
SELECT &con
       dbid,
       instance_number inst_id,
       startup_time INSTANCE_STARTUP,
       MIN(begin_interval_time)+0 begin_interval_time,
       MAX(end_interval_time)+0 end_interval_time,
       MIN(snap_id) begin_snap_id,
       MAX(snap_id) end_snap_id,
       COUNT(1) snaps,
       round(AVG(end_interval_time+0-(begin_interval_time+0))*1440) interval_min
FROM   dba_hist_snapshot
GROUP  BY &con dbid, instance_number, startup_time
ORDER  BY startup_time DESC,instance_number;

PRO Instance Info:
PRO ==============
SELECT * FROM DBA_HIST_DATABASE_INSTANCE ORDER BY startup_time DESC;