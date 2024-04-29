/*[[
    Show top SQLs based on pg_stat_statements. Usage: @@NAME [<keyword> | -f"<filter>" ]  [-reset|-iotime|-io|-buff|-mean|-call]
    
    <keyword>   : search queryid/user/db/query to find the matched records
    -f"<filter>": valid `WHRER` clause to filter the data
    -reset      : run `pg_stat_statements_reset()`
    
    Sort options: default order by total_time
        -cpu    : order by non-io time
        -iotime : order by io time
        -io     : order by io requests
        -buff   : order by buffer hits
        -mean   : order by mean time
        -call   : order by calls

    Block Types:
        * Shared blocks: contain data from normal tables and indexes
        * Local  blocks: contain short-term data used to calculate hashes, sorts, materialize operations, and similar.
        * Temp   blocks: contain data from temporary tables and indexes

    Configs:
        *  shared_preload_libraries = 'pg_stat_statements' (in "postgresql.conf")
        *  create extention pg_stat_statements;
        *  pg_stat_statements.max  : Sets the maximum number of statements tracked by pg_stat_statements
           pg_stat_statements.save : Save pg_stat_statements statistics across server shutdowns.
           pg_stat_statements.track: top - track top-level statements (default value)
                                     all - top + nested statements(recursive SQLs)
    --[[--
        @check_access_stmt: pg_stat_statements={1}
        &filter: default={lower(concat(queryid,'|',"user",'|',"db",'|',"query")) like lower('%&v1%')} f={}
        &reset:  default={} reset={select pg_stat_statements_reset();}
        @time: 13={exec_} default={}
        @tmpr: 13={temp_blk_read_time::bigint} default={0::bigint}
        @tmpw: 13={temp_blk_write_time::bigint} default={0::bigint}
        &ord:  {
                default={time}
                call={calls},
                mean={"mean"},
                iotime={blk_read_time+blk_write_time+&tmpr+&tmpw}
                io={shared_blks_read+local_blks_read+shared_blks_written+local_blks_written+temp_blks_read+temp_blks_written}
                buff={shared_blks_hit+local_blks_hit+shared_blks_dirtied+local_blks_dirtied}
                cpu={total_&time.time-(blk_read_time+blk_write_time)}
            }

    --]]--
]]*/
env autohide col
COL time,mean,min,max,read_time,write_time,tmpr_time,tmpw_time for usmhd2
COL calls,hits,dirties,reads,writes,tmp_read,tmp_write,rows for tmb1
COL time% for pct1
&reset

SELECT queryid::text sql_id,
       calls,
       total_&time.time*1e3 "time",
       round((total_&time.time/sum(total_&time.time) over())::numeric,3) "time%",
       '|' "|",
       mean_&time.time*1e3 "mean",
       min_&time.time*1e3 "min",
       max_&time.time*1e3 "max",
       nullif(round(rows::numeric / GREATEST(calls, 1),2),0) "rows",
       nullif(round((shared_blks_hit+local_blks_hit) / GREATEST(calls, 1),2),0) hits,
       nullif(round((shared_blks_read+local_blks_read) / GREATEST(calls, 1),2),0) reads,
       nullif(round((shared_blks_dirtied+local_blks_dirtied) / GREATEST(calls, 1),2),0) dirties,
       nullif(round((shared_blks_written+local_blks_written) / GREATEST(calls, 1),2),0) writes,
       nullif(round((blk_read_time*1e3)::numeric / nullif(shared_blks_read+local_blks_read,0),2),0) read_time,
       nullif(round((blk_write_time*1e3)::numeric / nullif(shared_blks_written+local_blks_written,0),2),0) write_time,
       nullif(round(temp_blks_read / GREATEST(calls, 1),2),0) tmp_read,
       nullif(round(temp_blks_written/ GREATEST(calls, 1),2),0) tmp_write,
       nullif(round((&tmpr*1e3) / GREATEST(temp_blks_read, 1),2),0) tmpr_time,
       nullif(round((&tmpw*1e3) / GREATEST(temp_blks_written, 1),2),0) tmpw_time,
       '|' "|",
       "user",
       "db",
       LTRIM(SUBSTR(regexp_replace(query, '\s+', ' ', 'g'), 1, 200)) short_sql_text
FROM   pg_stat_statements a
LEFT JOIN (select datname "db",oid from pg_database) db on a.dbid=db.oid
WHERE &filter
ORDER  BY &ord desc nulls last limit 50;
