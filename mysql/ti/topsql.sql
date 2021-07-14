/*[[List Top SQLs. Usage: @@NAME {[<yymmddhh24mi> [<yymmddhh24mi>]} | {[-f"<filter>" | -snap <secs> | -u ]} [-local] [-current]
    -f"<filter>": Customize the `WHERE` clause
    -snap       : Only list the recent SQLs within <secs> seconds. Defaults to list the SQLs within 7 days.
    -u          : Only list the SQLs for current database
    -current    : Only list the the SQLs exist in "[cluster_]statements_summary",otherwise use the *history view
    -local      : Only list the the SQLs exist in local instance

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
            
        }
        &vw: default={_history} current={}
        &inst: default={cluster_} local={} 
    --]]--
]]*/
COL "Total|Ela,Avg|Ela,Max|Ela,Avg|Parse,Avg|Compile,Avg|Process,Avg|Commit,Avg|Wait,Avg|Commit,Avg|Backoff,Avg|TiKV,Avg|Cop,Avg|TiPD" FOR USMHD2
COL "Avg|Disk,Avg|RocksDB" for kmg2
COL "Avg|Keys" for tmb2

SELECT concat(substr(digest,1,18),' ..') AS digest,
       IFNULL((SELECT MAX('Yes') FROM information_schema.&inst.slow_query s WHERE s.digest=h.digest),'') `Slow`,
       COUNT(DISTINCT plan_digest) AS `Plans`,
       DATE_FORMAT(MAX(last_seen),'%m%d-%H:%i') last_seen,
       COUNT(1) `Count`,
       SUM(exec_count) AS `Execs`,
       '|' `|`,
       SUM(sum_latency)/1e3 AS `Total|Ela`,
       MAX(max_latency)/1e3 AS `Max|Ela`,
       SUM(exec_count * avg_latency) / SUM(exec_count)/1e3 AS `Avg|Ela`,
       '|' `|`,
       SUM(exec_count * avg_parse_latency) / SUM(exec_count)/1e3 `Avg|Parse`,
       SUM(exec_count * avg_compile_latency) / SUM(exec_count)/1e3 `Avg|Compile`,
       SUM(exec_count * avg_process_time) / SUM(exec_count)/1e3 `Avg|Process`,
       SUM(exec_count * avg_wait_time) / SUM(exec_count)/1e3 `Avg|Wait`,
       SUM(exec_count * max_cop_wait_time) / SUM(exec_count)/1e3  `Avg|Cop`,
       SUM(exec_count * avg_commit_time) / SUM(exec_count)/1e3 `Avg|Commit`,
       SUM(exec_count * avg_backoff_time) / SUM(exec_count)/1e3  `Avg|Backoff`,
       SUM(exec_count * avg_kv_time) / SUM(exec_count)/1e3  `Avg|TiKV`,
       SUM(exec_count * avg_pd_time) / SUM(exec_count)/1e3  `Avg|TiPD`,
       '|' `|`,
       SUM(exec_count * avg_disk) / SUM(exec_count)  `Avg|Disk`,
       SUM(exec_count * avg_rocksdb_block_read_byte) / SUM(exec_count)  `Avg|RocksDB`,
       SUM(exec_count * avg_total_keys) / SUM(exec_count)  `Avg|Keys`,
       '|' `|`,
       any_value(substr(replace(replace(replace(replace(trim(digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150)) sql_text
FROM   information_schema.&inst.statements_summary&vw h
WHERE  &filter
GROUP  BY digest
HAVING SUM(exec_count)>0
ORDER  BY `Total|Ela` DESC LIMIT 50