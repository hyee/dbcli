/*[[Show session info. Usage: session <sid> [inst_id] ]]*/

set pivot 10
set headstyle none
select * from gv$session where sid=:V1 and (:V2 is null or inst_id=:V2);

select * from gv$ses_optimizer_env where sid=:V1  and (:V2 is null or inst_id=:V2) ORDER BY 1,2,4;