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
SELECT * FROM dba_hist_wr_control &check_access_tab;

PRO Instance Info:
PRO ==============
SELECT * FROM (SELECT * FROM dba_hist_database_instance ORDER BY startup_time DESC) WHERE ROWNUM<=30;

PRO Snapshot Info:
PRO ==============
WITH r AS
 (SELECT r.*, ROWNUM seq,dense_rank() OVER(ORDER BY &con dbid) grp
  FROM   (SELECT &con
                 dbid,
                 (SELECT b.db_name &platform
                  FROM   dba_hist_database_instance b
                  WHERE  b.dbid = a.dbid
                  AND    b.startup_time = a.startup_time
                  AND    b.instance_number = a.instance_number
                  AND    ROWNUM < 2) dbname,
                 instance_number inst_id,
                 startup_time instance_startup,
                 min(begin_interval_time) + 0 st,
                 max(end_interval_time) + 0 et,
                 min(snap_id) begin_snap_id,
                 max(snap_id) end_snap_id,
                 round(avg(end_interval_time + 0 - (begin_interval_time + 0)) * 1440) interval_min
          FROM   dba_hist_snapshot a
          GROUP  BY &con dbid, instance_number, startup_time
          ORDER  BY &con dbid,st, instance_startup, et, inst_id) r),
chain AS
 (SELECT connect_by_root(seq) root_seq, seq, st, et
  FROM   r
  CONNECT BY grp=PRIOR grp
         AND seq=PRIOR seq+1
         AND st BETWEEN PRIOR st AND PRIOR et)
SELECT * 
FROM (
    SELECT &con dbid,
           dbname,
           &agg insts,
           min(instance_startup) instance_startup,
           min(st) begin_interval_time,
           max(et) end_interval_time,
           round((max(et) - min(st))*1440) duration,
           min(begin_snap_id) begin_snap_id,
           max(end_snap_id) end_snap_id,
           max(end_snap_id) - min(begin_snap_id) snapshots,
           min(interval_min) interval_min
    FROM   r NATURAL JOIN (SELECT DISTINCT seq,root_seq FROM chain WHERE root_seq NOT IN (SELECT seq FROM chain WHERE seq != root_seq)) c 
    GROUP  BY root_seq, &con dbid, dbname
    ORDER BY  end_interval_time DESC
) WHERE ROWNUM<=50;
