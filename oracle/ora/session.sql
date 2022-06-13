/*[[Show session info. Usage: @@NAME <sid> [inst_id] 
    --[[
        @ARGS: 1
    ]]--
]]*/

set pivot 30 pivotsort head feed off
set headstyle none
pro GV$SESSION_CONNECT_INFO
PRO =======================
select distinct * from GV$SESSION_CONNECT_INFO 
where sid=:V1 and (:V2 is null or inst_id=:V2);

pro GV$SESSION
PRO ==========
set pivot 30 pivotsort head
select * 
from gv$session 
where sid=:V1 and (:V2 is null or inst_id=:V2) 
order by inst_id;

pro GV$SES_OPTIMIZER_ENV
PRO ====================
SELECT a.*, b.value system_value
FROM   gv$session c,gv$ses_optimizer_env a, gv$SYS_OPTIMIZER_ENV b
WHERE  a.inst_id = b.inst_id
AND    a.inst_id = c.inst_id
AND    a.sid     = c.sid
AND    a.id = b.id
AND    nvl(a.value, 'x') != nvl(b.value, 'x')
AND    c.sid = :V1
AND    (:V2 IS NULL OR c.inst_id = :V2)
ORDER  BY 1,  4;

col CPU_USED for usmhd2
col PGA_USED_MEM,PGA_ALLOC_MEM,PGA_FREEABLE_MEM,PGA_MAX_MEM FOR KMG
set pivot 30 pivotsort head
pro GV$PROCESS
PRO ====================
select * 
from  gv$process 
where (inst_id,addr) in (select inst_id,paddr from gv$session where sid=:V1 and (:V2 is null or inst_id=:V2))
order by inst_id;