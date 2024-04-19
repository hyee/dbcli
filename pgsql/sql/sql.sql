/*[[
    get SQL text from pg_stat_statements/dbe_perf.summary_statement. Usage: @@NAME <queryid> 
    The maximum SQL text length in dbe_perf.summary_statement is only 1023
    --[[--
        @ARGS: 1
        @check_access_stmt: {
            pg_stat_statements={dbe_perf.summary_statement where queryid}
            dbe_perf.summary_statement={dbe_perf.summary_statement where unique_sql_id}
        }
    --]]--
]]*/
env feed off
col query new_value q noprint
SELECT * from &check_access_stmt =:V1::bigint\G
print q
echo  --------------------------------------------------
save q sql_&v1..txt