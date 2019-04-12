/*[[Show tablspace usage, or file usage if specify the tablespace name. Usage: @@NAME [<tablespace_name>]
    --[[
        @CHECK_ACCESS: wmsys.wm_concat={wmsys.wm_concat(DISTINCT loc)}, default={&VERSION}
        @VERSION: 11.2={regexp_replace(listagg(loc,',') within group(order by file_name),'([^,]+)(,\1)+','\1')} default={null}
    --]]
]]*/
set printsize 1000
col MAX_SIZE format KMG
col FILE_SIZE format KMG
col USED_SPACE format KMG
col HWM_SPACE format KMG
col FREE_SPACE format KMG
col TOTAL_FREE,MBPS format KMG
col latency for usmhd0

SELECT TABLESPACE_NAME,
       files "File(s)",
       siz "MAX_SIZE",
       SPACE "FILE_SIZE",
       HWM_SPACE "HWM_SPACE",
       SPACE - NVL(FREE_SPACE, 0) "USED_SPACE",
       FREE_SPACE "FREE_SPACE",
       siz+FREE_SPACE-space "TOTAL_FREE",
       ROUND(100*(SPACE - NVL(FREE_SPACE, 0))/nullif(siz, 0),2) "USED(%)",
       IOPS,MBPS,latency,
       FSFI "FSFI(%)",
       g location
FROM  (SELECT /*+NO_EXPAND_GSET_TO_UNION NO_MERGE opt_param('_optimizer_filter_pushdown','false')*/ 
              decode(grouping_id(TABLESPACE_NAME,file_id),0,null,3,'TOTAL('||IS_TEMP||')',nvl2(:V1,'','  ')||TABLESPACE_NAME) TABLESPACE_NAME,
              decode(grouping_id(file_id),0,'#'||file_id,''||count(1)) files,
              nvl(SUM(FREE_BYTES-6*blocksiz),0)  FREE_SPACE, --minus 6 end blocks
              round(sqrt(sum(m_blocks)/sum(s_blocks))* (100/sqrt(sqrt(sum(c_blocks)))),2) fsfi,
              sum(nvl(hwm_block*blocksiz,space)) HWM_SPACE,
              SUM(siz) siz,
              SUM(space) SPACE,
              ROUND(SUM(IOPS)) IOPS,SUM(MBPS*blocksiz) MBPS,round(1E4*SUM(latency)/nullif(SUM(IOPS),0)) latency,
              IS_TEMP,
              decode(grouping_id(file_id),0,max(file_name),&CHECK_ACCESS) g
        FROM(
            SELECT /*+no_merge no_expand no_merge(b) no_merge(a) no_push_pred(a) use_hash(b a) opt_param('_optimizer_sortmerge_join_enabled','false')*/
                   TABLESPACE_NAME,FILE_ID, 
                   SUM(a.BYTES) FREE_BYTES,
                   max(b.bytes/b.blocks) blocksiz, 
                   max(a.blocks) m_blocks,
                   sum(a.blocks) s_blocks,
                   count(a.blocks) c_blocks,
                   max(greatest(b.maxbytes, b.bytes)) siz,
                   max(b.bytes) space,
                   max(case when a.block_id+a.blocks-1>=b.user_blocks then a.block_id end) hwm_block,
                   max(b.file_name) file_name,
                   max(decode(seq,1,regexp_substr(b.file_name, '^.[^\\/]+'))) loc,
                   'Permanent' IS_TEMP,
                   max(IOPS) IOPS,MAX(MBPS) MBPS,MAX(latency) latency
            FROM   DBA_FREE_SPACE a 
            JOIN  (select /*+no_merge*/ 
                          file_id,
                          SUM((PHYSICAL_READS+PHYSICAL_WRITES)*60/INTSIZE_CSEC) IOPS,
                          SUM((PHYSICAL_BLOCK_READS+PHYSICAL_BLOCK_WRITES)*60/INTSIZE_CSEC) MBPS,
                          SUM((PHYSICAL_READS*AVERAGE_READ_TIME+PHYSICAL_WRITES*AVERAGE_WRITE_TIME)*60/INTSIZE_CSEC)  latency
                   FROM gv$filemetric
                   GROUP BY file_id)
            USING (FILE_ID)
            RIGHT JOIN (select b.*,row_number() over(partition by TABLESPACE_NAME,regexp_substr(b.file_name, '^.[^\\/]+') order by 1) seq from DBA_DATA_FILES b) b 
            USING (TABLESPACE_NAME,FILE_ID)
            WHERE  (:V1 IS NULL OR TABLESPACE_NAME=upper(:V1))
            GROUP  BY TABLESPACE_NAME,FILE_ID
            UNION ALL
            SELECT /*+NO_EXPAND_GSET_TO_UNION no_expand no_merge(h) no_merge(p) no_merge(f) use_hash(h p f)*/
                   h.TABLESPACE_NAME,
                   h.file_id,
                   SUM((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) FREE_BYTES,
                   0 blocksiz,null,null,null,
                   SUM(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes))  file_size,
                   SUM(h.bytes_free + h.bytes_used)  space_all,
                   null hwm_block,
                   max(f.file_name) file_name,
                   max(decode(seq,1,loc)) loc,
                   'Temporary',NULL,NULL,NULL
            FROM   v$TEMP_SPACE_HEADER h, v$Temp_extent_pool p, 
                (select a.*, regexp_substr(file_name, '^.[^\\/]+') loc,1 seq from dba_temp_files a) f
            WHERE  p.file_id(+) = h.file_id
            AND    p.tablespace_name(+) = h.tablespace_name
            AND    f.file_id = h.file_id
            AND    f.tablespace_name = h.tablespace_name
            AND   (:V1 IS NULL OR h.TABLESPACE_NAME=upper(:V1))
            GROUP  BY h.tablespace_name,h.FILE_ID
            )
        GROUP BY  IS_TEMP,ROLLUP(TABLESPACE_NAME,FILE_ID)
        HAVING (:V1 IS NOT NULL AND grouping_id(TABLESPACE_NAME)<1) OR (:V1 IS NULL AND FILE_ID IS NULL))
ORDER  BY IS_TEMP,USED_SPACE DESC,TABLESPACE_NAME DESC NULLS LAST;