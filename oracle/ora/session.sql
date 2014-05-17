/*[[Show session info. Usage: session <sid>]]*/

set pivot 10
set headstyle none
select * from gv$session where sid=:V1