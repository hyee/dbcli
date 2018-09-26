/*[[show summary of the AWR repository
  --[[
     @con: 12.2={con_id,} default={}
     @agg: 11.1={listagg(inst_id,',') within group(order by inst_id)} default={wmsys.wm_concat(inst_id)}
  --]]
]]*/
SET FEED OFF
COL DURATION FOR ITV

PRO AWR Config:
PRO ===========
SELECT * FROM DBA_HIST_WR_CONTROL;

PRO Instance Info:
PRO ==============
SELECT * FROM DBA_HIST_DATABASE_INSTANCE ORDER BY startup_time DESC;

PRO Snapshot Info:
PRO ==============
WITH r AS
 (SELECT &con dbid,
         (select b.db_name||'('||b.PLATFORM_NAME||')' from DBA_HIST_DATABASE_INSTANCE b where b.dbid=a.dbid and b.startup_time=a.startup_time and b.instance_number=a.instance_number and rownum<2 ) dbname,
         instance_number inst_id,
         startup_time INSTANCE_STARTUP,
         MIN(begin_interval_time) + 0 begin_interval_time,
         MAX(end_interval_time) + 0 end_interval_time,
         MIN(snap_id) begin_snap_id,
         MAX(snap_id) end_snap_id,
         COUNT(1) snaps,
         round(AVG(end_interval_time + 0 - (begin_interval_time + 0)) * 1440) interval_min
  FROM   dba_hist_snapshot a
  GROUP  BY &con dbid, instance_number, startup_time)
SELECT &con dbid,
       max(dbname) dbname,
       &agg insts,
       MIN(INSTANCE_STARTUP) INSTANCE_STARTUP,
       MIN(begin_interval_time) begin_interval_time,
       MAX(end_interval_time) end_interval_time,
       (MAX(end_interval_time) - MIN(begin_interval_time))*86400 duration,
       begin_snap_id,
       end_snap_id,
       MAX(snaps) snaps,
       MAX(interval_min) interval_min
FROM   r
GROUP  BY &con dbid, begin_snap_id, end_snap_id
ORDER  BY INSTANCE_STARTUP DESC;
