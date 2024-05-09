/*[[
    Show SQL history stats. Usage: @@NAME <digest> [YYMMDDHH24MI [YYMMDDHH24MI]] [-d|-p]
    -d: group by day
    -p: group by plan digest

    --[[
        @ARGS: 1
        &grp1:  default={SUMMARY_END_TIME} d={DATE(SUMMARY_END_TIME)} p={MAX(SUMMARY_END_TIME)}
        &grp2:  default={SUMMARY_END_TIME} d={DATE(SUMMARY_END_TIME)} p={PLAN_DIGEST}
    --]]
]]*/
COL "Total|Ela,MAX|ELA,MIN|ELA,AVG|ELA" FOR NSMHD2
COL "PARSE|TIME,Compile|Time,Queue|Time,PD|Time,KV|Time,Retry|Time,2PC ->|PreWri,2PC ->|Commit,Process|Time,Wait|Time,Latch|Time,Backoff|Time,Cache|Hit" for pct2
COL "Scan|Rows,Process|Rows,Write|Rows,Affect|Rows,Read|RUs,Write|RUs,Avg|RocksDB" for tmb2
COL "AVG|Disk,Write|Disk" for kmg2
ENV AUTOHIDE COL
SELECT MAX(SUMMARY_END_TIME) END_TIME,
       concat(substr(PLAN_DIGEST,1,18),' ..') PLAN_DIGEST,
       NULLIF(sum(SUM_ERRORS),0) ERRS,
       NULLIF(sum(SUM_WARNINGS),0) WARNS,
       sum(SUM_LATENCY) `Total|Ela`,
       sum(EXEC_COUNT) `Total|Execs`,
       '|' `|`,
       MAX(MAX_LATENCY) `MAX|ELA`,
       MIN(MIN_LATENCY) `MIN|ELA`,
       SUM(SUM_LATENCY)/greatest(1,sum(EXEC_COUNT)) `AVG|ELA`,
       NULLIF(ROUND(SUM(AVG_PARSE_LATENCY*EXEC_COUNT)/sum(SUM_LATENCY),4),0) "Parse|Time",
       NULLIF(ROUND(SUM(AVG_COMPILE_LATENCY*EXEC_COUNT)/sum(SUM_LATENCY),4),0) "Compile|Time",
       NULLIF(ROUND(SUM(AVG_QUEUED_RC_TIME*EXEC_COUNT)/greatest(1,sum(EXEC_COUNT)),2),0) "Queue|Time",
       NULLIF(ROUND(SUM(AVG_KV_TIME*EXEC_COUNT)/sum(SUM_LATENCY),4),0) "PD|Time",
       NULLIF(ROUND(SUM(SUM_EXEC_RETRY_TIME)/sum(SUM_LATENCY),4),0) "Retry|Time",
       '|' `|`,
       NULLIF(ROUND(SUM(AVG_DISK*EXEC_COUNT)/greatest(1,sum(EXEC_COUNT)),2),0) `AVG|Disk`,
       NULLIF(ROUND(SUM(AVG_WRITE_SIZE*EXEC_COUNT)/greatest(1,sum(EXEC_COUNT)),2),0) `Write|Disk`,
       NULLIF(ROUND(SUM(AVG_REQUEST_UNIT_WRITE*EXEC_COUNT)/greatest(1,sum(EXEC_COUNT)),2),0) `Write|RUs`,
       NULLIF(ROUND(SUM(AVG_REQUEST_UNIT_Read*EXEC_COUNT)/greatest(1,sum(EXEC_COUNT)),2),0) `Read|RUs`,
       NULLIF(ROUND(SUM(exec_count * avg_rocksdb_block_read_byte) / SUM(exec_count),2),0)  `Avg|RocksDB`,
       SUM(exec_count * avg_rocksdb_block_cache_hit_count)/NULLIF(SUM(exec_count*(avg_rocksdb_block_cache_hit_count+avg_rocksdb_block_read_count)),0) `Cache|Hit`,
       '|' `|`,
       NULLIF(ROUND(SUM(SUM_COP_TASK_NUM)/greatest(1,sum(EXEC_COUNT)),2),0) `AVG|Tasks`,
       NULLIF(ROUND(SUM(exec_count * avg_prewrite_time) / SUM(exec_count),4),0) `2PC ->|PreWri`,
       NULLIF(ROUND(SUM(exec_count * avg_commit_time) / SUM(exec_count),4),0) `2PC ->|Commit`,
       NULLIF(ROUND(SUM(AVG_PROCESS_TIME*EXEC_COUNT)/sum(SUM_LATENCY),4),0) `Process|Time`,
       NULLIF(ROUND(SUM(AVG_WAIT_TIME*EXEC_COUNT)/sum(SUM_LATENCY),4),0) `Wait|Time`,
       NULLIF(ROUND(SUM(exec_count * avg_local_latch_wait_time) /sum(SUM_LATENCY),4),0)  `Latch|Time`,
       NULLIF(ROUND(SUM(exec_count * avg_resolve_lock_time) / sum(SUM_LATENCY),4),0)  `Lock|Time`,
       NULLIF(ROUND(SUM(SUM_BACKOFF_TIMES)/sum(SUM_LATENCY),4),0) "Backoff|Time",
       NULLIF(ROUND(SUM(AVG_TOTAL_KEYS*EXEC_COUNT)/sum(EXEC_COUNT),4),0) "Scan|Rows",
       NULLIF(ROUND(SUM(AVG_PROCESSED_KEYS*EXEC_COUNT)/sum(EXEC_COUNT),4),0) "Process|Rows",
       NULLIF(ROUND(SUM(AVG_WRITE_KEYS*EXEC_COUNT)/sum(EXEC_COUNT),4),0) "Write|Rows",
       NULLIF(ROUND(SUM(AVG_AFFECTED_ROWS*EXEC_COUNT)/sum(EXEC_COUNT),4),0) "Affect|Rows"
FROM   information_schema.cluster_statements_summary_history
WHERE  digest like concat(:V1,'%')
AND    summary_end_time BETWEEN
        ifnull(str_to_date(NULLIF('&V2',''),'%y%m%d%H%i%s'),date_add(now(),interval -7 day)) AND
        ifnull(str_to_date(NULLIF('&V3',''),'%y%m%d%H%i%s'),date_add(now(),interval 1 day))
GROUP BY &grp2,PLAN_DIGEST
ORDER BY 1 DESC LIMIT 300;