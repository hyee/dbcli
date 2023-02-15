/*[[Show temp tablespace usage. Usage: @@NAME [-f"<filter>"|-text"<keyword>"] 
    --[[--
        &filter: default={1=1} f={(&0)} text={UPPER(sql_text) LIKE UPPER('%&0%')}
        @sq_id:  12.1={a.SQL_ID_TEMPSEG} default={a.sql_id}
        @cid: 12.1={,con_id} default={}
    --]]--
]]*/
set feed off
col BYTES_CACHED,BYTES_FREE,BYTES_USED,bytes,BLOCK_SIZE for kmg
col inst_id head INST
col tablespace_name head TABLESPACE
col EXTENTS_CACHED,EXTENTS_USED,USED_EXTENTS,FREE_EXTENTS noprint
col BLOCKS_CACHED,BLOCKS_USED for tmb

PRO GV$TEMP_EXTENT_POOL:
PRO ====================
select /*+opt_param('optimizer_dynamic_sampling' 5)*/ DISTINCT * 
from gv$temp_extent_pool order by 2,3,1;

PRO GV$SORT_SEGMENT(In dba_segments where segment_type = 'TEMPORARY')
PRO         (Use level 2147483647 to cleanup all tablespaces)
PRO ===================================================================
SELECT /*+opt_param('optimizer_dynamic_sampling' 5)*/
       inst_id inst,
       T1.TS#,
       TABLESPACE_NAME,
       S.USED_EXTENTS,
       S.FREE_EXTENTS,
       S.CURRENT_USERS,
       S.FREE_BLOCKS,
       T2.NEXT_EXTENT,
       T2.BLOCK_SIZE,
       S.FREE_BLOCKS * T2.BLOCK_SIZE BYTES_FREE,
       S.USED_BLOCKS * T2.BLOCK_SIZE BYTES_USED &cid,
       'alter session set events ''immediate trace name DROP_SEGMENTS level ' || (T1.TS# + 1) || ''';' STMT
FROM   GV$SORT_SEGMENT S 
JOIN   (SELECT TS#,NAME TABLESPACE_NAME &cid FROM V$TABLESPACE) T1 USING(TABLESPACE_NAME &cid) 
JOIN   DBA_TABLESPACES T2 USING(TABLESPACE_NAME)
;

PRO GV$TEMPSEG_USAGE:
PRO =================
WITH tmps AS (    
    SELECT /*+inline*/ sid,spid,username,tablespace,
           round(BLOCKS*(select value from v$parameter where name='db_block_size'), 2) bytes,
           segtype,event,sql_id
    FROM TABLE(GV$(CURSOR(
        SELECT /*+ordered*/
               B.SID||','||B.SERIAL#||',@'||userenv('instance') sid,
               P.SPID,
               B.USERNAME,
               TABLESPACE,
               a.blocks,
               A.SEGTYPE,
               b.event,
               &sq_id SQL_ID
        FROM   v$tempseg_usage A, V$SESSION B, v$PROCESS P
        WHERE  A.SESSION_ADDR = B.SADDR
        AND    B.PADDR = P.ADDR))))
SELECT A.*,trim(substr(b.sql_text,1,200)) sql_text
FROM   tmps a
LEFT JOIN (
    SELECT sql_id,extractvalue(column_value,'/ROW/SQL_TEXT') sql_text
    FROM   (select /*+no_merge*/ distinct sql_id from tmps) a,
           TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'{
               SELECT substr(regexp_replace(REPLACE(sql_text, chr(0)),'\s+',' '),1,2000) sql_text
               FROM   gv$sqlstats
               WHERE  sql_id = '}'||a.sql_id||'''
               AND    rownum<2'),'/ROWSET/ROW'))) ) b
ON a.sql_id=b.sql_id
WHERE &filter
ORDER  BY BYTES DESC;