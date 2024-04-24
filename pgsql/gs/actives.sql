/*[[Show active sessions from pg_thread_wait_status. Usage: @@NAME [-f"<filter>"]
    --[[
        &filter: default={s.wait_status!='none'} f={}
        
    --]]
]]*/
col dur,block_time,txn_time for usmhd2
env autohide on

SELECT r.pid, s.db_name,r.username,r.queryid sql_id,s.wait_event,
       nullif(r.block_time*1e3,0) block_time,s.block_sessionid block_pid,
       duration*1e3 dur,
       ltrim(substr(regexp_replace(r.query,'\s+',' ','g'),1,200)) short_sql_text
FROM   pg_thread_wait_status s
right join   dbe_perf.statement_complex_runtime r
ON     s.sessionid=r.pid
WHERE  (1=1);