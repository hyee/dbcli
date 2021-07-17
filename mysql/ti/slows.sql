/*[[List Top SQLs. Usage: @@NAME [{<yymmddhh24mi> [<yymmddhh24mi>}  | {-snap <secs>} | {-sql <digest>} | -f"<filter>" | -u ] [-local]
    -snap       : Only list the recent SQLs within <secs> seconds. Defaults to list the SQLs within 7 days.
    -f"<filter>": Customize the `WHERE` clause
    -u          : Only list the statements for current user
    -local      : Only list the the SQLs exist in local instance

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
            snap={time>=date_add(now(), interval -&V1 second)}
            sql={digest LIKE concat(:V1,'%')}
            f={}
            u={user() like concat(User,'@%')}
        }
        &grp : default={digest} sql={`# Hour`}
        &hour: default={concat(substr(digest,1,18),' ..')} sql={DATE_FORMAT(Time,'%m%d %H')}
        &tail: {
            default={any_value(substr(replace(replace(replace(replace(replace(replace(trim(query),'\n',' '),' ','<>'),'><',''),'<>',' '),'` , ',','),'`',''),1,150)) sql_text}
            sql={any_value(concat(substr(plan_digest,1,18),' ..')) Plan_Digest}
        }
        &sort: default={`Total|Ela`} sql={&grp}
        &comment: default={} sql={--}
        &inst: default={cluster_} local={}

    --]]--
]]*/
ENV FEED OFF AUTOHIDE COL
COL "Total|Ela,Avg|Ela,Avg|Retry,Avg|Backoff,Avg|TiKV,Avg|TiPD,Avg|Parse,Avg|Compile,Avg|ReWrite,Sub|Query,Avg|Optim,2PC ->|PreWri,2PC ->|Commit,Cop|Time,Cop|Prox,Cop|Wait" FOR USMHD2
COL "Write|Size,Mem|Max,Disk|Max" FOR KMG2
COL "Write_Keys,Cop|Keys,Cop|Tasks,execs,retry" FOR TMB2

SELECT &hour &grp,
       DATE_FORMAT(MIN(Time),'%m%d-%H:%i') first_seen,
       DATE_FORMAT(MAX(Time),'%m%d-%H:%i') last_seen,
       COUNT(1) AS execs,
       SUM(Exec_retry_count) as retry,
       '|' `|`,
       SUM(Query_time)*1e6 AS `Total|Ela`,
       AVG(Query_time)*1e6 `Avg|Ela`,
       NULLIF(AVG(Exec_retry_time)*1e6,0) `Avg|Retry`,
       NULLIF(AVG(Backoff_total)*1e6,0) `Avg|Backoff`,
       AVG(Parse_time)*1e6 `Avg|Parse`,
       '|' `|`,
       AVG(Compile_time)*1e6 `Avg|Compile`,
       AVG(Rewrite_time)*1e6 `Avg|ReWrite`,
       NULLIF(AVG(Preproc_subqueries_time)*1e6,0) `Sub|Query`,
       NULLIF(AVG(Optimize_time)*1e6,0) `Avg|Optim`,
       '|' `|`,
       AVG(PD_total)*1e6 `Avg|TiPD`,
       NULLIF(AVG(Prewrite_time)*1e6,0) `2PC ->|PreWri`,
       NULLIF(AVG(Commit_time)*1e6,0) `2PC ->|Commit`,
       NULLIF(AVG(Write_Keys),0) `Write|Keys`,
       NULLIF(AVG(Write_size),0) `Write|Size`,
       NULLIF(AVG(Prewrite_region),0) 'PreWri|Region',
       '|' `|`,
       AVG(KV_total)*1e6 `Avg|TiKV`,
       AVG(Cop_time)*1e6 `Cop|Time`,
       NULLIF(AVG(Process_time)*1e6,0) `Cop|Prox`,
       NULLIF(AVG(Wait_time)*1e6,0) `Cop|Wait`,
       NULLIF(AVG(Request_count),0) `Cop|Tasks`,
       NULLIF(AVG(Total_keys),0) `Cop|Keys`,
       '|' `|`,
       AVG(Mem_max) `Mem|Max`,
       NULLIF(AVG(Disk_Max),0) `Disk|Max`,
       '|' `|`,
       any_value(User) AS user,
       --COUNT(DISTINCT plan_digest) AS plans,
       &tail
FROM   information_schema.&inst.slow_query
WHERE  (&filter)
GROUP  BY &grp
ORDER  BY &sort DESC LIMIT 50;

&comment /*
col plan new_value plan noprint
env colwrap 150

SELECT Query `SQL Text`,plan
FROM   information_schema.&inst.slow_query
WHERE  &filter
ORDER  BY Time DESC LIMIT  1;

tiplan plan
&comment */