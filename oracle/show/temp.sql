/*[[Show temp tablespace usage]]*/
SELECT /*+ ordered */
     B.SID,
     B.SERIAL#,
     B.INST_ID,
     P.SPID,
     B.USERNAME,
     TABLESPACE,
     round(A.BLOCKS * 8 / 1024, 2) MB,
     A.SEGTYPE,
     b.event,
     a.SQL_ID,
     extractvalue(c.column_value,'/ROW/SQL_TEXT')  sql_text
FROM   gV$tempseg_usage A, gV$SESSION B, gV$PROCESS P,
       TABLE(XMLSEQUENCE(EXTRACT(dbms_xmlgen.getxmltype(q'{
           SELECT substr(regexp_replace(REPLACE(sql_text, chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' '),1,200) sql_text
           FROM   gv$sqlstats
           WHERE  sql_id = '}'||a.sql_id||'''
           AND    inst_id = '||a.inst_id),'/ROWSET/ROW')))(+) c
WHERE  A.SESSION_ADDR = B.SADDR
AND    B.PADDR = P.ADDR
AND    a.inst_id = b.inst_id
AND    b.inst_id = p.inst_id;