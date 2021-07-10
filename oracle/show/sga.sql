/*[[Show SGA stats]]*/
set feed off
col TOTAL_SIZE format kmg
col CURRENT_SIZE format kmg
col MIN_SIZE format kmg
col MAX_SIZE format kmg
col USER_SPECIFIED_SIZE format kmg
col USED_SIZE,BYTES format kmg
col FREE_SIZE,GRANULE_SIZE format kmg

pro SGA Advise:
PRo ===============
SELECT * FROM gV$SGA_TARGET_ADVICE WHERE inst_id=nvl(:instance,userenv('instance'))  order by 1,2;

pro SGA Components:
PRo ===============
select * from gv$sga_dynamic_components WHERE inst_id=nvl(:instance,userenv('instance'))  order by 1,2;


grid {
[[--grid:{topic='SGA Info'}
    SELECT a.*,b.used used_size, nvl(b.free,a.total_size-b.used) free_size
    FROM   (SELECT inst_id inst,name,resizeable resize,sum(bytes) total_size 
            FROM GV$SGAINFO 
            WHERE inst_id=nvl(:instance,userenv('instance')) 
            GROUP BY resizeable,inst_id,NAME) a
    LEFT    JOIN (
            SELECT decode(POOL,'in-memory pool','in-memory','numa pool','%NUMA% pool',pool) pool,
                   MAX(decode(typ,'free',0,bytes)) used,
                   MAX(decode(typ,'free',bytes)) free
            FROM(SELECT nvl(POOL,name) pool, 
                        NVL2(POOL, decode(NAME, 'free memory', 'free', 'used'), NAME) typ, 
                        SUM(bytes) bytes
                 FROM   GV$SGASTAT
                 WHERE  inst_id=nvl(:instance,userenv('instance'))
                 GROUP  BY nvl(POOL,name), NVL2(POOL, decode(NAME, 'free memory', 'free', 'used'), NAME))
            GROUP BY pool) b
    ON     ((lower(a.name) LIKE '% pool %' AND b.pool like '% pool' AND LOWER(a.name) LIKE LOWER(b.pool || '%') OR --
             lower(a.name) NOT LIKE '% pool %' AND b.pool not like '% pool' and
           (   a.name = 'Redo Buffers' AND b.pool = 'log_buffer' 
               OR REPLACE(LOWER(a.name), ' ', '_') LIKE '%' || b.pool || '%')))
    ORDER BY TOTAL_SIZE DESC
]],'|',[[--grid:{topic='Shared Pool Components'}
    SELECT * FROM (
        SELECT NVL(NAME,'--TOTAL--') name,SUM(BYTES) bytes
        FROM   GV$SGASTAT
        WHERE  inst_id=nvl(:instance,userenv('instance'))
        AND    pool='shared pool'
        GROUP BY inst_id,rollup(NAME) HAVING SUM(BYTES)>0
        ORDER BY bytes DESC)
    WHERE ROWNUM<=30
]],'+',[[--grid:{topic='Other Pools Components'}
    SELECT * FROM (
        SELECT initcap(pool) pool,NVL(NAME,'--TOTAL--') name,SUM(BYTES) bytes
        FROM   GV$SGASTAT a
        WHERE  inst_id=nvl(:instance,userenv('instance'))
        AND    pool != 'shared pool'
        GROUP BY inst_id,pool,rollup(NAME) HAVING SUM(BYTES)>0
        ORDER BY bytes DESC,a.name desc)
    WHERE ROWNUM<=30]]
}