/*[[
    Show AWR Top SQLs for a specific period. Usage: @@NAME {[0|<inst>] [ela|exec|cpu|io|cc|fetch|sort|px|row|load|parse|read|write|mem] [yymmddhhmi] [yymmddhhmi]} [-m|-p] [-u] [-f"<filter>"] 
    -m: group by force_maching_signature instead of sql_id
    -p: group by plan_hash_value instead of sql_id
    -u: only show the records whose parsing_schema_name=sys_context('userenv','current_schema')
    --[[
        &filter: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &BASE : s={sql_id}, m={signature} p={plan_hash_value}
        &grp  : s={sql_id,phvs,top_phv top_plan,} m={signature,sqls,top_sql,phvs,top_phv top_plan,} p={top_phv plan_hash,phvs sqls,top_sql,}
        &v2   : df={ela} default={}
        @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
    --]]
]]*/
set feed off
col &v2,avg format usmhd2
ORA _sqlstat
col pct for pct2
COL MEM_LOW,MEM_HIGH FOR KMG0
COl OPTIMALS,ONEPASSES,MULTIPASSES,TOTALS,PER_SECOND FOR TMB

PRO SQL WORKAREA HISTOGRAM:
PRO =======================
WITH snap AS(
    SELECT /*+materialize*/ dbid, 
            instance_number, 
            1+round(86400*(max(end_interval_time+0)-min(end_interval_time+0))) secs,
            max(snap_id) max_snap_id, 
            min(snap_id) min_snap_id
    FROM   (SELECT a.*,
                   to_date(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                   to_date(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI') ed,
                   min(snap_id) OVER(PARTITION BY dbid,instance_number,startup_time) min_snap_id
            FROM   &check_access_pdb.snapshot a
            WHERE  coalesce(upper(:V1),''||:instance,'A') IN('A',''||instance_number))
    WHERE  end_interval_time + 0 BETWEEN st - 5/1440 AND ed + 5/1440
    GROUP BY dbid,instance_number,min_snap_id)
SELECT mem_low,mem_high,
       '|' "|",optimals,optimals/totals pct,
       '|' "|",onepasses,onepasses/totals pct,
       '|' "|",multipasses,multipasses/totals pct,
       '|' "|",totals,per_second, 2*ratio_to_report(totals) OVER() pct
FROM (
    SELECT nvl(''||low_optimal_size,'*') mem_low,
           nvl(''||(high_optimal_size+1),'*') mem_high,
           nullif(sum(optimal_executions*decode(snap_id,min_snap_id,-1,1)),0) optimals,
           nullif(sum(onepass_executions*decode(snap_id,min_snap_id,-1,1)),0) onepasses,
           nullif(sum(multipasses_executions*decode(snap_id,min_snap_id,-1,1)),0) multipasses,
           nullif(sum(total_executions*decode(snap_id,min_snap_id,-1,1)),0) totals,
           nullif(round(sum(total_executions*decode(snap_id,min_snap_id,-1,1)/secs),2),0) per_second
    FROM   &check_access_pdb.sql_workarea_hstgrm h
    JOIN   snap s
    USING (dbid,instance_number)
    WHERE  h.snap_id BETWEEN s.min_snap_id AND s.max_snap_id
    GROUP BY ROLLUP((low_optimal_size,high_optimal_size))
    ORDER BY low_optimal_size)
WHERE totals>0;

PRO SQL STATS:
PRO ==========
WITH qry AS (SELECT coalesce(upper(:V1),''||:instance,'A') inst,
                    lower(nvl(:V2,'ela')) typ,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI')  ed FROM dual)
SELECT /*+ordered use_nl(a b)*/
     &grp
     execs,
     parse,
     val &v2,
     pct,
     round(val/greatest(execs,1),2) "AVG",
     extractvalue(dbms_xmlgen.getxmltype(q'~SELECT trim(substr(regexp_replace(to_char(substr(sql_text, 1, 500)),'[[:space:][:cntrl:]]+',' '),1,200)) text FROM &check_access_pdb.sqltext WHERE sql_id='~'||regexp_substr(a.top_sql,'\w+')||''' and dbid='||a.dbid||' and rownum<2'),'//TEXT') sql_text
FROM (SELECT ROWNUM r,
             ratio_to_report(val) OVER() pct,
             a.* 
      FROM(
          SELECT /*+ordered use_nl(s hs)*/
                   &base,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total),
                   max(plan_hash_value) KEEP(dense_rank LAST ORDER BY elapsed_time_total)  top_phv,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total) top_sql,
                   count(DISTINCT sql_id) sqls,
                   max(dbid) dbid,
                   typ,
                   count(DISTINCT decode('&base','plan_hash_value',sql_id,s.plan_hash_value)) phvs,
                   decode(typ,'mem',max(s.sharable_mem)/1024/1024,
                      sum(decode(nvl(typ,'ela'),
                                    'exec',s.elapsed_time,
                                    'parse',s.elapsed_time,
                                    'cpu',s.cpu_time,
                                    'read',(s.disk_reads + s.buffer_gets),
                                    'write',nvl(s.phywrite,0)+nvl(s.direct_writes*512*1024,0),
                                    'io',s.iowait,
                                    'cc',s.ccwait,
                                    'load',loads,
                                    'sort',sorts,
                                    'fetch',end_of_fetch_count,
                                    'row',rows_processed,
                                    'px',px_servers_execs,
                                    s.elapsed_time))) val,
                   nullif(sum(s.execs),0) execs,
                   sum(s.parse_calls) parse,
                   sum(s.px_servers_execs) px_count
            FROM (SELECT s.*, 
                         executions+CASE WHEN flag_=1 AND first_value(flag_) over(partition by dbid,instance_number,sql_id,plan_hash_value,instance_start ORDER BY snap_id RANGE BETWEEN 1 FOLLOWING AND 1 FOLLOWING) IS NULL then 1 else 0 end execs,
                         qry.typ
                  FROM   qry,&&awr$sqlstat s
                  WHERE  (&filter)
                  AND    s.end_interval_time BETWEEN qry.st AND ed
                  AND    (qry.inst IN('A','0') OR qry.inst= ''||s.instance_number)) s
            GROUP  BY &base,typ
            ORDER  BY decode(typ,'exec',execs,'parse',parse,val) DESC NULLS LAST) a) a
WHERE  r<=50
ORDER  BY pct DESC