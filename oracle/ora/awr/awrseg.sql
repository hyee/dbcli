/*[[List AWR top segments. Usage: @@NAME [<keyword>|-f"<filter>"] [<sort_by>] [yymmddhhmi] [yymmddhhmi] [-avg]
    <keyword>: Used to fussily search over OWNER+OBJECT_NAME+SUBOBJECT_NAME+OBJ#+DATAOBJ#
    <sort_by>: Sort the records with specific order
    -avg     : Show average values per second instead of total
    --[[
        @11G : 11.2={} DEFAULT={--}
        @12c : 19.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        @phf : 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
        &AWR_VIEW        : default={AWR_PDB_} hist={dba_hist_}
        @check_access_pdb: pdb/awr_pdb_snapshot={&AWR_VIEW.} default={DBA_HIST_}
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
        &filter : default={UPPER('.'||owner||'.'||object_name||'.'||subobject_name||'.') LIKE upper('%&V1%')} f={}
        &flag   : default={nvl2(:V1,0,1)} f={0}
        &V2 : default={nvl(logi_reads,0)/30+nvl(phy_reads,0)+nvl(phy_writes,0)+nvl(cr_blocks,0)+nvl(cu_blocks,0)}
        &V3 : default={&starttime}
        &V4 : default={&endtime}
        &unit: default={1} avg={s}
        @opt_reads: 12.1={ROUND(SUM(OPTIMIZED_PHYSICAL_READS_DELTA)/NULLIF(SUM(PHYSICAL_READ_REQUESTS_DELTA),0),4)} default={to_number(null)}
        @imscans: 19.1={SUM(IM_SCANS_DELTA/&unit)} default={to_number(null)}
        @gc_grants: 19.1={SUM(GC_REMOTE_GRANTS_DELTA/&unit)} default={to_number(null)}
    ]]--
]]*/
COL "scans,imscans,logi_reads,busy_waits,phy_rreqs,phy_reads,phy_wreqs,phy_writes,value" FOR TMB
COL "blk_chgs,im_chgs,gc_busy,cr_blocks,cu_blocks,itl_waits,lock_waits,gc_grants,chain_rows" FOR TMB
COL "space,im_mem" FOR KMG
COL "opt_reads,dx_reads,dx_writes,Weight" FOR PCT2
SET AUTOHIDE COL FEED OFF

WITH segs AS(
    SELECT owner,object_name,
           decode(grouping_id(SUBOBJECT_NAME),0,SUBOBJECT_NAME,'* ('||COUNT(DISTINCT dataobj#)||' segs)') "Partition",
           nullif(SUM(TABLE_SCANS_DELTA/&unit),0) scans,
           nullif(&imscans,0) imscans,
           nullif(SUM(LOGICAL_READS_DELTA/&unit),0) logi_reads,
           nullif(SUM(BUFFER_BUSY_WAITS_DELTA/&unit),0) busy_waits,
           nullif(SUM(GC_BUFFER_BUSY_DELTA/&unit),0) gc_busy,
           nullif(SUM(PHYSICAL_READ_REQUESTS_DELTA/&unit),0) phy_rreqs,
           nullif(&opt_reads,0) opt_reads,
           nullif(SUM(PHYSICAL_READS_DELTA/&unit),0) phy_reads,
           nullif(ROUND(SUM(PHYSICAL_READS_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_READS_DELTA),0),4),0)  dx_reads,
           nullif(SUM(GC_CR_BLOCKS_RECEIVED_DELTA/&unit),0) cr_blocks,
           nullif(SUM(DB_BLOCK_CHANGES_DELTA/&unit),0) blk_chgs,
           &12c nullif(SUM(IM_DB_BLOCK_CHANGES_DELTA/&unit),0) im_chgs,
           nullif(SUM(PHYSICAL_WRITE_REQUESTS_DELTA/&unit),0) phy_wreqs,
           nullif(SUM(PHYSICAL_WRITES_DELTA/&unit),0) phy_writes,
           nullif(ROUND(SUM(PHYSICAL_WRITES_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_WRITES_DELTA),0),4),0) dx_writes,
           nullif(SUM(GC_CU_BLOCKS_RECEIVED_DELTA/&unit),0) cu_blocks,
           nullif(MAX(decode(r,1,SPACE_USED_TOTAL/&unit)),0) space,
           &12c nullif(SUM(IM_MEMBYTES/&unit),0) im_mem,
           nullif(SUM(ITL_WAITS_DELTA/&unit),0) itl_waits,
           nullif(SUM(ROW_LOCK_WAITS_DELTA/&unit),0) lock_waits,
           nullif(&gc_grants,0) gc_grants,
           nullif(SUM(CHAIN_ROW_EXCESS_DELTA/&unit),0) chain_rows
    from (select a.*, 
                 row_number() over(PARTITION BY dbid, obj#, dataobj# ORDER BY SPACE_USED_TOTAL DESC) r 
         from (
            select /*+DYNAMIC_SAMPLING(8)*/ *
            FROM &check_access_pdb.Seg_stat_obj b
            JOIN &check_access_pdb.Seg_stat c USING (dbid,obj#,dataobj#)
            JOIN (select dbid,snap_id,instance_number,
                         greatest(1,round(86400*((end_interval_time+0)-
                            case when begin_interval_time+0>= to_date(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')-3/1440
                                 then begin_interval_time+0 
                            end))) s
                  from &check_access_pdb.snapshot
                  where end_interval_time between to_timestamp(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
                  and   to_timestamp(coalesce('&V4', to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')) a
            USING(dbid,instance_number,snap_id)
            WHERE dbid=nvl(0+'&dbid',&did)
            AND   &filter
            ) a)
    GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
)
SELECT * FROM(
    SELECT Ratio_to_report(&v2) over()*2 "Weight",
           '|' "|",
           A.*
    FROM segs A
    ORDER BY &v2 desc nulls last)
WHERE ROWNUM<=50
AND   nvl("Partition",'x') not like '%(1 segs)%'
ORDER BY 1 DESC;

col Statistics break ~
var c refcursor "Top Segments by Statistics(threshold = 8%)"
BEGIN
    OPEN :c FOR 
        WITH segs AS(
            SELECT /*+MATERIALIZE*/ owner,object_name,
                   decode(grouping_id(SUBOBJECT_NAME),0,SUBOBJECT_NAME,''||COUNT(DISTINCT dataobj#)) segments,
                   nullif(SUM(TABLE_SCANS_DELTA/&unit),0) scans,
                   nullif(&imscans,0) imscans,
                   nullif(SUM(LOGICAL_READS_DELTA/&unit),0) logi_reads,
                   nullif(SUM(BUFFER_BUSY_WAITS_DELTA/&unit),0) busy_waits,
                   nullif(SUM(GC_BUFFER_BUSY_DELTA/&unit),0) gc_busy,
                   nullif(SUM(PHYSICAL_READ_REQUESTS_DELTA/&unit),0) phy_rreqs,
                   nullif(&opt_reads,0) opt_reads,
                   nullif(SUM(PHYSICAL_READS_DELTA/&unit),0) phy_reads,
                   nullif(ROUND(SUM(PHYSICAL_READS_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_READS_DELTA),0),4),0)  dx_reads,
                   nullif(SUM(GC_CR_BLOCKS_RECEIVED_DELTA/&unit),0) cr_blocks,
                   nullif(SUM(DB_BLOCK_CHANGES_DELTA/&unit),0) blk_chgs,
                   &12c nullif(SUM(IM_DB_BLOCK_CHANGES_DELTA/&unit),0) im_chgs,
                   nullif(SUM(PHYSICAL_WRITE_REQUESTS_DELTA/&unit),0) phy_wreqs,
                   nullif(SUM(PHYSICAL_WRITES_DELTA/&unit),0) phy_writes,
                   nullif(ROUND(SUM(PHYSICAL_WRITES_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_WRITES_DELTA),0),4),0) dx_writes,
                   nullif(SUM(GC_CU_BLOCKS_RECEIVED_DELTA/&unit),0) cu_blocks,
                   nullif(MAX(decode(r,1,SPACE_USED_TOTAL/&unit)),0) space,
                   &12c nullif(SUM(IM_MEMBYTES/&unit),0) im_mem,
                   nullif(SUM(ITL_WAITS_DELTA/&unit),0) itl_waits,
                   nullif(SUM(ROW_LOCK_WAITS_DELTA/&unit),0) lock_waits,
                   nullif(&gc_grants,0) gc_grants,
                   nullif(SUM(CHAIN_ROW_EXCESS_DELTA/&unit),0) chain_rows
            from (select a.*, 
                         row_number() over(PARTITION BY dbid, obj#, dataobj# ORDER BY SPACE_USED_TOTAL DESC) r 
                 from (
                    select /*+DYNAMIC_SAMPLING(8)*/ *
                    FROM &check_access_pdb.Seg_stat_obj b
                    JOIN &check_access_pdb.Seg_stat c USING (dbid,obj#,dataobj#)
                    JOIN (select dbid,snap_id,instance_number,
                                 greatest(1,round(86400*((end_interval_time+0)-
                                    case when begin_interval_time+0>= to_date(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')-3/1440
                                         then begin_interval_time+0 
                                    end))) s
                          from &check_access_pdb.snapshot
                          where end_interval_time between to_timestamp(coalesce('&V3', to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
                          and   to_timestamp(coalesce('&V4', to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')) a
                    USING(dbid,instance_number,snap_id)
                    WHERE dbid=nvl(0+'&dbid',&did)
                    AND   &filter
                    ) a)
            GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
            HAVING grouping_id(SUBOBJECT_NAME)=&flag)
        SELECT n "Statistics",v "Value",p "Weight", owner,object_name,segments
        FROM (
            SELECT a.*,round(ratio_to_report(v) over(PARTITION BY n),4) p
            FROM (
                SELECT r,
                       decode(r,
                              1, 'Logical Reads',
                              2, 'Physical Reads',
                              3, 'Physical Read Requests',
                              4, 'Direct Path Reads',
                              5, 'Physical Reads Un-Optimized',
                              6, 'Segment Scans',
                              7, 'Inmemory Scans',
                              8, 'DB Block Changes',
                              9, 'Physical Writes',
                              10, 'Physical Write Requests',
                              11, 'Direct Path Writes',
                              12, 'Buffer Busy Waits',
                              13, 'GC Buffer Busy Waits',
                              14, 'GC Remote Grants',
                              15, 'GC CR Blocks Received',
                              16, 'GC CU Blocks Received',
                              17, 'Row Lock Waits',
                              18, 'ITL Waits',
                              19, 'Chained Rows') n,
                        nullif(round(decode(a.r,
                                      1,logi_reads,
                                      2,phy_reads,
                                      3,phy_rreqs,
                                      4,dx_reads,
                                      5,phy_reads-nvl(opt_reads,0),
                                      6,scans,
                                      7,imscans,
                                      8,blk_chgs,
                                      9,phy_writes,
                                      10,phy_wreqs,
                                      11,dx_writes,
                                      12,busy_waits,
                                      13,gc_busy,
                                      14,gc_grants,
                                      15,cr_blocks,
                                      16,cu_blocks,
                                      17,lock_waits,
                                      18,itl_waits,
                                      19,chain_rows),2),0) v,
                        owner,object_name,segments
                FROM (select rownum r from dual connect by rownum<=19) a, segs) a
        WHERE v>0)
    WHERE p>=0.08
    ORDER BY R,p DESC;
END;
/