/*[[Show active sessions from pg_thread_wait_status. Usage: @@NAME [-f"<filter>"]
    --[[
        &filter: default={wait_status!='none'} f={}
        
    --]]
]]*/
col query_time,txn_time for usmhd2


SELECT  *
FROM   pg_thread_wait_status
WHERE  &filter;