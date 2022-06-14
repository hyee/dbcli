/*[[Show temp tablespace usage. Usage: @@NAME [-f"<filter>"|-text"<keyword>"] 
    --[[--
        &filter: default={} f={AND (&0)} text={AND UPPER(extractvalue(c.column_value,'/ROW/SQL_TEXT')) LIKE UPPER('%&0%')}
        @sq_id:  12.1={a.SQL_ID_TEMPSEG} default={a.sql_id}
        @cid: 12.1={,con_id} default={}
    --]]--
]]*/
set feed off
col BYTES_CACHED,BYTES_FREE,BYTES_USED,bytes,BLOCK_SIZE for kmg
PRO GV$TEMP_EXTENT_POOL:
PRO ====================
select /*+opt_param('optimizer_dynamic_sampling' 5)*/ DISTINCT * 
from gv$temp_extent_pool order by 2,3,1;

PRO UNLOCKED SEGMENTS(In dba_segments where segment_type = 'TEMPORARY')
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

PRO GV$TEMP_EXTENT_POOL:
PRO ====================
SELECT /*+ ordered opt_param('optimizer_dynamic_sampling' 5)*/
     B.SID||','||B.SERIAL#||',@'||B.INST_ID sid,
     P.SPID,
     B.USERNAME,
     TABLESPACE,
     round(A.BLOCKS*(select value from v$parameter where name='db_block_size'), 2) bytes,
     A.SEGTYPE,
     b.event,
     &sq_id SQL_ID,
     SUBSTR(extractvalue(c.column_value,'/ROW/SQL_TEXT'),1,200)  sql_text
FROM   gv$tempseg_usage A, gV$SESSION B, gv$PROCESS P,
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'{
           SELECT substr(regexp_replace(REPLACE(sql_text, chr(0)),'\s+',' '),1,512) sql_text
           FROM   gv$sqlstats
           WHERE  sql_id = '}'||&sq_id||'''
           AND    inst_id = '||a.inst_id),'/ROWSET/ROW')))(+) c
WHERE  A.SESSION_ADDR = B.SADDR
AND    B.PADDR = P.ADDR
AND    a.inst_id = b.inst_id
AND    b.inst_id = p.inst_id &filter
ORDER  BY BYTES DESC;