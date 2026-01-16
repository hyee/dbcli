/*[[
    Compare SQL by difference snapshot ranges. Usage: type `help @@NAME` for more details.
    * @@NAME [<yymmddhh24mi> [<yymmddhh24mi>]]: compare between awr snapshots and delta stats of gv$sqlstats
    * @@NAME -awr <yymmddhh24mi> <yymmddhh24mi> [<yymmddhh24mi>]: compare between snapshot ranges

    Compare groups:
    ===============
    -m  : default, group by force_matching_signature
    -sql: group by SQL ID
    
    Filter diff:
    ============
    -regress           : only list the regress SQLs
    -improve           : only list the improve SQLs
    -adj["<op><diff>"] : filter the avg_diff. i.e.: adj">=2"

    Other options:
    ==============
    -f"<filter>"       : additional filter on dba_hist_sqlstat/gv$sqstat
    -same              : exclude same plans that exists in both `PRE` and `POST`
    
    --[[
            &snap:   dg={2} awr={1}
            &diff:   default={=avg_diff} regress={>=1.2} improve={<=0.8} adj={}
            &filter: default={1=1} f={}
            &sql:    m={signature} sql={signature,sql_id}
            &same:   default={1=1} same={plans=1 or grp='PRE'}
    --]]--
]]*/

col Weight,avg_diff for pct3 break
col avg_ela,cpu_time,io_time for usmhd2
col buff,reads,writes,dxwrites,execs for tmb2
col io,offload_in,offload_out for kmg2
col hv,sig_weight,plans,grps,all_ela,all_execs noprint
col signature break
set autohide col

WITH r AS(
        SELECT  /*+opt_param('_fix_control' '26552730:0') 
                   opt_param('_no_or_expansion' 'true') 
                   opt_param('_optimizer_cbqt_or_expansion' 'off')*/
                signature,
                grp,
                MAX(sql_id) keep(dense_rank LAST ORDER BY ela * log(10, execs)) sql_id,
                plan_hash,
                count(distinct sql_id) sqls,
                SUM(execs) execs,
                '|' "|",
                ROUND(SUM(ela) / SUM(execs),2) avg_ela,
                ROUND(SUM(cpu_time) / SUM(execs),2) cpu_time,
                ROUND(SUM(io_time) / SUM(execs),2) io_time,
                ROUND(SUM(buff) / SUM(execs),2) buff,
                nullif(ROUND(SUM(reads) / SUM(execs),2),0) reads,
                nullif(ROUND(SUM(writes) / SUM(execs),2),0) writes,
                nullif(ROUND(SUM(dxwrites) / SUM(execs),2),0) dxwrites,
                nullif(ROUND(SUM(io) / SUM(execs),2),0) io,
                nullif(ROUND(SUM(offload_in) / SUM(execs),2),0) offload_in,
                nullif(ROUND(SUM(offload_out) / SUM(execs),2),0) offload_out
        FROM   (SELECT  /*+outline_leaf use_hash(s)*/
                        DECODE(SIGN(end_interval_time+0-nvl(to_date(nvl('&v2','&enddate'),'yymmddhh24miss'),sysdate)),-1,'PRE','POST') grp,
                        plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        SUM(elapsed_time_delta) ela,
                        SUM(executions_delta) execs,
                        SUM(cpu_time_delta) cpu_time,
                        SUM(iowait_delta) io_time,
                        SUM(buffer_gets_delta) buff,
                        SUM(physical_read_requests_delta) reads,
                        SUM(physical_write_requests_delta) writes,
                        SUM(direct_writes_delta) dxwrites,
                        SUM(io_interconnect_bytes_delta) io,
                        SUM(io_offload_elig_bytes_delta) offload_in,
                        SUM(io_offload_return_bytes_delta) offload_out
                FROM   dba_hist_sqlstat s
                JOIN   dba_hist_snapshot USING(dbid,snap_id,instance_number)
                WHERE  plan_hash_value > 0
                AND   (&snap=1 OR dbid=:dbid)
                AND   (&filter)
                AND   (:instance is null or instance_number=0+:instance)
                AND    end_interval_time >= nvl(to_date(nvl('&v1','&starttime'),'yymmddhh24miss'),sysdate - 3)
                AND    end_interval_time <= nvl(to_date(nvl(decode(&snap,1,'&v3','&v2'),'&endtime'),'yymmddhh24miss'),sysdate)
                GROUP  BY plan_hash_value, sql_id, force_matching_signature,
                          DECODE(SIGN(end_interval_time+0-nvl(to_date(nvl('&v2','&enddate'),'yymmddhh24miss'),sysdate)),-1,'PRE','POST')
                HAVING SUM(executions_delta) > 1)
        GROUP  BY grp,plan_hash,&sql
        UNION ALL
        SELECT  signature,
                'POST',
                MAX(sql_id) keep(dense_rank LAST ORDER BY ela * log(10, execs)) sql_id,
                plan_hash,
                count(distinct sql_id) sqls,
                SUM(execs) execs,
                '|' "|",
                round(SUM(ela) / SUM(execs),2) ela,
                round(SUM(cpu_time) / SUM(execs),2) cpu_time,
                round(SUM(io_time) / SUM(execs),2) io_time,
                round(SUM(buff) / SUM(execs),2) buff,
                nullif(ROUND(SUM(reads) / SUM(execs),2),0) reads,
                nullif(ROUND(SUM(writes) / SUM(execs),2),0) writes,
                nullif(ROUND(SUM(dxwrites) / SUM(execs),2),0) dxwrites,
                nullif(ROUND(SUM(io) / SUM(execs),2),0) io,
                nullif(ROUND(SUM(offload_in) / SUM(execs),2),0) offload_in,
                nullif(ROUND(SUM(offload_out) / SUM(execs),2),0) offload_out
        FROM   (SELECT  plan_hash_value plan_hash,
                        sql_id,
                        nvl(nullif(force_matching_signature,0),plan_hash_value) signature,
                        SUM(delta_elapsed_time) ela,
                        SUM(delta_execution_count) execs,
                        SUM(delta_cpu_time) cpu_time,
                        SUM(delta_user_io_wait_time) io_time,
                        SUM(delta_buffer_gets) buff,
                        SUM(delta_physical_read_requests) reads,
                        SUM(delta_physical_write_requests) writes,
                        SUM(delta_direct_writes) dxwrites,
                        SUM(delta_io_interconnect_bytes) io,
                        SUM(delta_cell_offload_elig_bytes) offload_in,
                        SUM(io_cell_offload_returned_bytes) offload_out
                FROM   gv$sqlstats
                WHERE  &snap = 2
                AND   (select dbid from v$database)=:dbid
                AND   (&filter)
                AND   (:instance is null or inst_id=0+:instance)
                AND    plan_hash_value > 0
                GROUP  BY plan_hash_value, sql_id, force_matching_signature
                HAVING SUM(delta_execution_count) > 1)
        GROUP  BY plan_hash,&sql
),
r1 AS(
    SELECT sum(decode(grp,'POST',all_ela/all_execs))  over(partition by &sql)/
           sum(decode(grp,'PRE',all_ela/all_execs)) over(partition by &sql) avg_diff,
           a.*,
           SYS_OP_COMBINED_HASH(&sql) hv,
           max(decode(grp,'POST',avg_ela*execs)) over(PARTITION BY &sql)/2 sig_weight
    FROM (SELECT r.*,
                 SUM(execs*avg_ela) over(partition by &sql,grp) all_ela,
                 SUM(execs) over(partition by &sql,grp) all_execs,
                 COUNT(distinct grp) OVER(PARTITION BY &sql) grps,
                 count(distinct grp) over(partition by plan_hash) plans 
          FROM   r) a
    WHERE grps>1 and (&same)
)
SELECT * FROM (
    SELECT ratio_to_report(sig_weight) over() "Weight",
    r1.*,'||' "||",
    trim(to_char(substr(regexp_replace(sql_text,'\s+',' '),1,300))) sql_text
    FROM r1 LEFT JOIN dba_hist_sqltext s
    ON (s.dbid=:dbid AND r1.sql_id=s.sql_id)
    WHERE (avg_diff &diff)
    ORDER by "Weight" desc,avg_diff,hv,grp desc,avg_ela*execs desc)
WHERE rownum<=300;