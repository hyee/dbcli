/*[[
   Lists SQL Statements with Elapsed Time per Execution changing over time. Usage: @@NAME {[YYMMDDHH24MI] [YYMMDDHH24MI]} [-m]
   Author:      Carlos Sierra
   Version:     Modified version based on V2014/10/31
   Usage:       Lists statements that have changed their elapsed time per execution over
                some history.
                Uses the ration between "elapsed time per execution" and the median of
                this metric for SQL statements within the sampled history, and using
                linear regression identifies those that have changed the most. In other
                words where the slope of the linear regression is larger. Positive slopes
                are considered "improving" while negative are "regressing".

   Notes:       Developed and tested on 11.2.0.3.

                Requires an Oracle Diagnostics Pack License since AWR data is accessed.

                To further investigate poorly performing SQL use sqltxplain.sql or sqlhc
                (or planx.sql or sqlmon.sql or sqlash.sql).
    --[[
        &BASE : s={sql_id}, m={signature},
        &SIG  : s={},m={signature,}
        &FILTER: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
    --]]

]]*/

DEF min_slope_threshold='0.1';
DEF max_num_rows='50';

PRO SQL Statements with "Elapsed Time per Execution" changing over time
ORA _sqlstat
WITH per_time AS (
select /*+materialize*/ * from(
    SELECT max(sql_id) keep(dense_rank last order by snap) sql_id,&SIG
           grouping_id(plan_hash_value) grp,
           SYSDATE - max(end_time) days_ago,
           count(distinct nullif(plan_hash_value,0)) over(partition by &BASE) plans,
           min(begin_time) min_seen,
           max(end_time) max_seen,
           SUM(executions) execs,
           count(distinct trunc(end_time)) over() total_days,
           count(distinct snap_id) over() total_slots,
           SUM(elapsed_time)/ greatest(SUM(decode(executions,0,parse_calls,executions)),1) time_per_exec
    FROM (SELECT s.*,
                 nvl(MIN(decode(executions,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
                 MAX(decode(parse_calls,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap
          FROM  &awr$sqlstat s
          WHERE end_time BETWEEN NVL(TO_DATE(nvl(:V1,:starttime),'YYMMDDHH24MI'),SYSDATE-31) AND NVL(TO_DATE(nvl(:V2,:endtime),'YYMMDDHH24MI'),SYSDATE)
          AND   (:instance is null or instance_number=:instance)
          AND   &filter)
    GROUP BY grouping sets((&BASE,snap),(&BASE,snap,plan_hash_value,snap_id,trunc(end_time)))
    ) where grp=1
),
avg_time AS (
SELECT sql_id,&SIG
       sum(execs) execs,
       min(min_seen) min_seen,
       max(max_seen) max_seen,
       max(plans) plans,
       100*count(1)/max(total_slots) ratio,
       MEDIAN(time_per_exec) med_time_per_exec,
       STDDEV(time_per_exec) std_time_per_exec,
       AVG(time_per_exec)    avg_time_per_exec,
       MIN(time_per_exec)    min_time_per_exec,
       MAX(time_per_exec)    max_time_per_exec
  FROM per_time
 GROUP BY sql_id,&SIG total_days
HAVING COUNT(*) >= greatest(2,total_days)
   AND MAX(days_ago) - MIN(days_ago) >= total_days/4
   AND MEDIAN(time_per_exec) > 0.01
),
time_over_median AS (
SELECT h.days_ago,
       (h.time_per_exec / a.med_time_per_exec) time_per_exec_over_med,
       a.*
  FROM per_time h, avg_time a
 WHERE a.sql_id = h.sql_id
),
ranked AS (
SELECT RANK () OVER (ORDER BY ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) DESC) rank_num,
       t.sql_id,&SIG
       CASE WHEN REGR_SLOPE(t.time_per_exec_over_med, t.days_ago) > 0 THEN 'IMPROVING' ELSE 'REGRESSING' END change,
       ROUND(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago), 3) slope,
       ROUND(AVG(t.med_time_per_exec), 3) med_secs_per_exec,
       ROUND(AVG(t.std_time_per_exec), 3) std_secs_per_exec,
       ROUND(AVG(t.avg_time_per_exec), 3) avg_secs_per_exec,
       ROUND(MIN(t.min_time_per_exec), 3) min_secs_per_exec,
       ROUND(MAX(t.max_time_per_exec), 3) max_secs_per_exec,
       max(execs) execs,
       max(plans) plans,
       max(ratio) ratio,
       TO_CHAR(min(min_seen) ,'MM-DD"|"HH24:MI') min_seen,
       TO_CHAR(max(max_seen) ,'MM-DD"|"HH24:MI') max_seen
  FROM time_over_median t
 GROUP BY &SIG t.sql_id
 HAVING ABS(REGR_SLOPE(t.time_per_exec_over_med, t.days_ago)) > &&min_slope_threshold
)
SELECT r.sql_id,&SIG
       r.change,
       TO_CHAR(r.slope, '990.000MI') slope,
       execs, round(ratio,2) "Slots|(%)",
       plans,
       TO_CHAR(r.med_secs_per_exec, '999,990.00') "Median Secs|Per Exec",
       TO_CHAR(r.std_secs_per_exec, '999,990.00') "Std Dev Secs|Per Exec",
       TO_CHAR(r.avg_secs_per_exec, '999,990.00') "Avg Secs|Per Exec",
       TO_CHAR(r.min_secs_per_exec, '999,990.00') "Min Secs|Per Exec",
       TO_CHAR(r.max_secs_per_exec, '999,990.00') "Max Secs|Per Exec",
       min_seen "First_Seen",max_seen "Last_Seen",
       REPLACE((SELECT substr(regexp_replace(REPLACE(sql_text, chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' '),1,150) FROM dba_hist_sqltext s WHERE s.sql_id = r.sql_id and rownum<2), CHR(10)) sql_text
  FROM ranked r
 WHERE r.rank_num <= &&max_num_rows
 ORDER BY r.rank_num;