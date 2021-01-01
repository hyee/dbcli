/*[[Show session info. Usage: @@NAME <sid> [inst_id] 
    --[[
        @ARGS: 1
    ]]--
]]*/

set pivot 10 feed off
set headstyle none
select * from gv$session where sid=:V1 and (:V2 is null or inst_id=:V2);

SELECT a.*, b.value system_value
FROM   gv$session c,gv$ses_optimizer_env a, gv$SYS_OPTIMIZER_ENV b
WHERE  a.inst_id = b.inst_id
AND    a.inst_id = c.inst_id
AND    a.sid     = c.sid
AND    a.id = b.id
AND    nvl(a.value, 'x') != nvl(b.value, 'x')
AND    c.sid = :V1
AND    (:V2 IS NULL OR c.inst_id = :V2)
ORDER  BY 1, 2, 4;