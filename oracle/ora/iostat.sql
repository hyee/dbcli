/*[[Show IO Stats. Usage: @@NAME [<inst_id>] [-d [YYMMDDHH24MI] [YYMMDDHH24MI]]
   -d: Show data from dba_hist_* instead of v$* views
    --[[
    &V1: default={&instance}
    &V2: default={&starttime}
    &V3: default={&endtime}
    &iod: {
        default={select a.*,1 r,1 dbid from gv$iostat_function_detail A}
        d={
            SELECT A.*,decode(a.snap_id,s.max_snap_id,1,-1) r,s.inst_id
            FROM   snap s,dba_hist_iostat_detail A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id IN(s.min_snap_id,s.max_snap_id)
        }

    }
    &iof: {
        default={select DISTINCT FUNCTION_ID, FUNCTION_NAME FUNC,1 dbid from v$iostat_function A}
        d={
            SELECT DISTINCT FUNCTION_ID, FUNCTION_NAME FUNC,s.dbid
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
    &sysstat: {
        default={select 1 r,a.*,1 dbid from gv$sysstat a}
        d={
            SELECT A.*,decode(a.snap_id,s.max_snap_id,1,-1) r,s.inst_id,stat_name name
            FROM   snap s,dba_hist_sysstat A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id IN(s.min_snap_id,s.max_snap_id)
        }
    }
    &bs: {
        default={(select name,value,1 dbid from v$parameter)}
        d={
            SELECT s.dbid,max(value) value,parameter_name name
            FROM   snap s,dba_hist_parameter A
            WHERE  s.dbid=a.dbid
            AND    s.inst_id=a.instance_number
            AND    a.snap_id IN(s.min_snap_id,s.max_snap_id)
            AND    a.parameter_name='db_block_size'
            group  by parameter_name,s.dbid
        }
    }
    &snap: {
        default={WITH snap AS(
            SELECT /*+materialize*/ dbid, instance_number inst_id, MAX(snap_id) max_snap_id, NULLIF(MIN(snap_id), min_snap_id) min_snap_id
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

col reqs,total,timeouts,cnt for tmb
col avg_wait,wait_time for usmhd2
col waits,reads,<128K,Time%,fg,pct for pct
col bytes,avg_io for kmg2
col func break skip ~
col category break
grid {[[--grid:{topic='IO Stats - Function Detail'}
    &snap
    SELECT Nvl(FUNC,' ** TOTAL **') Func,
           regexp_replace(FILETYPE_NAME,' File$') file_type,
           SUM(reqs) reqs,
           nullif(round(SUM(r*number_of_waits) / SUM(reqs), 4),0) WAITS,
           nullif(round(SUM(r*small_read_reqs + r*large_read_reqs) / SUM(reqs), 4),0) reads,
           nullif(round(SUM(r*small_write_reqs + r*small_read_reqs) / SUM(reqs), 4),0) "<128K",
           nullif(SUM(mbs * 1024 * 1024),0) bytes,
           nullif(ROUND(SUM(mbs) * 1024 / SUM(reqs), 2),0) avg_kb,
           nullif(SUM(r*wait_time) * 1000,0) wait_time,
           nullif(round(SUM(r*wait_time) / NULLIF(SUM(r*number_of_waits), 0) * 1000, 2),0) avg_Wait,
           nullif(round(ratio_to_report(SUM(r*wait_time)) OVER(PARTITION BY GROUPING_ID(FUNC)), 4),0) "Time%"
    FROM   (SELECT A.*,
                   r*NULLIF(small_read_reqs + small_write_reqs + large_read_reqs + large_write_reqs, 0) REQS,
                   r*(small_read_megabytes + small_write_megabytes + large_read_megabytes + large_write_megabytes) mbs
            FROM   (SELECT *
                    FROM   (&iod) A --wrong FUNCTION_NAME
                    JOIN   (&iof) B
                    USING  (function_id,dbid)
                    WHERE  inst_id=NVL(0+:V1,inst_id)) A)
    GROUP  BY ROLLUP(FUNC), regexp_replace(FILETYPE_NAME,' File$')
    HAVING SUM(reqs)>0
    ORDER  BY 1, 2
]],'|',{[[--grid:{topic='Database I/O Events'}
    &snap
    SELECT nvl(event,'* '||wait_class||' *') event_or_class,
           SUM(r*total_waits) total,
           nullif(round(SUM(r*total_waits_fg) / SUM(r*total_waits), 4),0) fg,
           nullif(SUM(r*total_timeouts),0) timeouts,
           SUM(r*time_waited_micro) wait_time,
           round(SUM(r*time_waited_micro) / SUM(r*total_waits), 2) avg_wait,
           round(ratio_to_report(SUM(r*time_waited_micro)) OVER(PARTITION BY GROUPING_ID(EVENT)), 4) "Time%"
    FROM   (&env)
    WHERE  wait_class IN ('User I/O', 'System I/O')
    AND    inst_id=NVL(0+:V1,inst_id)
    GROUP  BY wait_class, ROLLUP(event)
    HAVING SUM(r*total_waits)>0
    ORDER  BY event NULLS FIRST
]],'-',[[--grid:{topic='System Stats'}
    &snap,
    stat AS(
        SELECT * 
        FROM  (
            SELECT TRIM(NAME) n, SUM(VALUE * r) v,
                   SUM(VALUE * r *(select value+0 from (&bs) b where b.name='db_block_size' and a.dbid=b.dbid)) bs
            FROM   (&sysstat) a
            WHERE  inst_id=NVL(0+:V1,inst_id)
            GROUP  BY TRIM(NAME)
            HAVING SUM(VALUE * r) > 0)
        MODEL RETURN UPDATED ROWS
        DIMENSION BY(n)
        MEASURES(cast(null as varchar2(30)) c,v,to_number(null) r,bs,to_number(null) p)
        RULES UPSERT ALL SEQUENTIAL ORDER(
            v['DB Physical Read']=v['physical read total bytes'],
            r['DB Physical Read']=v['physical read total IO requests'],
            v['DB Physical Read Opt']=v['physical read total bytes optimized'],
            r['DB Physical Read Opt']=v['physical read requests optimized'],
            v['DB Physical Write']=v['physical write total bytes'],
            r['DB Physical Write']=v['physical write total IO requests'],
            v['DB Physical Write Opt']=v['physical write total bytes optimized'],
            r['DB Physical Write Opt']=v['physical write requests optimized'],
            v['DB Physical IO']=SUM(v)[n in('DB Physical Read','DB Physical Write')],
            r['DB Physical IO']=SUM(r)[n in('DB Physical Read','DB Physical Write')],
            v['Saved by StorageIdx']=v['cell physical IO bytes saved by storage index'],
            v['Saved by Columnar']=v['cell physical IO bytes saved by columnar cache'],
            v['Phys IO - Flash']=nvl(v['DB Physical Read Opt'],0)+nvl(v['DB Physical Write Opt'],0)-nvl(v['Saved by StorageIdx'],0)-nvl(v['Saved by Columnar'],0),
            r['Phys IO - Flash']=nvl(r['DB Physical Read Opt'],0)+nvl(r['DB Physical Write Opt'],0),
            v['Phys IO - Flash+Disk']=nvl(v['DB Physical Read'],0)+nvl(v['DB Physical Write'],0)-nvl(v['Saved by StorageIdx'],0)-nvl(v['Saved by Columnar'],0),
            r['Phys IO - Flash+Disk']=nvl(r['DB Physical Read'],0)+nvl(r['DB Physical Write'],0),
            v['Spin Disk Read']=nvl(v['DB Physical Read'],0)-nvl(v['DB Physical Read Opt'],0),
            r['Spin Disk Read']=nvl(r['DB Physical Read'],0)-nvl(r['DB Physical Read Opt'],0),
            v['Spin Disk Write']=nvl(v['DB Physical Write']*3,0)-nvl(v['DB Physical Write Opt']*3,0),
            r['Spin Disk Write']=nvl(r['DB Physical Write']*3,0)-nvl(r['DB Physical Write Opt']*3,0),
            r['Flash/RAM/PMEM Read']=sum(v)[n in('cell flash cache read hits','cell ram cache read hits','cell pmem cache read hits')],
            r['Flash/RAM/PMEM Write']=sum(v)[n in('cell writes to flash cache','cell pmem cache writes')],
            v['Cell IO Uncompressed']=v['cell IO uncompressed bytes'],
            r['Cell IO Uncompressed']=v['HCC scan cell CUs decompressed'],
            v['HCC Read Decomp']=v['HCC scan rdbms bytes decompressed'],
            r['HCC Read Decomp']=v['HCC scan rdbms CUs decompressed'],
            v['HCC Read compressed']=v['HCC scan rdbms bytes compressed'],
            r['HCC Read compressed']=v['HCC scan cell CUs processed for compressed'],
            v['Pred Offloadable']=v['cell physical IO bytes eligible for predicate offload'],
            v['Interconnect']=v['cell physical IO interconnect bytes'],
            v['SmartScan Return']=v['cell physical IO interconnect bytes returned by smart scan'],
            v['SmartScan Passthru']=sum(v)[n in('cell physical IO bytes sent directly to DB node to balance CPU','cell num bytes in passthru due to quarantine','cell num bytes in passthru during predicate offload')],
            v['No Smart Scan']=sum(v)[n in('Interconnect','SmartScan Passthru')]-v['SmartScan Return'],
            v['Cache Layer']=bs['cell blocks processed by cache layer'],
            v['Data Layer']=bs['cell blocks processed by data layer'],
            v['Transaction Layer']=bs['cell blocks processed by txn layer'],
            v['Index Layer']=bs['cell blocks processed by index layer'],
            r['Cache Layer']=v['cell blocks processed by cache layer'],
            r['Data Layer']=v['cell blocks processed by data layer'],
            r['Transaction Layer']=v['cell blocks processed by txn layer'],
            r['Index Layer']=v['cell blocks processed by index layer'],
            r['Curr Block Cache']=v['db block gets from cache'],
            r['Curr Block Direct']=v['db block gets direct'],
            r['Cons Block Cache']=v['consistent gets from cache'],
            r['Cons Block Direct']=v['consistent gets direct'],
            r['Curr Block GC']=v['gc current blocks received'],
            r['Cons Block GC']=v['gc cr blocks received'],
            v['Curr Block Cache']=bs['db block gets from cache'],
            v['Curr Block Direct']=bs['db block gets direct'],
            v['Cons Block Cache']=bs['consistent gets from cache'],
            v['Cons Block Direct']=bs['consistent gets direct'],
            v['Curr Block GC']=bs['gc current blocks received'],
            v['Cons Block GC']=bs['gc cr blocks received'],
            v['Net to Client']=v['bytes sent via SQL*Net to client'],
            v['Net to DB-Link']=v['bytes sent via SQL*Net to dblink'],
            v['Net fr Client']=v['bytes received via SQL*Net from client'],
            v['Net fr DB-Link']=v['bytes received via SQL*Net from dblink'],
            r['Continued Rows']=sum(v)[n in('table fetch continued row','cell chained row pieces fetched')],
            r['Skipped Rows']=sum(v)[n in('chained rows skipped by cell','cell chained rows skipped')],
            r['Processed Rows']=sum(v)[n in('chained rows processed by cell','cell chained rows processed')],
            r['Rejected Rows']=sum(v)[n in('chained rows rejected by cell','cell chained rows rejected')],
            p[n in('DB Physical Read','DB Physical Write')]=r[cv()]/nullif(r['DB Physical IO'],0),
            p['DB Physical Read Opt']=r[cv()]/nullif(r['DB Physical Read'],0),
            p['Flash/RAM/PMEM Read']=r[cv()]/nullif(r['DB Physical Read'],0),
            p['Flash/RAM/PMEM Write']=r[cv()]/nullif(r['DB Physical Write']*3,0),
            p['DB Physical Write Opt']=r[cv()]/nullif(r['DB Physical Write'],0),
            p['Phys IO - Flash']=v[cv()]/nullif(v['DB Physical IO'],0),
            p['Phys IO - Flash+Disk']=v[cv()]/nullif(v['DB Physical IO'],0),
            p['No Smart Scan']=v[cv()]/nullif(v['Interconnect'],0),
            p['Pred Offloadable']=v[cv()]/nullif(v['DB Physical Read'],0),
            p[n in('SmartScan Return','Saved by StorageIdx','Saved by Columnar')]=v[cv()]/nullif(v['Pred Offloadable'],0),
            p[n in('Spin Disk Read','Spin Disk Write')]=2*r[cv()]/nullif(sum(r)[n in('Spin Disk Read','Spin Disk Write')],0),
            p[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')]=2*v[cv()]/nullif(sum(v)[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')],0),
            p[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')]=2*v[cv()]/nullif(sum(v)[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')],0),
            p[n in('Net to Client','Net to DB-Link','Net fr Client','Net fr DB-Link')]=2*v[cv()]/nullif(sum(v)[n in('Net to Client','Net to DB-Link','Net fr Client','Net fr DB-Link')],0),
            c[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')]='1 - DB Logical IO',
            c[n in('DB Physical IO','DB Physical Read','DB Physical Write')]='2 - DB Physical IO',
            c[n in('DB Physical Read Opt','DB Physical Write Opt','Saved by StorageIdx','Saved by Columnar','Flash/RAM/PMEM Read','Flash/RAM/PMEM Write','Phys IO - Flash','Phys IO - Flash+Disk')]='3 - Reduce IO',
            c[n in('Spin Disk Read','Spin Disk Write')]='4 - Real Disk IO',
            c[n in('Cell IO Uncompressed','HCC Read Decomp','HCC Read compressed')]='5 - Compress',
            c[n in('Interconnect','Pred Offloadable','SmartScan Return','SmartScan Passthru','No Smart Scan')]='6 - InterConnect',
            c[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')]='7 - Cell Process',
            c[n in('Net to Client','Net to DB-Link','Net fr Client','Net fr DB-Link')]='8 - SQL*Net IO',
            c[n in('Continued Rows','Skipped Rows','Processed Rows','Rejected Rows')]='9 - Chained Rows'
        ))
    SELECT c Category,n name,v bytes,r cnt,round(v/nullif(r,0),2) avg_io,round(p,4) pct
    FROM   stat
    WHERE  nvl(r,0)+nvl(v,0)>0
    order by c,n
]]}}