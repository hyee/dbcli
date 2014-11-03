/*[[Show temp tablespace usage]]*/
SELECT /*+ ordered */
 B.SID,
 B.SERIAL#,
 B.INST_ID,
 P.SPID,
 B.USERNAME,
 B.MACHINE,
 round(A.BLOCKS * 8 / 1024, 2) MB,
 A.SEGTYPE,
 b.sql_id top_sql_id,
 a.SQL_ID,
 (SELECT substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),
                               '[' || chr(10) || chr(13) || chr(9) || ' ]+',
                               ' '),
                1,
                120)
  FROM   gv$sqlarea s
  WHERE  s.inst_id = a.inst_id
  AND    s.sql_id = a.sql_id) sql_text
FROM   gV$SORT_USAGE A, gV$SESSION B, gV$PROCESS P
WHERE  A.SESSION_ADDR = B.SADDR
AND    B.PADDR = P.ADDR
AND    a.inst_id = b.inst_id
AND    b.inst_id = p.inst_id
