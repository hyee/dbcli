/*[[Show IO Stats. Usage: @@NAME [<inst_id>] [-d [YYMMDDHH24MI] [YYMMDDHH24MI]] [-avg]
   -d  : Show data from dba_hist_* instead of v$* views
   -avg: Show average per second instead of total

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
            FROM   snap s,dba_hist_iostat_function_name A
            WHERE  s.dbid=a.dbid
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
            SELECT /*+materialize*/ dbid, 
                    instance_number inst_id, 
                    round(86400*sum((end_interval_time+0)-case when begin_interval_time+0>=st-5/1440 then begin_interval_time+0 end)) secs,
                    MAX(snap_id) max_snap_id, 
                    nullif(min(snap_id),min_snap_id) min_snap_id
            FROM   (SELECT a.*,
                           NVL(to_date(:V2, 'yymmddhh24miss'), SYSDATE - 7) st,
                           NVL(to_date(:V3, 'yymmddhh24miss'), SYSDATE + 1) ed,
                           min(snap_id) over(partition by dbid,instance_number,startup_time) min_snap_id
                    FROM   DBA_HIST_SNAPSHOT a)
            WHERE  end_interval_time + 0 BETWEEN st - 5/1440 AND ed + 5/1440
            GROUP BY dbid,instance_number,min_snap_id)
        }
    }
    &dict: default={1} d={2}
    &unit: default={0} avg={&dict}
    --]]
]]*/
set verify off feed off
var c number;

DECLARE
    c INT := 1;
BEGIN
    IF &unit=1 THEN
        select round(sum(sysdate-startup_time)*86400)
        INTO c
        FROM gv$instance;
    ELSIF &unit=2 THEN
        &snap 
        select sum(secs) 
        into c
        from snap; 
    END IF;
    :c := c;
END;
/
col reqs,total,timeouts,cnt for tmb
col avg_wait,sync_wait for usmhd2
col syncs,reads,<128K,Time%,fg,pct for pct
col bytes,avg_io for kmg2
col func break skip ~
col category break
grid {[[--grid:{topic='IO Stats - Function Detail'}
    &snap
    SELECT decode(grouping_id(typ,filetype),0,typ,1,' ** All Files **',2,' ** All Types **',' **  Total  **') Func,
           nvl(filetype,typ) file_type,
           ROUND(SUM(reqs)/&c,2) reqs,
           nullif(round(SUM(r*number_of_waits) / SUM(reqs), 4),0) Syncs,
           nullif(round(SUM(r*small_read_reqs + r*large_read_reqs)/ SUM(reqs), 4),0) reads,
           nullif(round(SUM(r*small_write_reqs + r*small_read_reqs) / SUM(reqs), 4),0) "<128K",
           nullif(SUM(mbs * 1024 * 1024 /&c),0) bytes,
           nullif(ROUND(SUM(mbs) * 1024 * 1024 / SUM(reqs), 2),0) avg_io,
           nullif(SUM(r*wait_time) /&c * 1000,0) sync_wait,
           nullif(round(SUM(r*wait_time) / NULLIF(SUM(r*number_of_waits), 0) * 1000, 2),0) avg_Wait,
           nullif(round(ratio_to_report(SUM(r*wait_time)) OVER(PARTITION BY grouping_id(typ,filetype)), 4),0) "Time%"
    FROM   (SELECT A.*,
                   replace(FILETYPE_NAME,' File') filetype,
                   replace(FUNC,'Buffer Cache Reads','Buffer Reads') typ,
                   r*NULLIF(small_read_reqs + small_write_reqs + large_read_reqs + large_write_reqs, 0) REQS,
                   r*(small_read_megabytes + small_write_megabytes + large_read_megabytes + large_write_megabytes) mbs
            FROM   (SELECT *
                    FROM   (&iod) A --wrong FUNCTION_NAME
                    JOIN   (&iof) B
                    USING  (function_id,dbid)
                    WHERE  inst_id=NVL(0+:V1,inst_id)) A)
    GROUP  BY CUBE(typ,filetype)
    HAVING SUM(reqs)>0
    ORDER  BY 1, 3 desc
]],'|',{[[--grid:{topic='Top Database I/O Events',max_rows=17}
    &snap
    SELECT nvl(event,'* '||wait_class||' *') event_or_class,
           SUM(r*total_waits)/&c total,
           nullif(round(SUM(r*total_waits_fg) / SUM(r*total_waits), 4),0) fg,
           nullif(SUM(r*total_timeouts)/&c,0) timeouts,
           SUM(r*time_waited_micro)/&c wait_time,
           round(SUM(r*time_waited_micro) / SUM(r*total_waits), 2) avg_wait,
           round(ratio_to_report(SUM(r*time_waited_micro)) OVER(PARTITION BY GROUPING_ID(EVENT)), 4) "Time%"
    FROM   (&env)
    WHERE  wait_class IN ('User I/O', 'System I/O')
    AND    inst_id=NVL(0+:V1,inst_id)
    GROUP  BY wait_class, ROLLUP(event)
    HAVING SUM(r*total_waits)>0
    ORDER  BY grouping_id(event) desc, "Time%" desc
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
            r['Flash/RDMA/XRMEM Read']=sum(v)[n in('cell RDMA reads','cell flash cache read hits','cell pmem cache read hits','cell xrmem cache read hits')],
            r['Flash/RDMA/XRMEM Write']=sum(v)[n in('cell RDMA writes','cell writes to flash cache','cell pmem cache writes','cell xrmem cache writes')],
            v['Cell HCC Decomp']=v['HCC scan cell bytes decompressed'],
            r['Cell HCC Decomp']=v['HCC scan cell CUs decompressed'],
            v['DB HCC Read Decomp']=v['HCC scan rdbms bytes decompressed'],
            r['DB HCC Read Decomp']=v['HCC scan rdbms CUs decompressed'],
            v['DB HCC Read Compressed']=v['HCC scan rdbms bytes compressed'],
            r['DB HCC Read Compressed']=v['HCC scan cell CUs processed for compressed'],
            v['DB HCC Load Compressed']=sum(v)[n in('HCC load direct bytes compressed','HCC load conventional bytes compressed')],
            v['DB HCC Load Not-Comp']=sum(v)[n in('HCC load direct bytes uncompressed','HCC load conventional bytes uncompressed')],
            v['Pred Offloadable']=v['cell physical IO bytes eligible for predicate offload'],
            v['Interconnect']=v['cell physical IO interconnect bytes'],
            v['SmartScan Return']=v['cell physical IO interconnect bytes returned by smart scan'],
            v['SmartScan Passthru']=sum(v)[n ='cell physical IO bytes sent directly to DB node to balance CPU' or n like 'cell % bytes in passthru%'],
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
            v['Net fr/to Client']=sum(v)[n in('bytes sent via SQL*Net fr/to Client','bytes received via SQL*Net from client')],
            r['Net fr/to Client']=v['SQL*Net roundtrips to/from client'],
            v['Net fr/to DB-Link']=sum(v)[n in('bytes sent via SQL*Net to dblink','bytes received via SQL*Net from dblink')],
            r['Net fr/to DB-Link']=v['SQL*Net roundtrips to/from dblink'],
            r['Continued Rows']=sum(v)[n in('table fetch continued row','cell chained row pieces fetched')],
            r['Skipped Rows']=sum(v)[n in('chained rows skipped by cell','cell chained rows skipped')],
            r['Processed Rows']=sum(v)[n in('chained rows processed by cell','cell chained rows processed')],
            r['Rejected Rows']=sum(v)[n in('chained rows rejected by cell','cell chained rows rejected')],
            p[n in('DB Physical Read','DB Physical Write')]=r[cv()]/nullif(r['DB Physical IO'],0),
            p['DB Physical Read Opt']=r[cv()]/nullif(r['DB Physical Read'],0),
            p['DB Physical Write Opt']=r[cv()]/nullif(r['DB Physical Write'],0),
            p['Flash/RDMA/XRMEM Read']=r[cv()]/nullif(r['DB Physical Read'],0),
            p['Flash/RDMA/XRMEM Write']=r[cv()]/nullif(r['DB Physical Write']*3,0),
            p['Phys IO - Flash']=v[cv()]/nullif(v['DB Physical IO'],0),
            p['Phys IO - Flash+Disk']=v[cv()]/nullif(v['DB Physical IO'],0),
            p['No Smart Scan']=v[cv()]/nullif(v['Interconnect'],0),
            p['Pred Offloadable']=v[cv()]/nullif(v['DB Physical Read'],0),
            p[n in('SmartScan Return','SmartScan Passthru','Saved by StorageIdx','Saved by Columnar')]=v[cv()]/nullif(v['Pred Offloadable'],0),
            p[n in('Spin Disk Read','Spin Disk Write')]=2*r[cv()]/nullif(sum(r)[n in('Spin Disk Read','Spin Disk Write')],0),
            p[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')]=2*v[cv()]/nullif(sum(v)[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')],0),
            p[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')]=2*v[cv()]/nullif(sum(v)[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')],0),
            p[n in('Net fr/to Client','Net fr/to DB-Link')]=2*v[cv()]/nullif(sum(v)[n in('Net fr/to Client','Net fr/to DB-Link')],0),
            c[n in('Curr Block Cache','Curr Block Direct','Curr Block GC','Cons Block Cache','Cons Block Direct','Cons Block GC')]='1 - DB Logical IO',
            c[n in('DB Physical IO','DB Physical Read','DB Physical Write')]='2 - DB Physical IO',
            c[n in('DB Physical Read Opt','DB Physical Write Opt','Saved by StorageIdx','Saved by Columnar','Flash/RDMA/XRMEM Read','Flash/RDMA/XRMEM Write','Phys IO - Flash','Phys IO - Flash+Disk')]='3 - Reduce IO',
            c[n in('Spin Disk Read','Spin Disk Write')]='4 - Real Disk IO',
            c[n in('Cell HCC Decomp','DB HCC Read Decomp','DB HCC Read Compressed','DB HCC Load Compressed','DB HCC Load Not-Comp')]='5 - Compression',
            c[n in('Interconnect','Pred Offloadable','SmartScan Return','SmartScan Passthru','No Smart Scan')]='6 - InterConnect',
            c[n in('Cache Layer','Data Layer','Transaction Layer','Index Layer')]='7 - Cell Process',
            c[n in('Net fr/to Client','Net fr/to DB-Link')]='8 - SQL*Net IO',
            c[n in('Continued Rows','Skipped Rows','Processed Rows','Rejected Rows')]='9 - Chained Rows'
        ))
    SELECT c Category,n name,round(v/&c) bytes,round(r/&c) cnt,round(v/nullif(r,0),2) avg_io,round(p,4) pct
    FROM   stat
    WHERE  nvl(r,0)+nvl(v,0)>0
    order by c,n
]]}}