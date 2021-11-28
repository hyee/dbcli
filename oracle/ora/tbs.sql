/*[[Show tablspace usage, or file usage if specify the tablespace name. Usage: @@NAME [<tablespace_name>] [-cdb]

Sample Outputs:
===============
ORCL> ora tbs                                                                                                                                  
      TABLESPACE_NAME   File(s)  MAX_SIZE   FILE_SIZE  HWM_SPACE USED_SPACE FREE_SPACE TOTAL_FREE USED(%) IOPS  MBPS   LATENCY FSFI(%) LOCATION
    ------------------- ------- ---------- ---------- ---------- ---------- ---------- ---------- ------- ---- ------- ------- ------- --------
    TOTAL(Permanent)    13       353.95 GB    4.68 GB    2.93 GB    2.91 GB    1.77 GB  351.05 GB    0.82    0 1.22 KB   957us      36 /u01    
      SYSAUX            1         32.00 GB    1.29 GB    1.23 GB    1.22 GB   66.64 MB   30.78 GB    3.82    0  704  B   952us    58.7 /u01    
      SYSTEM            1         32.00 GB 1010.00 MB 1002.00 MB 1001.80 MB    8.20 MB   31.02 GB    3.06    0  122  B     1ms   82.81 /u01    
      MITIREP_1203      1         32.00 GB  330.00 MB  292.00 MB  291.30 MB   38.70 MB   31.72 GB    0.89    0    0  B           83.27 /u01    
      USERS             2         64.00 GB  312.00 MB  164.12 MB  164.22 MB  147.78 MB   63.84 GB    0.25    0    0  B           84.09 /u01    
      ODIDEMO           1         32.00 GB  300.00 MB  127.00 MB  106.80 MB  193.20 MB   31.90 GB    0.33    0    0  B           38.63 /u01    
      OGG_ODI_USER      1       1000.00 MB  200.00 MB   61.87 MB   61.92 MB  138.08 MB  938.08 MB    6.19    0    0  B             100 /u01    
      UNDOTBS1          1         32.00 GB    1.05 GB   53.00 MB   52.23 MB    1.00 GB   31.95 GB    0.16    0  418  B   811us   84.06 /u01    
      OGG_IAS_OPSS      1         32.00 GB   60.00 MB   38.37 MB   38.42 MB   21.58 MB   31.96 GB    0.12    0    0  B             100 /u01    
      FERMATDATA        1         32.00 GB   10.00 MB    1.81 MB    1.86 MB    8.14 MB   32.00 GB    0.01    0    0  B             100 /u01    
      FERMATINDEXES     1         32.00 GB   10.00 MB    1.69 MB    1.73 MB    8.27 MB   32.00 GB    0.01    0    0  B             100 /u01    
      OGG_IAS_IAU       1         32.00 GB   60.00 MB    1.62 MB    1.67 MB   58.33 MB   32.00 GB    0.01    0    0  B             100 /u01    
      OGG_STB           1       1000.00 MB  100.00 MB    1.25 MB    1.30 MB   98.70 MB  998.70 MB    0.13    0    0  B             100 /u01    
    TOTAL(Temporary)    4         65.07 GB  730.00 MB  730.00 MB    2.00 MB  728.00 MB   65.07 GB       0                              /u01    
      TEMP              1         32.00 GB  500.00 MB  500.00 MB    2.00 MB  498.00 MB   32.00 GB    0.01                              /u01    
      OGG_ODI_TEMP      1       1000.00 MB  100.00 MB  100.00 MB       0  B  100.00 MB 1000.00 MB       0                              /u01    
      OGG_IAS_TEMP      1        100.00 MB  100.00 MB  100.00 MB       0  B  100.00 MB  100.00 MB       0                              /u01    
      MITIREP_1203_TEMP 1         32.00 GB   30.00 MB   30.00 MB       0  B   30.00 MB   32.00 GB       0                              /u01    
                                                                                                                         
ORCL> ora tbs SYSTEM                                                                                                                           
    TABLESPACE_NAME File(s) MAX_SIZE  FILE_SIZE  HWM_SPACE USED_SPACE FREE_SPACE TOTAL_FREE USED(%) IOPS  MBPS  LATENCY FSFI(%)                
    --------------- ------- -------- ---------- ---------- ---------- ---------- ---------- ------- ---- ------ ------- ------- ---------------
    SYSTEM          1       32.00 GB 1010.00 MB 1002.00 MB 1001.80 MB    8.20 MB   31.02 GB    3.06    0 122  B     1ms   82.81 /u01           
                    #1      32.00 GB 1010.00 MB 1002.00 MB 1001.80 MB    8.20 MB   31.02 GB    3.06    0 122  B     1ms   82.81 /u01/app/oracle

    --[[
        @CHECK_ACCESS: wmsys.wm_concat={wmsys.wm_concat(DISTINCT loc)}, default={&VERSION}
        @VERSION: 11.2={regexp_replace(listagg(loc,',') within group(order by loc),'([^,]+)(,\1)+','\1')} default={null}
        &cid    : default={file_id} cdb={con_id}
        &cid2   : default={null} cdb={con_id}
        &cname  : default={fid} cdb={con_id}
        &con    : default={dba_} cdb={cdb_}
        &pname  : default={&cname} cdb={(select name from v$containers b where b.con_id=a.con_id) pdb}
        @attr11  : 11.2={} default={--}
        @attr12  : 12.2={} default={--}
        @attr18  : 18.1={} default={--}
        @attr19  : 19.1={} default={--}
    --]]
]]*/
set printsize 1000
set autohide col
col MAX_SIZE format KMG
col FILE_SIZE format KMG
col USED_SPACE format KMG
col HWM_SPACE format KMG
col FREE_SPACE format KMG
col TOTAL_FREE,MBPS format KMG
col latency for usmhd0
col fid noprint
col "USED(%)" for pct2

SELECT &pname,
       TABLESPACE_NAME,
       files "File(s)",
       siz "MAX_SIZE",
       SPACE "FILE_SIZE",
       HWM_SPACE "HWM_SPACE",
       SPACE - NVL(FREE_SPACE, 0) "USED_SPACE",
       FREE_SPACE "FREE_SPACE",
       siz+FREE_SPACE-space "TOTAL_FREE",
       ROUND((SPACE - NVL(FREE_SPACE, 0))/nullif(siz, 0),4) "USED(%)",
       IOPS,MBPS,latency,
       FSFI "FSFI(%)",
       g location,
       attrs
FROM  (SELECT /*+NO_EXPAND_GSET_TO_UNION NO_MERGE opt_param('_optimizer_filter_pushdown','false')*/
              &cname,
              decode(grouping_id(TABLESPACE_NAME,file_id),0,null,3,'TOTAL('||IS_TEMP||')',nvl2(:V1,'','  ')||TABLESPACE_NAME) TABLESPACE_NAME,
              decode(grouping_id(file_id),0,'#'||file_id,''||count(1)) files,
              nvl(SUM(FREE_BYTES-6*blocksiz),0)  FREE_SPACE, --minus 6 end blocks
              round(sqrt(sum(m_blocks)/sum(s_blocks))* (100/sqrt(sqrt(sum(c_blocks)))),2) fsfi,
              sum(nvl(hwm_block*blocksiz,space)) HWM_SPACE,
              SUM(siz) siz,
              SUM(space) SPACE,
              NULLIF(ROUND(SUM(IOPS)),0) IOPS,
              NULLIF(SUM(MBPS*blocksiz),0) MBPS,
              NULLIF(round(1E4*SUM(latency)/nullif(SUM(IOPS),0)),0) latency,
              IS_TEMP,
              decode(grouping_id(file_id),0,max(file_name),&CHECK_ACCESS) g,
              decode(grouping_id(TABLESPACE_NAME,file_id),0,MAX(F.ATTRS),1,MAX(T.ATTRS)) attrs
        FROM(
            SELECT a.*,row_number() over(partition by tablespace_name,loc order by 1) loc_seq
            FROM (
                SELECT /*+no_merge no_expand no_merge(b) no_merge(a) no_push_pred(a) use_hash(b a) opt_param('_optimizer_sortmerge_join_enabled','false')*/
                       TABLESPACE_NAME,FILE_ID,&cname,
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
                       max(IOPS) IOPS,MAX(MBPS) MBPS,MAX(latency) latency,
                       MAX(TRIM(',' FROM REGEXP_REPLACE(
                          DECODE(STATUS,'AVAILABLE','',STATUS||',')||
                          DECODE(ONLINE_STATUS,'ONLINE','',ONLINE_STATUS||',')||
                          'NEXT('||DECODE(AUTOEXTENSIBLE,'YES',TRIM(DBMS_XPLAN.FORMAT_SIZE2(INCREMENT_BY*b.BYTES/b.BLOCKS)),'0')||')'||
                          '',',+',','))) attrs
                FROM   &CON.FREE_SPACE a 
                LEFT JOIN (select /*+no_merge*/ 
                              file_id,&cid2 &cname,
                              SUM((PHYSICAL_READS+PHYSICAL_WRITES)*60/INTSIZE_CSEC) IOPS,
                              SUM((PHYSICAL_BLOCK_READS+PHYSICAL_BLOCK_WRITES)*60/INTSIZE_CSEC) MBPS,
                              SUM((PHYSICAL_READS*AVERAGE_READ_TIME+PHYSICAL_WRITES*AVERAGE_WRITE_TIME)*60/INTSIZE_CSEC)  latency
                       FROM gv$filemetric
                       GROUP BY file_id,&cid) c
                USING (FILE_ID,&cid)
                RIGHT JOIN (select b.*,row_number() over(partition by TABLESPACE_NAME,regexp_substr(b.file_name, '^.[^\\/]+') order by 1) seq from &CON.DATA_FILES b) b 
                USING (TABLESPACE_NAME,FILE_ID,&cid)
                WHERE  (:V1 IS NULL OR TABLESPACE_NAME=upper(:V1))
                GROUP  BY TABLESPACE_NAME,FILE_ID,&cname
                UNION ALL
                SELECT /*+NO_EXPAND_GSET_TO_UNION no_expand no_merge(h) no_merge(p) no_merge(f) use_hash(h p f)*/
                       TABLESPACE_NAME,
                       file_id,&cid2,
                       SUM((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) FREE_BYTES,
                       0 blocksiz,null,null,null,
                       SUM(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes))  file_size,
                       SUM(h.bytes_free + h.bytes_used)  space_all,
                       null hwm_block,
                       max(f.file_name) file_name,
                       max(decode(seq,1,loc)) loc,
                       'Temporary',NULL,NULL,NULL,
                       MAX(TRIM(',' FROM REGEXP_REPLACE(
                          DECODE(STATUS,'AVAILABLE','',STATUS||',')||
                          'NEXT('||DECODE(AUTOEXTENSIBLE,'YES',TRIM(DBMS_XPLAN.FORMAT_SIZE2(INCREMENT_BY*f.BYTES/f.BLOCKS)),'0')||')'||
                          '',',+',','))) attrs
                FROM   (select distinct * from v$TEMP_SPACE_HEADER) h
                LEFT   JOIN (select distinct * from v$Temp_extent_pool) p 
                USING  (file_id,&cid,tablespace_name)
                JOIN   (select a.*, regexp_substr(file_name, '^.[^\\/]+') loc,1 seq from &CON.temp_files a) f
                USING  (file_id,&cid,tablespace_name)
                WHERE  (:V1 IS NULL OR TABLESPACE_NAME=upper(:V1))
                GROUP  BY tablespace_name,FILE_ID,&cid2
            ) A) F JOIN (
                SELECT TABLESPACE_NAME,
                     TRIM(',' FROM REGEXP_REPLACE(
                         (SELECT '#'||TS#||',' FROM v$tablespace WHERE name=tablespace_name)||
                         'BLOCK('||TRIM(DBMS_XPLAN.FORMAT_SIZE2(BLOCK_SIZE))||'),'||
                         DECODE(STATUS,'ONLINE','',STATUS||',')||
                         DECODE(CONTENTS,'UNDO','UNDO'||(decode(RETENTION,'NOT APPLY','','('||RETENTION||')'))||',')||
                         DECODE(LOGGING,'NOLOGGING','NOLOGGING,')||
                         DECODE(ALLOCATION_TYPE,'UNIFORM','UNIFORM('||TRIM(DBMS_XPLAN.FORMAT_SIZE2(NEXT_EXTENT))||'),')||
                         DECODE(SEGMENT_SPACE_MANAGEMENT,'MANUAL','LMT,')||
                         &attr11 DECODE(BIGFILE,'YES','BIGFILE,')||
                         &attr11 DECODE(ENCRYPTED,'YES','TDE,')||
                         &attr11 DECODE(PLUGGED_IN,'YES','PLUGIN,')||
                         &attr11 DECODE(PREDICATE_EVALUATION,NULL,'','STORAGE','','PRED: '||PREDICATE_EVALUATION)||
                         &attr11 COMPRESS_FOR||','||
                         &attr12 DECODE(CHUNK_TABLESPACE,'Y','CHUNK,')||
                         &attr12 DECODE(SHARED,'SHARED','',SHARED||',')||
                         &attr12 NVL2(INDEX_COMPRESS_FOR,'INDEX-'||INDEX_COMPRESS_FOR||',','')||
                         &attr12 NVL2(DEF_INMEMORY_COMPRESSION,'DBIM-'||DEF_INMEMORY_COMPRESSION||'-PRIOR('||DEF_INMEMORY_PRIORITY||')-DISTRIB('||DEF_INMEMORY_DUPLICATE||')','')||
                         '',',+',',')) AS ATTRS
              FROM &CON.tablespaces) T USING(TABLESPACE_NAME)
        GROUP BY  &cname,IS_TEMP,ROLLUP(TABLESPACE_NAME,FILE_ID)
        HAVING (:V1 IS NOT NULL AND grouping_id(TABLESPACE_NAME)<1) OR (:V1 IS NULL AND FILE_ID IS NULL)) a
ORDER  BY 1,IS_TEMP,USED_SPACE DESC,TABLESPACE_NAME DESC NULLS LAST;