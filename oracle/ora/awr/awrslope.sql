/*[[
    Lists SQL Statements with Elapsed Time per Execution changing over time. Usage: @@NAME {[YYMMDDHH24MI] [YYMMDDHH24MI]} [-m] [-regress|-improve] [-f"<filter>"]
    
    -regress: order by regression
    -improve: order by improvement
    --[[
        &BASE : s={sql_id}, m={signature},
        &SIG  : s={},m={signature,}
        &FILTER: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &ORD   : default={"Total SQL ms" desc} improve={"Diff%"} regress={"Diff%" desc}
    --]]

]]*/

DEF min_slope_threshold='0.1';
ORA _sqlstat
COL "Median|Per Exec,Std Dev|Per Exec,Avg|Per Exec,Min|Per Exec,Max|Per Exec,AVG ELA" for usmhd2
col "Weight%,Diff%" for pct2
COL "Total SQL ms" NOPRINT
col "execs,buff gets" for tmb2
col sql_id break

WITH src AS
(SELECT a.*,
       COUNT(DISTINCT phf) OVER(PARTITION BY dbid,sql_id) phfs,
       COUNT(distinct flag) OVER(PARTITION BY dbid,sql_id) flags,
       SUM(decode(flag,1,ela)) over(partition by sql_id,dbid) * SUM(decode(flag,0,exe)) over(partition by sql_id,dbid)  
           /nullif(SUM(decode(flag,0,ela)) over(partition by sql_id,dbid)*SUM(decode(flag,1,exe)) over(partition by sql_id,dbid),0) diff
 FROM(SELECT coalesce(
                 extractvalue(dbms_xmlgen.getxmltype(q'~
                        select nullif(to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1)),'0') phf
                        from  dba_hist_sql_plan b
                        where b.sql_id='~'||a.sql_id||'''
                        and   b.dbid=' || a.dbid || '
                        and   b.plan_hash_value=' || a.plan_hash || '
                        and   b.other_xml is not null
                        and   rownum<2'),
                        '/ROWSET/ROW/PHF') + 0,
                 a.plan_hash) phf,
             a.*
      FROM   (SELECT dbid,
                     CASE WHEN end_time >= NVL(TO_DATE(nvl(:V1,:starttime),'YYMMDDHH24MI'),SYSDATE-3) THEN 1 ELSE 0 END flag,
                     MAX(SQL_id) keep(dense_rank last order by elapsed_time) sql_id,
                     plan_hash_value plan_hash,
                     to_char(MIN(begin_interval_time), 'YYMMDD HH24:MI') first_seen,
                     to_char(MAX(end_interval_time), 'YYMMDD HH24:MI') last_seen,
                     SUM(elapsed_time) ela,
                     SUM(executions) exe,
                     SUM(cpu_time) CPU,
                     SUM(iowait) iowait,
                     SUM(clwait) clwait,
                     SUM(apwait) apwait,
                     SUM(ccwait) ccwait,
                     SUM(plsexec_time) plsexec_time,
                     SUM(javexec_time) javexec_time,
                     SUM(buffer_gets) buffer_gets
              FROM   &awr$sqlstat
              WHERE  plan_hash_value > 0
              AND    end_time <= NVL(TO_DATE(nvl(:V2,:endtime),'YYMMDDHH24MI'),SYSDATE+1)
              AND   (:instance is null or instance_number=:instance)
              AND   dbid=:dbid
              AND   (&filter)
              GROUP  BY dbid, force_matching_signature, plan_hash_value,CASE WHEN end_time >= NVL(TO_DATE(nvl(:V1,:starttime),'YYMMDDHH24MI'),SYSDATE-3) THEN 1 ELSE 0 END
              HAVING SUM(elapsed_time)>0
              ) a) a)
SELECT * FROM (
    SELECT dense_rank() OVER(ORDER BY &ord nulls last,sql_id) "#",
           a.* 
    FROM (
        SELECT sql_id,
               MAX(plan_hash) KEEP(dense_rank LAST ORDER BY ela) plan_hash,
               phf PLAN_HASH_FULL,
               MIN(first_seen) first_seen,
               MAX(last_seen) last_seen,
               ratio_to_report(SUM(decode(flag,1,ela))) OVER() "Weight%",
               MAX(diff) "Diff%",
               SUM(exe) "Execs",
               '|' "|",
               ROUND(SUM(ela)/greatest(1,SUM(exe))) "Avg ELA",
               ROUND(100*SUM(CPU)/SUM(ela),2) "CPU%",
               ROUND(100*SUM(iowait)/SUM(ela),2) "IO%",
               ROUND(100*SUM(clwait)/SUM(ela),2) "Cl%",
               ROUND(100*SUM(ccwait)/SUM(ela),2) "CC%",
               ROUND(100*SUM(apwait)/SUM(ela),2) "APP%",
               ROUND(100*SUM(plsexec_time)/SUM(ela),2) "PLSQL%",
               ROUND(100*SUM(javexec_time)/SUM(ela),2) "JAVA%",
               ROUND(SUM(buffer_gets)/greatest(1,SUM(exe)),2) "Buff Gets",
               SUM(SUM(decode(flag,1,ela))) OVER(PARTITION BY dbid,sql_id)*1e3 "Total SQL ms",
               substr(trim(regexp_replace(MAX(to_char(SUBSTR(sql_text,1,1000))),'\s+',' ')),1,200) sql_text
        FROM src 
        LEFT JOIN dba_hist_sqltext USING(dbid,sql_id)
        WHERE phfs>1 and flags>1
        GROUP BY sql_id,dbid,phf
    ) A)
WHERE "#" <=30
ORDER BY "#",last_seen desc, first_seen desc,  "Weight%";

