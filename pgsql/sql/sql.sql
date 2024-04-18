/*[[get SQL text from pg_stat_statements. Usage: @@NAME <queryid> 
    --[[--
        @ARGS: 1
        @check_access_stmt: pg_stat_statements={1}
    --]]--
]]*/
env feed off
col query new_value q
SELECT query from pg_stat_statements where queryid=:V1::bigint;

save q &v1..txt