/*[[List Top SQLs. Usage: @@NAME [<yymmddhh24mi> [<yymmddhh24mi>] | -f"<filter>" | -u]
    -f"<filter>": Customize the `WHERE` clause
    -u          : Only list the statements for current user
    
    Parameters:
        * tidb_enable_slow_log (default: on)
        * tidb_slow_log_threshold (default: 300ms)
        * tidb_slow_query_file
        * tidb_expensive_query_time_threshold (default: 60s)
    --[[--
        &V1: default={&STARTTIME}
        &V2: default={&ENDTIME}
        &filter: {
            default={
                 Time BETWEEN
                    ifnull(str_to_date(NULLIF('&V1',''),'%y%m%d%H%i%s'),date_add(now(),interval -7 day)) AND
                    ifnull(str_to_date(NULLIF('&V2',''),'%y%m%d%H%i%s'),date_add(now(),interval 10 day))
            }

            f={}
            u={user() like concat(User,'@%')}
        }
    --]]--
]]*/
COL "Total|Ela,Avg|Ela,Avg|Retry,Avg|Parse,Avg|Compile,Avg|Optim,Avg|Commit,Avg|Wait" FOR USMHD2
SELECT concat(substr(digest,1,18),' ..') AS digest,
       DATE_FORMAT(MIN(Time),'%m%d-%H:%i') first_seen,
       DATE_FORMAT(MAX(Time),'%m%d-%H:%i') last_seen,
       COUNT(1) AS execs,
       SUM(Query_time)*1e6 AS `Total|Ela`,
       '|' `|`,
       AVG(Query_time)*1e6 `Avg|Ela`,
       AVG(Parse_time)*1e6 `Avg|Parse`,
       AVG(Compile_time)*1e6 `Avg|Compile`,
       AVG(Optimize_time)*1e6 `Avg|Optim`,
       AVG(Commit_time)*1e6 `Avg|Commit`,
       AVG(Wait_time)*1e6 `Avg|Wait`,
       AVG(Exec_retry_time)*1e6 `Avg|Retry`,
       '|' `|`,
       any_value(User) AS user,
       COUNT(DISTINCT plan_digest) AS plans,
       any_value(substr(replace(replace(replace(replace(trim(Query),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150)) sql_text
FROM   information_schema.cluster_slow_query
WHERE  &filter
GROUP  BY digest
ORDER  BY `Total|Ela` DESC LIMIT 50