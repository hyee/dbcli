/*[[Show session info. Usage: @@NAME <sid> [inst_id] ]]*/

set pivot 10 feed off
set headstyle none
select * from gv$session where sid=:V1 and (:V2 is null or inst_id=:V2);

select * from gv$ses_optimizer_env where sid=:V1  and (:V2 is null or inst_id=:V2) ORDER BY 1,2,4;