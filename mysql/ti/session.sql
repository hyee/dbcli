/*[[Show process info. Usage: @@NAME <process_id>
    --[[
        @ARGS: 1
    --]]

]]*/

select * from PERFORMANCE_SCHEMA.SESSION_CONNECT_ATTRS where PROCESSLIST_ID=&v1;