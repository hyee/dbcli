/*[[Get SQL List that is captured by SQL monitor. Usage: sqls [elapsed_minutes]]]*/
SELECT *
FROM   (SELECT /*+no_expand*/ 
               a.sql_id,
               a.inst_id,
               a.SID,
               to_char(a.last_refresh_time,'MMDD-HH24:MI:SS') tim,
              -- NVL(floor(a.elapsed_time/(a.last_refresh_time-a.sql_exec_start)/(86400*1e6)),0) PX,
               ROUND((a.last_refresh_time-a.sql_exec_start)*1440, 2) ela,
               substr(regexp_replace(regexp_replace(b.sql_text, '^\s+|[' || CHR(10) || CHR(13) || ']'),'\s{2,}',' '), 1, 200) sql_text
        FROM   gv$sql_monitor a,gv$sqlarea b
        WHERE  a.inst_id=b.inst_id
        AND    a.sql_id=b.sql_id
        AND    not regexp_like(a.process_name,'^p\d+$')
        AND    b.SQL_TEXT not like 'DECLARE job BINARY_INTEGER%'
        AND    a.sql_id||lower(b.sql_text) like '%'||lower(:V2)||'%'
        ORDER  BY tim DESC)
WHERE  ROWNUM <= 50
AND    ela>=nvl(0+:V1,0)
ORDER  BY tim,ela
