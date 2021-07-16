/*[[List SQL stats for a specifc digest. Usage: @@NAME <partial digest> {[-f"<filter>" | -snap <secs>} [-local] [-current]
    -f"<filter>": Customize the `WHERE` clause
    -snap       : Only list the recent SQLs within <secs> seconds. Defaults to list the SQLs within 7 days.
    -current    : Only list the the SQLs exist in "[cluster_]statements_summary",otherwise use the *history view
    -local      : Only list the the SQLs exist in local instance

    --[[--
        &filter: default={1=1} snap={summary_end_time>=date_add(now(), interval -&V1 second)} f={}
        &vw    : default={_history} current={}
        &inst  : default={cluster_} local={}
    --]]--
]]*/

COL "Total|Ela,Avg|Ela,Max|Ela,Avg|Parse,Avg|Compile,Avg|Process,2PC -|PreWr,2PC -|Commit,Avg|Wait,Avg|Commit,Avg|Retry,Avg|Backoff,Avg|TiKV,Avg|CopProx,Avg|CopWait,Avg|TiPD" FOR USMHD2
COL "Avg|Disk,Avg|RocksDB,Avg|Writ,Avg|Mem" for kmg2
COL "Avg|Keys" for tmb2

SELECT DATE_FORMAT(summary_end_time,'%m%d %H')  `# Hour`,
       DATE_FORMAT(MAX(last_seen),'%m%d-%H:%i:%s') last_seen,
       SUM(exec_count) `Execs`,
       SUM(sum_errors) `Errs`,
       SUM(sum_warnings) `Warns`,
       SUM(sum_exec_retry) `Retry`,
       '|' `|`,
       SUM(sum_latency)/1e3 `Total|Ela`,
       MAX(max_latency)/1e3 `Max|Ela`,
       SUM(exec_count * avg_latency) / SUM(exec_count)/1e3 `Avg|Ela`,
       '|' `|`,
       SUM(exec_count * avg_parse_latency) / SUM(exec_count)/1e3 `Avg|Parse`,
       SUM(exec_count * avg_compile_latency) / SUM(exec_count)/1e3 `Avg|Compile`,
       SUM(exec_count * avg_process_time) / SUM(exec_count)/1e3 `Avg|Process`,
       SUM(exec_count * avg_wait_time) / SUM(exec_count)/1e3 `Avg|Wait`,
       SUM(exec_count * max_cop_process_time) / SUM(exec_count)/1e3  `Avg|CopProx`,
       SUM(exec_count * max_cop_wait_time) / SUM(exec_count)/1e3  `Avg|CopWait`,
       SUM(exec_count * avg_prewrite_time) / SUM(exec_count)/1e3 `2PC -|PreWr`,
       SUM(exec_count * avg_commit_time) / SUM(exec_count)/1e3 `2PC -|Commit`,
       SUM(exec_count * avg_backoff_total_time) / SUM(exec_count)/1e3  `Avg|Backoff`,
       SUM(exec_count * avg_kv_time) / SUM(exec_count)/1e3  `Avg|TiKV`,
       SUM(exec_count * avg_pd_time) / SUM(exec_count)/1e3  `Avg|TiPD`,
       SUM(exec_count * sum_exec_retry_time) / SUM(exec_count)/1e3  `Avg|Retry`,
       '|' `|`,
       ROUND(SUM(sum_cop_task_num) / SUM(exec_count),1) `Avg|Cops`,
       SUM(exec_count * avg_total_keys) / SUM(exec_count)  `Avg|Keys`,
       SUM(exec_count * avg_mem) / SUM(exec_count)  `Avg|Mem`,
       SUM(exec_count * avg_disk) / SUM(exec_count)  `Avg|Disk`,
       SUM(exec_count * avg_rocksdb_block_read_byte) / SUM(exec_count)  `Avg|RocksDB`,
       SUM(exec_count * avg_write_size) / SUM(exec_count)  `Avg|Writ`
FROM   information_schema.&inst.statements_summary&vw h
WHERE  digest LIKE CONCAT(:V1,'%')
GROUP  BY `# Hour`
HAVING SUM(exec_count)>0
ORDER  BY 1 DESC LIMIT 100;