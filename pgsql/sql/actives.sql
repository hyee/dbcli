/*[[Show active sessions. Usage: @@NAME [-f"<filter>"]
    --[[
        &filter: default={state <> 'idle' and pid <> pg_backend_pid()} f={}
        @CHECK_USER_GAUSS: gaussdb={waiting,unique_sql_id sql_id,} default={pg_blocking_pids(pid) AS blocked_by,}
    --]]
]]*/
col query_time for usmhd2
SELECT pid,
       usename          AS "username",
       application_name,
       client_addr      AS client_address,
       datname          AS database_name,
       state,
       &CHECK_USER_GAUSS
       EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - query_start))*1e6 query_time ,
       substr(regexp_replace(a.query,'\s+',' ','g'),1,200) short_sql_text
FROM   pg_stat_activity a
WHERE  &filter
ORDER BY state, pid;
