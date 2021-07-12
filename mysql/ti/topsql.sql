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
COL ela_total,ela_max,ela_min,ela_avg FOR USMHD2
SELECT concat(substr(digest,1,18),' ..') AS digest,
       DATE_FORMAT(MIN(summary_begin_time),'%m%d-%H:%i') first_seen,
       DATE_FORMAT(MAX(summary_end_time),'%m%d-%H:%i') last_seen,
       COUNT(1) `rows`,
       SUM(exec_count) AS execs,
       SUM(sum_latency)/1e3 AS ela_total,
       MAX(max_latency)/1e3 AS ela_max,
       MIN(min_latency)/1e3 AS ela_min,
       CAST(SUM(exec_count * avg_latency) / SUM(exec_count) AS signed)/1e3 AS ela_avg,
       any_value(schema_name) AS schema_name,
       -- any_value(table_names) AS table_names,
       COUNT(DISTINCT plan_digest) AS plans,
       any_value(substr(replace(replace(replace(replace(trim(digest_text),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150)) sql_text
FROM   information_schema.cluster_statements_summary_history
WHERE  &filter
GROUP  BY schema_name, digest
ORDER  BY ela_total DESC LIMIT 50