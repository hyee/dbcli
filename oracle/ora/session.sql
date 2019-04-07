/*[[Show session info. Usage: @@NAME <sid> [inst_id] 
    --[[
        @ARGS: 1
    ]]--
]]*/

set pivot 10 feed off
set headstyle none
select * from gv$session where sid=:V1 and (:V2 is null or inst_id=:V2);

select a.*,b.value system_value from gv$ses_optimizer_env a,gv$SYS_OPTIMIZER_ENV b
where  a.inst_id=b.inst_id(+) and a.id=b.id(+) and nvl(a.value,'x')!=nvl(b.value,'x')
and    sid=:V1  and (:V2 is null or a.inst_id=:V2) ORDER BY 1,2,4;