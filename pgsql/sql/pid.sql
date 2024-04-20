/*[[
    view/kill/cancel process with pid. Usage: @@NAME <pid> [-k|-c]

    defaults to only view the process by Id, plus below additional options:
        -k: terminal process by `pg_terminate_backend`
        -c: cancel   process by `pg_cancel_backend`
    
    --[[--
        &cmd: default={} k={select pg_terminate_backend(&v1);} c={select pg_cancel_backend(&v1);}
        @ALIAS: kill
        @CHECK_USER
    --]]--
]]*/
env COLWRAP 150
select *
       --,pg_stat_get_backend_wait_event_type(pid) wait_event_type,
       --,pg_stat_get_backend_wait_event(pid) wait_event 
from pg_stat_get_activity(&v1) \G

&cmd