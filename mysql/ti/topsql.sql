/*[[List Top SQLs. Usage: @@NAME [<yymmddhh24mi> [<yymmddhh24mi>] | -f"<filter>" | -u]
    -f"<filter>": Customize the `WHERE` clause
    -u          : Only list the statements for current database
    --[[--
        &V1: default={&STARTTIME}
        &V2: default={&ENDTIME}
        &filter: {
            default={
                 summary_end_time BETWEEN
                    ifnull(str_to_date(NULLIF('&V1',''),'%y%m%d%H%i%s'),date_add(now(),interval -7 day)) AND
                    ifnull(str_to_date(NULLIF('&V2',''),'%y%m%d%H%i%s'),date_add(now(),interval 10 day))
            }

            f={}
            u={schema_name=database()}
        }
    --]]--
]]*/
COL "Total|Ela,Avg|Ela,Max|Ela,Avg|Parse,Avg|Compile,Avg|Process,Avg|Commit,Avg|Wait,Avg|Backoff" FOR USMHD2
SELECT concat(substr(digest,1,18),' ..') AS digest,
       DATE_FORMAT(MIN(summary_begin_time),'%m%d-%H:%i') first_seen,
       DATE_FORMAT(MAX(summary_end_time),'%m%d-%H:%i') last_seen,
       COUNT(1) `rows`,
       SUM(exec_count) AS execs,
       SUM(sum_latency)/1e3 AS `Total|Ela`,
       '|' `|`,
       MAX(max_latency)/1e3 AS `Max|Ela`,
       SUM(exec_count * avg_latency) / SUM(exec_count)/1e3 AS `Avg|Ela`,
       SUM(exec_count * avg_parse_latency) / SUM(exec_count)/1e3 `Avg|Parse`,
       SUM(exec_count * avg_compile_latency) / SUM(exec_count)/1e3 `Avg|Compile`,
       SUM(exec_count * avg_process_time) / SUM(exec_count)*1e6 `Avg|Process`,
       SUM(exec_count * avg_wait_time) / SUM(exec_count)*1e6 `Avg|Wait`,
       SUM(exec_count * avg_backoff_time) / SUM(exec_count)*1e6  `Avg|Backoff`,
       SUM(exec_count * avg_commit_time) / SUM(exec_count)*1e6 `Avg|Wait`,
       '|' `|`,
       any_value(schema_name) AS schema_name,
       COUNT(DISTINCT plan_digest) AS plans,
       any_value(substr(replace(replace(replace(replace(trim(digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150)) sql_text
FROM   information_schema.cluster_statements_summary_history
WHERE  &filter
GROUP  BY schema_name, digest
ORDER  BY `Total|Ela` DESC LIMIT 50