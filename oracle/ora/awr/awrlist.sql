/*[[show summary of the AWR repository
  --[[
     @con: 12.2={con_id,} default={}
     @platform : 11.1={|| '(' || b.PLATFORM_NAME || ')'} default={}
     @agg: 11.1={trim(',' from regexp_replace(listagg(inst_id,',') within group(order by inst_id)||',','([^,]+,)\1+','\1'))} default={wmsys.wm_concat(distinct inst_id)}
     @check_access_tab: {
          dba_hist_table_settings={
            LEFT JOIN (
                select dbid,
                       max(decode(f,'ALL',c)) "Flush Lv|All", 
                       max(decode(f,'TYPICAL',c)) "Flush Lv|Typical", 
                       max(decode(f,'LITE',c)) "Flush Lv|Lite", 
                       max(decode(f,'BESTFIT',c)) "Flush Lv|BESTFIT",
                       max(decode(f,'NOT APPLICABLE',c)) "Flush Lv|N/A"
                from (select dbid,FLUSH_LEVEL_VAL f,count(1) c from dba_hist_table_settings group by dbid,FLUSH_LEVEL_VAL) 
                group by dbid)
            USING(DBID)
          }
          default={}
     }
  --]]
]]*/
SET FEED OFF
COL DURATION FOR ITV

PRO AWR Config:
PRO ===========
SELECT * FROM DBA_HIST_WR_CONTROL &check_access_tab;

PRO Instance Info:
PRO ==============
SELECT * FROM DBA_HIST_DATABASE_INSTANCE ORDER BY startup_time DESC;

PRO Snapshot Info:
PRO ==============
WITH r AS
 (SELECT r.*, ROWNUM seq,dense_rank() over(order by &con dbid) grp
  FROM   (SELECT &con
                 dbid,
                 (SELECT b.db_name &platform
                  FROM   DBA_HIST_DATABASE_INSTANCE b
                  WHERE  b.dbid = a.dbid
                  AND    b.startup_time = a.startup_time
                  AND    b.instance_number = a.instance_number
                  AND    rownum < 2) dbname,
                 instance_number inst_id,
                 startup_time INSTANCE_STARTUP,
                 MIN(begin_interval_time) + 0 st,
                 MAX(end_interval_time) + 0 et,
                 MIN(snap_id) begin_snap_id,
                 MAX(snap_id) end_snap_id,
                 round(AVG(end_interval_time + 0 - (begin_interval_time + 0)) * 1440) interval_min
          FROM   dba_hist_snapshot a
          GROUP  BY &con dbid, instance_number, startup_time
          ORDER  BY &con dbid,st, INSTANCE_STARTUP, et, inst_id) r),
chain AS
 (SELECT connect_by_root(seq) root_seq, seq, st, et
  FROM   r
  CONNECT BY grp=prior grp
         AND seq=prior seq+1
         AND st BETWEEN PRIOR st and PRIOR et)
SELECT &con dbid,
       dbname,
       &agg insts,
       MIN(INSTANCE_STARTUP) INSTANCE_STARTUP,
       MIN(st) begin_interval_time,
       MAX(et) end_interval_time,
       ROUND((MAX(et) - MIN(st))*1440) duration,
       MIN(begin_snap_id) begin_snap_id,
       MAX(end_snap_id) end_snap_id,
       MAX(end_snap_id) - MIN(begin_snap_id) snapshots,
       MIN(interval_min) interval_min
FROM   r natural join (SELECT distinct seq,root_seq FROM chain WHERE root_seq NOT IN (SELECT seq FROM chain WHERE seq != root_seq)) c 
GROUP  BY root_seq, &con dbid, dbname
ORDER BY  end_interval_time DESC;
