/*[[
    Show top SQLs based on dbe_perf.summary_statement. Usage: @@NAME [<keyword> | -f"<filter>" ] [-io|-avg|-buff|-call]
    
    <keyword>   : search sql_id/user/node/query to find the matched records
    -f"<filter>": valid `WHRER` clause to filter the data

    Sort options: default order by total time
        -io    : order by io requests
        -buff  : order by buffer hits
        -avg   : order by avg time
        -call  : order by calls

    --[[--
        @check_access_stmt: dbe_perf.summary_statement={1}
        &filter: default={lower(concat(unique_sql_id,'|',user_name,'|',node_name,'|',"query")) like lower('%&v1%')} f={}
        &ord: {
            default={"time"}
            call={calls}
            avg={"avg|time"}
            buff={n_blocks_hit}
            io={n_blocks_fetched-n_blocks_hit}
        }
    --]]--
]]*/
env autohide col
COL time,avg|time,min|time,max|time,read_time,write_time for usmhd2
COL calls,buffer|hit,buffer|misses,rows|returned,rows|accessed for tmb1
COL time% for pct1

SELECT unique_sql_id::text sql_id,
       n_calls calls,
       total_elapse_time "time",
       nullif(round((total_elapse_time/sum(total_elapse_time) over())::numeric,3),0) "time%",
       '|' "|",
       round(total_elapse_time/GREATEST(calls, 1)::numeric,2) "avg|time",
       min_elapse_time "min|time",
       max_elapse_time "max|time",
       nullif(round((n_returned_rows+n_tuples_inserted+n_tuples_updated+n_tuples_deleted)::numeric / GREATEST(calls, 1),2),0) "rows|returned",
       nullif(round((n_tuples_returned+n_tuples_fetched)::numeric / GREATEST(calls, 1),2),0) "rows|accessed",
       nullif(round(n_blocks_hit/ GREATEST(calls, 1),2),0) "buffer|hits",
       nullif(round((n_blocks_fetched-n_blocks_hit)/ GREATEST(calls, 1),2),0) "buffer|misses",
       '|' "|",
       user_name,
       node_name,
       LTRIM(SUBSTR(regexp_replace(query, '\s+', ' ', 'g'), 1, 200)) short_sql_text
FROM   dbe_perf.summary_statement a
WHERE &filter
ORDER  BY "time" desc nulls last limit 50;
