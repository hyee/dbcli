/*[[Show top SQLs based on pg_stat_statements. Usage: @@NAME [<keyword> | -f"<filter>"] 
    --[[--
        @check_access_stmt: pg_stat_statements={1}
        &filter: default={lower(concat(queryid,'|',"user",'|',"db",'|',"query")) like lower('%&v1%')} f={}
    --]]--
]]*/
env autohide col
COL time,mean,min,max,blk_r_time,blk_w_time for usmhd2
COL calls,blks_hit,blks_dirty,blks_read,blks_write,tmp_read,tmp_write for tmb1
COL time% for pct1
SELECT queryid sql_id,
       calls,
       total_time*1e3 "time",
       round((total_time/sum(total_time) over())::numeric,3) "time%",
       '|' "|",
       mean_time*1e3 "mean",
       min_time*1e3 "min",
       max_time*1e3 "max",
       rows / GREATEST(calls, 1) "rows",
       nullif(round((shared_blks_hit+local_blks_hit)/ GREATEST(calls, 1),2),0) blks_hit,
       nullif(round((shared_blks_read+local_blks_read)/ GREATEST(calls, 1),2),0) blks_read,
       nullif(round((shared_blks_dirtied+local_blks_dirtied)/ GREATEST(calls, 1),2),0) blks_dirty,
       nullif(round((shared_blks_written+local_blks_written)/ GREATEST(calls, 1),2),0) blks_write,
       nullif(round((blk_read_time*1e3)::numeric/nullif(shared_blks_read+local_blks_read,0),2),0) blk_r_time,
       nullif(round((blk_write_time*1e3)::numeric/nullif(shared_blks_written+local_blks_written,0),2),0) blk_w_time,
       nullif(round(temp_blks_read/ GREATEST(calls, 1),2),0) tmp_read,
       nullif(round(temp_blks_written/ GREATEST(calls, 1),2),0) tmp_write,
       '|' "|",
       "user",
       "db",
       LTRIM(SUBSTR(regexp_replace(query, '\s+', ' ', 'g'), 1, 200)) short_sql_text
FROM   pg_stat_statements a
LEFT JOIN (select rolname "user",oid from pg_authid) au on a.userid=au.oid
LEFT JOIN (select datname "db",oid from pg_database) db on a.dbid=db.oid
WHERE &filter
ORDER  BY total_time desc limit 50;
