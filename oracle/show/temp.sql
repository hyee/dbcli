/*[[Show temp tablespace usage.]]*/
set feed off
col BYTES_CACHED,BYTES_USED,bytes for kmg
select * from gv$temp_extent_pool order by 2,3,1;

SELECT /*+ ordered */
     B.SID||','||B.SERIAL#||',@'||B.INST_ID sid,
     P.SPID,
     B.USERNAME,
     TABLESPACE,
     round(A.BLOCKS*(select value from v$parameter where name='db_block_size'), 2) bytes,
     A.SEGTYPE,
     b.event,
     a.SQL_ID,
     extractvalue(c.column_value,'/ROW/SQL_TEXT')  sql_text
FROM   gv$tempseg_usage A, gV$SESSION B, gv$PROCESS P,
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'{
           SELECT substr(regexp_replace(REPLACE(sql_text, chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) sql_text
           FROM   gv$sqlstats
           WHERE  sql_id = '}'||a.sql_id||'''
           AND    inst_id = '||a.inst_id),'/ROWSET/ROW')))(+) c
WHERE  A.SESSION_ADDR = B.SADDR
AND    B.PADDR = P.ADDR
AND    a.inst_id = b.inst_id
AND    b.inst_id = p.inst_id;