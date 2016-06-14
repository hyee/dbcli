/*[[Show SGA stats]]*/
set feed off
col TOTAL_SIZE format kmg
col CURRENT_SIZE format kmg
col MIN_SIZE format kmg
col MAX_SIZE format kmg
col USER_SPECIFIED_SIZE format kmg
col USED_SIZE format kmg
col FREE_SIZE format kmg

pro SGA Components:
PRo ===============
select * from gv$sga_dynamic_components order by 1,2;

pro SGA Advise:
PRo ===============
SELECT * FROM gV$SGA_TARGET_ADVICE order by 1,2;

pro SGA STATS:
PRo ==========
SELECT a.*, b.bytes used_size, a.total_size-b.bytes free_size
FROM   (SELECT inst_id,name,sum(bytes) total_size FROM GV$SGAINFO GROUP BY inst_id,NAME) a
LEFT   JOIN (SELECT INST_ID, POOL, NVL2(POOL, decode(NAME, 'free memory', 'free memory', 'used memory'), NAME) typ, SUM(bytes) bytes
             FROM   GV$SGASTAT
             GROUP  BY INST_ID, POOL, NVL2(POOL, decode(NAME, 'free memory', 'free memory', 'used memory'), NAME)) b
ON     (a.inst_id = b.inst_id AND (lower(a.name) LIKE '% pool %' AND LOWER(a.name) LIKE LOWER('%' || b.pool || '%') AND b.pool IS NOT NULL AND b.typ NOT LIKE '%free%' OR --
       lower(a.name) NOT LIKE '% pool %' AND b.pool IS NULL  AND 
       (a.name = 'Redo Buffers' AND b.typ = 'log_buffer' OR REPLACE(LOWER(a.name), ' ', '_') LIKE '%' || b.typ || '%')))
ORDER BY 1,TOTAL_SIZE DESC;

pro SGA Parameters:
pro ================
ora param sga