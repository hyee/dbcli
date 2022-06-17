/*[[List AWR top segments. Usage: @@NAME [<keyword>] [<sort_by>] [yymmddhhmi] [yymmddhhmi] 
    <keyword>: Used to fussily search over OWNER+OBJECT_NAME+SUBOBJECT_NAME+OBJ#+DATAOBJ#
    <sort_by>: Sort the records with specific order

    --[[
        @11G : 11.2={} DEFAULT={--}
        @12c : 19.1={} DEFAULT={--}
        @CON : 12.1={,CON_DBID} DEFAULT={}
        @phf : 12.1={nvl2(other_xml,to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'')} default={null}
        &AWR_VIEW        : default={AWR_PDB_} hist={dba_hist_}
        @check_access_pdb: pdb/awr_pdb_snapshot={&AWR_VIEW.} default={DBA_HIST_}
        @did : 12.2={sys_context('userenv','dbid')+0} default={(select dbid from v$database)}
        &v2 : default={'0'}  
    ]]--
]]*/
COL "scans,imscans,logi_reads,busy_waits,phy_rreqs,phy_reads,phy_wreqs,phy_writes" FOR TMB
COL "blk_chgs,im_chgs,gc_busy,cr_blocks,cu_blks,itl_waits,lock_waits,gc_grants,chain_rows" FOR TMB
COL "space,im_mem" FOR KMG
COL "opt_reads,dx_reads,dx_writes" FOR PCT2
SET AUTOHIDE COL

SELECT * FROM(
SELECT owner,object_name "SEG STATS|OBJECT NAME",
       decode(grouping_id(SUBOBJECT_NAME),0,SUBOBJECT_NAME,'** '||COUNT(DISTINCT dataobj#)||' segs **') "SEG|NAME",
       nullif(SUM(TABLE_SCANS_DELTA),0) scans,
       &12c nullif(SUM(IM_SCANS_DELTA),0) imscans,
       nullif(SUM(LOGICAL_READS_DELTA),0) logi_reads,
       nullif(SUM(BUFFER_BUSY_WAITS_DELTA),0) busy_waits,
       nullif(SUM(GC_BUFFER_BUSY_DELTA),0) gc_busy,
       nullif(SUM(PHYSICAL_READ_REQUESTS_DELTA),0) phy_rreqs,
       &11G nullif(ROUND(SUM(OPTIMIZED_PHYSICAL_READS_DELTA)/NULLIF(SUM(PHYSICAL_READ_REQUESTS_DELTA),0),4),0) opt_reads,
       nullif(SUM(PHYSICAL_READS_DELTA),0) phy_reads,
       nullif(ROUND(SUM(PHYSICAL_READS_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_READS_DELTA),0),4),0)  dx_reads,
       nullif(SUM(GC_CR_BLOCKS_RECEIVED_DELTA),0) cr_blocks,
       nullif(SUM(DB_BLOCK_CHANGES_DELTA),0) blk_chgs,
       &12c nullif(SUM(IM_DB_BLOCK_CHANGES_DELTA),0) im_chgs,
       nullif(SUM(PHYSICAL_WRITE_REQUESTS_DELTA),0) phy_wreqs,
       nullif(SUM(PHYSICAL_WRITES_DELTA),0) phy_writes,
       nullif(ROUND(SUM(PHYSICAL_WRITES_DIRECT_DELTA)/NULLIF(SUM(PHYSICAL_WRITES_DELTA),0),4),0) dx_writes,
       nullif(SUM(GC_CU_BLOCKS_RECEIVED_DELTA),0) cu_blks,
       nullif(MAX(decode(r,1,SPACE_USED_TOTAL)),0) space,
       &12c nullif(SUM(IM_MEMBYTES),0) im_mem,
       nullif(SUM(ITL_WAITS_DELTA),0) itl_waits,
       nullif(SUM(ROW_LOCK_WAITS_DELTA),0) lock_waits,
       &12c  nullif(SUM(GC_REMOTE_GRANTS_DELTA),0) gc_grants,
       nullif(SUM(CHAIN_ROW_EXCESS_DELTA),0) chain_rows
from (select a.*, row_number() over(PARTITION BY dbid, obj#, dataobj# ORDER BY SPACE_USED_TOTAL DESC) r 
     from (
        select *     
        FROM &check_access_pdb.Seg_stat_obj
        JOIN &check_access_pdb.Seg_stat USING (dbid,obj#,dataobj# &CON)
        JOIN (select dbid,snap_id,instance_number
              from &check_access_pdb.snapshot
              where end_interval_time between to_timestamp(coalesce(:V3,:starttime, to_char(SYSDATE - 7, 'YYMMDDHH24MI')),'YYMMDDHH24MI')
              and   to_timestamp(coalesce(:V4,:endtime, to_char(SYSDATE+1, 'YYMMDDHH24MI')), 'YYMMDDHH24MI'))
        USING(dbid,instance_number,snap_id)
        WHERE UPPER('.'||owner||'.'||object_name||'.'||subobject_name||'.') LIKE upper('%&V1%')
        ) a)
GROUP BY owner,object_name,rollup(SUBOBJECT_NAME)
HAVING grouping_id(SUBOBJECT_NAME)=0 OR COUNT(DISTINCT dataobj#)>1
ORDER BY &v2 desc,nvl(logi_reads,0)/15+nvl(phy_reads,0)+nvl(phy_writes,0) DESC)
WHERE ROWNUM<=50;