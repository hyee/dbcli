/*[[List AWR top segments. Usage: @@NAME [<keyword>|-f"<filter>"] [<sort_by>] [yymmddhhmi] [yymmddhhmi] [-avg]
    <keyword>: Used to fussily search over OWNER+OBJECT_NAME+SUBOBJECT_NAME+OBJ#+DATAOBJ#
    <sort_by>: Sort the records with specific order
    -avg     : Show average values per second instead of total
    --[[
        @11G : 11.2={} DEFAULT={--}
        @12c : 19.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        @phf : 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
        @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
        &filter : default={UPPER('.'||owner||'.'||object_name||'.'||subobject_name||'.'||obj#) LIKE upper('%&V1%')} f={}
        &flag   : default={CASE WHEN :V1 IS NOT NULL THEN 0 ELSE 1 END} f={0}
        &V2 : default={nvl(logi_reads,0)/30+nvl(phy_reads,0)+nvl(phy_writes,0)+nvl(cr_blocks,0)+nvl(cu_blocks,0)}
        &V3 : default={&starttime}
        &V4 : default={&endtime}
        &unit: default={1} avg={s}
        @opt_reads: 12.1={ROUND(SUM(OPTIMIZED_PHYSICAL_READS_DELTA)/NULLIF(SUM(PHYSICAL_READ_REQUESTS_DELTA),0),4)} default={0}
        @imscans: 19.1={SUM(IM_SCANS_DELTA/&unit)} default={0}
        @im_chgs: 19.1={SUM(IM_DB_BLOCK_CHANGES_DELTA/&unit)} default={0}
        @gc_grants: 19.1={SUM(GC_REMOTE_GRANTS_DELTA/&unit)} default={0}
        @pop_cus: 19.1={SUM(POPULATE_CUS_DELTA/&unit)} default={0}
        @repop_cus: 19.1={SUM(REPOPULATE_CUS_TOTAL/&unit)} default={0}
    ]]--
]]*/
COL "scans,imscans,logi_reads,busy_waits,phy_rreqs,phy_reads,phy_wreqs,phy_writes,value" FOR TMB
COL "blk_chgs,im_chgs,gc_busy,cr_blocks,cu_blocks,itl_waits,lock_waits,gc_grants,chain_rows" FOR TMB
COL "space,im_mem" FOR KMG
COL "opt_reads,dx_reads,dx_writes,Weight" FOR PCT2
SET AUTOHIDE COL FEED OFF

WITH segs AS(
    SELECT owner,object_name,
           decode(grouping_id(subobject_name),0,subobject_name,'* ('||count(DISTINCT nvl(subobject_name,' '))||' segs)') "Partition",
           nullif(sum(table_scans_delta/&unit),0) scans,
           nullif(&imscans,0) imscans,
           nullif(sum(logical_reads_delta/&unit),0) logi_reads,
           nullif(sum(buffer_busy_waits_delta/&unit),0) busy_waits,
           nullif(sum(gc_buffer_busy_delta/&unit),0) gc_busy,
           nullif(sum(physical_read_requests_delta/&unit),0) phy_rreqs,
           nullif(&opt_reads,0) opt_reads,
           nullif(sum(physical_reads_delta/&unit),0) phy_reads,
           nullif(round(sum(physical_reads_direct_delta)/nullif(sum(physical_reads_delta),0),4),0)  dx_reads,
           nullif(sum(gc_cr_blocks_received_delta/&unit),0) cr_blocks,
           nullif(sum(db_block_changes_delta/&unit),0) blk_chgs,
           nullif(&im_chgs,0) im_chgs,
           nullif(sum(physical_write_requests_delta/&unit),0) phy_wreqs,
           nullif(sum(physical_writes_delta/&unit),0) phy_writes,
           nullif(round(sum(physical_writes_direct_delta)/nullif(sum(physical_writes_delta),0),4),0) dx_writes,
           nullif(sum(gc_cu_blocks_received_delta/&unit),0) cu_blocks,
           nullif(&gc_grants,0) gc_grants,
           nullif(&pop_cus,0) pop_cus,
           nullif(&repop_cus,0) repop_cus,
           nullif(sum(itl_waits_delta/&unit),0) itl_waits,
           nullif(sum(row_lock_waits_delta/&unit),0) lock_waits,
           nullif(sum(chain_row_excess_delta/&unit),0) chain_rows,
           nullif(max(decode(r,1,space_used_total)),0) space
           &12c ,nullif(max(decode(r,1,im_membytes)),0) im_mem
    FROM (SELECT a.*, 
                 row_number() OVER(PARTITION BY dbid, obj#, dataobj# ORDER BY space_used_total DESC) r 
         FROM (
            SELECT /*+outline_leaf leading(a b c) use_hash(a b c)*/ *
            FROM &check_access_pdb.seg_stat_obj b
            JOIN &check_access_pdb.seg_stat c USING (dbid,obj#,dataobj#)
            JOIN (SELECT dbid,snap_id,instance_number,
                         greatest(1,round(86400*((end_interval_time+0)-
                            CASE WHEN begin_interval_time+0>= to_date(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')-3/1440
                                 THEN begin_interval_time+0 
                            END))) s
                  FROM &check_access_pdb.snapshot
                  WHERE end_interval_time BETWEEN to_timestamp(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
                  AND   to_timestamp(coalesce('&V4', to_char(sysdate+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')) a
            USING(dbid,instance_number,snap_id)
            WHERE dbid=&dbid
            AND   &filter
            ) a)
    GROUP BY owner,object_name,ROLLUP(subobject_name)
)
SELECT * FROM(
    SELECT ratio_to_report(&v2) OVER()*2 "Weight",
           '|' "|",
           a.*
    FROM segs a
    ORDER BY &v2 DESC NULLS LAST)
WHERE ROWNUM<=50
AND   nvl("Partition",'x') NOT LIKE '%(1 segs)%'
ORDER BY 1 DESC;

col Statistics break ~
var c refcursor "Top Segments by Statistics(threshold = 8%)"
BEGIN
    OPEN :c FOR 
        WITH segs AS(
            SELECT /*+MATERIALIZE opt_param('parallel_execution_enabled', 'false')*/ 
                   owner,object_name,
                   decode(count(DISTINCT nvl(subobject_name,' ')),1,max(obj#)) obj#,
                   decode(grouping_id(subobject_name),0,subobject_name,''||count(DISTINCT nvl(subobject_name,' '))) segments,
                   nullif(sum(table_scans_delta/&unit),0) scans,
                   nullif(&imscans,0) imscans,
                   nullif(sum(logical_reads_delta/&unit),0) logi_reads,
                   nullif(sum(buffer_busy_waits_delta/&unit),0) busy_waits,
                   nullif(sum(gc_buffer_busy_delta/&unit),0) gc_busy,
                   nullif(sum(physical_read_requests_delta/&unit),0) phy_rreqs,
                   nullif(&opt_reads,0) opt_reads,
                   nullif(sum(physical_reads_delta/&unit),0) phy_reads,
                   nullif(round(sum(physical_reads_direct_delta)/nullif(sum(physical_reads_delta),0),4),0)  dx_reads,
                   nullif(sum(gc_cr_blocks_received_delta/&unit),0) cr_blocks,
                   nullif(sum(db_block_changes_delta/&unit),0) blk_chgs,
                   nullif(&im_chgs,0) im_chgs,
                   nullif(sum(physical_write_requests_delta/&unit),0) phy_wreqs,
                   nullif(sum(physical_writes_delta/&unit),0) phy_writes,
                   nullif(round(sum(physical_writes_direct_delta)/nullif(sum(physical_writes_delta),0),4),0) dx_writes,
                   nullif(sum(gc_cu_blocks_received_delta/&unit),0) cu_blocks,
                   nullif(&gc_grants,0) gc_grants,
                   nullif(&pop_cus,0) pop_cus,
                   nullif(&repop_cus,0) repop_cus,
                   nullif(sum(itl_waits_delta/&unit),0) itl_waits,
                   nullif(sum(row_lock_waits_delta/&unit),0) lock_waits,
                   nullif(sum(chain_row_excess_delta/&unit),0) chain_rows,
                   nullif(max(decode(r,1,space_used_total)),0) space
                   &12c ,nullif(max(decode(r,1,im_membytes)),0) im_mem
            FROM (SELECT a.*, 
                         row_number() OVER(PARTITION BY dbid, obj#, dataobj# ORDER BY space_used_total DESC) r 
                 FROM (
                    SELECT /*+outline_leaf leading(a b c) use_hash(a b c)*/ *
                    FROM &check_access_pdb.seg_stat_obj b
                    JOIN &check_access_pdb.seg_stat c USING (dbid,obj#,dataobj#)
                    JOIN (SELECT dbid,snap_id,instance_number,
                                 greatest(1,round(86400*((end_interval_time+0)-
                                    CASE WHEN begin_interval_time+0>= to_date(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')-3/1440
                                         THEN begin_interval_time+0 
                                    END))) s
                          FROM &check_access_pdb.snapshot
                          WHERE end_interval_time BETWEEN to_timestamp(coalesce('&V3', to_char(sysdate - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
                          AND   to_timestamp(coalesce('&V4', to_char(sysdate+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI')) a
                    USING(dbid,instance_number,snap_id)
                    WHERE dbid=&dbid
                    AND   &filter
                    ) a)
            GROUP BY owner,object_name,ROLLUP(subobject_name)
            HAVING grouping_id(subobject_name)=&flag)
        SELECT n "Statistics",v "Value",p "Weight", owner,object_name,obj#,segments
        FROM (
            SELECT a.*,round(ratio_to_report(v) OVER(PARTITION BY n),4) p
            FROM (
                SELECT r,
                       decode(r,
                              1, 'Logical Reads',
                              2, 'Physical Reads',
                              3, 'Physical Read Requests',
                              4, 'Direct Path Reads',
                              5, 'Physical Reads Un-Optimized',
                              6, 'Segment Scans',
                              7, 'In-Memory Scans',
                              8, 'DB Block Changes',
                              9, 'In-Memory Block Changes',
                              10, 'Physical Writes',
                              11, 'Physical Write Requests',
                              12, 'Direct Path Writes',
                              13, 'Buffer Busy Waits',
                              14, 'GC Buffer Busy Waits',
                              15, 'GC Remote Grants',
                              16, 'GC CR Blocks Received',
                              17, 'GC CU Blocks Received',
                              18, 'Row Lock Waits',
                              19, 'ITL Waits',
                              20, 'Chained Rows',
                              21, 'Populated CUs',
                              22, 'Repopulated CUs') n,
                        nullif(round(decode(a.r,
                                      1,logi_reads,
                                      2,phy_reads,
                                      3,phy_rreqs,
                                      4,dx_reads,
                                      5,phy_reads-nvl(opt_reads,0),
                                      6,scans,
                                      7,imscans,
                                      8,blk_chgs,
                                      9,im_chgs,
                                      10,phy_writes,
                                      11,phy_wreqs,
                                      12,dx_writes,
                                      13,busy_waits,
                                      14,gc_busy,
                                      15,gc_grants,
                                      16,cr_blocks,
                                      17,cu_blocks,
                                      18,lock_waits,
                                      19,itl_waits,
                                      20,chain_rows,
                                      21,pop_cus,
                                      22,repop_cus),2),0) v,
                        owner,object_name,obj#,segments
                FROM (SELECT ROWNUM r FROM dual CONNECT BY ROWNUM<=22) a, segs) a
        WHERE v>0)
    WHERE p>=0.08
    ORDER BY r,p DESC;
END;
/