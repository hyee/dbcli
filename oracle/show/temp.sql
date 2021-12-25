/*[[Show temp tablespace usage. Usage: @@NAME [-f"<filter>"|-text"<keyword>"] 
    --[[--
        &filter: default={} f={AND (&0)} text={AND UPPER(extractvalue(c.column_value,'/ROW/SQL_TEXT')) LIKE UPPER('%&0%')}
        @sq_id: 12.1={a.SQL_ID_TEMPSEG} default={a.sql_id}
    --]]--
]]*/
set feed off
col BYTES_CACHED,BYTES_USED,bytes for kmg
select DISTINCT * from gv$temp_extent_pool order by 2,3,1;

SELECT /*+ ordered opt_param('cursor_sharing' 'force')*/
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