/*[[List Top SQLs. Usage: @@NAME {[<yymmddhh24mi> [<yymmddhh24mi>]}  | {-snap <secs>} | {-sql <digest>} | [-f"<filter>" | -u ] [-local] [-current]

    -sql <digest>: Only list the stats for the specific digest, as well as showing the sql text and execution plan     
    -snap <secs> : Only list the recent SQLs within <secs> seconds. Defaults to list the SQLs within 7 days.
    -f"<filter>" : Customize the `WHERE` clause
    -u           : Only list the SQLs for current database
    -current     : Only list the the SQLs exist in "[cluster_]statements_summary",otherwise use the *history view
    -local       : Only list the the SQLs exist in local instance

    Parameters:
        * tidb_enable_stmt_summary (default: 1)
        * tidb_stmt_summary_refresh_interval (default: 1800 secs)
        * tidb_stmt_summary_history_size (default: 24)
        * tidb_stmt_summary_max_stmt_count (default: 200)
        * tidb_stmt_summary_max_sql_length (default: 4096)
        * tidb_stmt_summary_internal_query (default: 0)
    
    --[[--
        &V1: default={&STARTTIME}
        &V2: default={&ENDTIME}
        &filter: {
            default={summary_end_time BETWEEN
                ifnull(str_to_date(NULLIF('&V1',''),'%y%m%d%H%i%s'),date_add(now(),interval -7 day)) AND
                ifnull(str_to_date(NULLIF('&V2',''),'%y%m%d%H%i%s'),date_add(now(),interval 10 day))}
            snap={summary_end_time>=date_add(now(), interval -&V1 second)}
            f={}
            u={schema_name=database()}
            sql={digest LIKE concat(:V1,'%')}
        }
        &grp : default={digest} sql={`# Hour`}
        &hour: default={concat(substr(digest,1,18),' ..')} sql={DATE_FORMAT(last_seen,'%m%d %H')}
        &tail: {
            default={any_value(substr(replace(replace(replace(replace(replace(replace(trim(digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),'` , ',','),'`',''),1,150)) sql_text}
            sql={any_value(concat(substr(plan_digest,1,18),' ..')) Plan_Digest}
        }
        &sort: default={`Total|Ela`} sql={&grp}
        &comment: default={} sql={--}
        &vw: default={_history} current={}
        &inst: default={cluster_} local={} 
    --]]--
]]*/
ENV FEED OFF AUTOHIDE COL
COL "Total|Ela,Avg|Ela,Max|Ela,Avg|Retry,Avg|Parse,Avg|Compile,Cop|Prox,Avg|Commit,Cop|Wait,2PC ->|PreWri,2PC ->|Commit,Avg|Backoff,Avg|Latch,Avg|Lock,Avg|TiKV,Avg|Cop,Avg|TiPD" FOR USMHD2
COL "Avg|Disk,Avg|RocksDB" for kmg2
COL "Avg|Keys,Avg|Rows,Execs,Retry" for tmb2
COL "Cache|Hit" for pct2

SELECT &hour &grp,
       IFNULL((SELECT MAX('Yes') FROM information_schema.&inst.slow_query s WHERE s.digest=h.digest),'') `Slow`,
       COUNT(DISTINCT plan_digest) AS `Plans`,
       DATE_FORMAT(MAX(last_seen),'%m%d-%H:%i') last_seen,
       COUNT(1) `Count`,
       SUM(exec_count) AS `Execs`,
       SUM(sum_exec_retry) AS `Retry`,
       '|' `|`,
       SUM(sum_latency)/1e3 AS `Total|Ela`,
       MAX(max_latency)/1e3 AS `Max|Ela`,
       SUM(sum_latency) / SUM(exec_count)/1e3 AS `Avg|Ela`,
       SUM(sum_exec_retry_time)/ SUM(exec_count)/1e3 AS `Avg|Retry`,
       '|' `|`,
       SUM(exec_count * avg_pd_time) / SUM(exec_count)/1e3  `Avg|TiPD`,
       SUM(exec_count * avg_parse_latency) / SUM(exec_count)/1e3 `Avg|Parse`,
       SUM(exec_count * avg_compile_latency) / SUM(exec_count)/1e3 `Avg|Compile`,
       '|' `|`,
       NULLIF(SUM(exec_count * (max_cop_wait_time+max_cop_process_time)) / SUM(exec_count)/1e3,0)  `Avg|Cop`,
       NULLIF(SUM(exec_count * avg_process_time) / SUM(exec_count)/1e3,0) `Cop|Prox`,
       NULLIF(SUM(exec_count * avg_wait_time) / SUM(exec_count)/1e3,0) `Cop|Wait`,
       '|' `|`,
       NULLIF(SUM(exec_count * avg_kv_time) / SUM(exec_count)/1e3,0)  `Avg|TiKV`,
       NULLIF(SUM(exec_count * avg_prewrite_time) / SUM(exec_count)/1e3,0) `2PC ->|PreWri`,
       NULLIF(SUM(exec_count * avg_commit_time) / SUM(exec_count)/1e3,0) `2PC ->|Commit`,
       NULLIF(ROUND(SUM(exec_count * avg_local_latch_wait_time) / SUM(exec_count)/1e3,2),0)  `Avg|Latch`,
       NULLIF(ROUND(SUM(exec_count * avg_resolve_lock_time) / SUM(exec_count)/1e3,2),0)  `Avg|Lock`,
       NULLIF(ROUND(SUM(exec_count * avg_backoff_total_time) / SUM(exec_count)/1e3,2),0)  `Avg|Backoff`,
       '|' `|`,
       NULLIF(ROUND(SUM(exec_count * avg_disk) / SUM(exec_count),2),0)  `Avg|Disk`,
       NULLIF(ROUND(SUM(exec_count * avg_rocksdb_block_read_byte) / SUM(exec_count),2),0)  `Avg|RocksDB`,
       SUM(exec_count * avg_rocksdb_block_cache_hit_count)/NULLIF(SUM(exec_count*(avg_rocksdb_block_cache_hit_count+avg_rocksdb_block_read_count)),0) `Cache|Hit`,
       NULLIF(ROUND(SUM(exec_count * avg_affected_rows) / SUM(exec_count),2),0)  `Avg|Rows`,
       NULLIF(SUM(exec_count * avg_total_keys) / SUM(exec_count),0)  `Avg|Keys`,
       '|' `|`,
       &tail
FROM   information_schema.&inst.statements_summary&vw h
WHERE  &filter
GROUP  BY &grp
HAVING SUM(exec_count)>0
ORDER  BY &sort DESC LIMIT 50;

&comment /*
col plan new_value plan noprint
env colwrap 150

SELECT digest_text `SQL Text`,plan
FROM   information_schema.&inst.statements_summary&vw
WHERE  &filter
ORDER  BY last_seen DESC LIMIT  1;

tiplan plan
&comment */