/*[[Show active sessions  Usage: as]]*/

select sid, substr(program,1,19) prog, address, hash_value, b.sql_id, child_number child, plan_hash_value, executions execs,
(elapsed_time/decode(nvl(executions,0),0,1,executions))/1000000 avg_etime,
substr(sql_text,1,100) sql_text
from v$session a, v$sql b
where status = 'ACTIVE'
and username is not null
and a.sql_id = b.sql_id
and a.sql_child_number = b.child_number
and sql_text not like 'select sid, substr(program,1,19) prog, address, hash_value, b.sql_id, child_number child,%' -- don't show this query
order by sql_id, sql_child_number;
