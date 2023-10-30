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
            MAX(snap_id) max_snap_id, 
            min(snap_id) min_snap_id
    FROM   (SELECT a.*,
                   to_date(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                   to_date(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI') ed,
                   min(snap_id) over(partition by dbid,instance_number,startup_time) min_snap_id
            FROM   &check_access_pdb.SNAPSHOT a
            WHERE  coalesce(upper(:V1),''||:instance,'A') IN('A',''||instance_number))
    WHERE  end_interval_time + 0 BETWEEN st - 5/1440 AND ed + 5/1440
    GROUP BY dbid,instance_number,min_snap_id)
SELECT MEM_LOW,MEM_HIGH,
       '|' "|",OPTIMALS,OPTIMALS/TOTALS PCT,
       '|' "|",ONEPASSES,ONEPASSES/TOTALS PCT,
       '|' "|",MULTIPASSES,MULTIPASSES/TOTALS PCT,
       '|' "|",TOTALS,PER_SECOND, 2*ratio_to_report(TOTALS) over() PCT
FROM (
    SELECT Nvl(''||LOW_OPTIMAL_SIZE,'*') MEM_LOW,
           Nvl(''||(HIGH_OPTIMAL_SIZE+1),'*') MEM_HIGH,
           nullif(SUM(OPTIMAL_EXECUTIONS*decode(snap_id,min_snap_id,-1,1)),0) OPTIMALS,
           nullif(SUM(ONEPASS_EXECUTIONS*decode(snap_id,min_snap_id,-1,1)),0) ONEPASSES,
           nullif(SUM(MULTIPASSES_EXECUTIONS*decode(snap_id,min_snap_id,-1,1)),0) MULTIPASSES,
           nullif(SUM(TOTAL_EXECUTIONS*decode(snap_id,min_snap_id,-1,1)),0) TOTALS,
           nullif(ROUND(SUM(TOTAL_EXECUTIONS*decode(snap_id,min_snap_id,-1,1)/secs),2),0) PER_SECOND
    FROM   &check_access_pdb.SQL_WORKAREA_HSTGRM h
    JOIN   snap s
    USING (dbid,instance_number)
    WHERE  h.snap_id BETWEEN s.min_snap_id and s.max_snap_id
    GROUP BY ROLLUP((LOW_OPTIMAL_SIZE,HIGH_OPTIMAL_SIZE))
    ORDER BY LOW_OPTIMAL_SIZE)
WHERE TOTALS>0;

PRO SQL STATS:
PRO ==========
WITH qry as (SELECT coalesce(upper(:V1),''||:instance,'A') inst,
                    lower(nvl(:V2,'ela')) typ,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI')  ed from dual)
SELECT /*+ordered use_nl(a b)*/
     &grp
     execs,
     parse,
     val &v2,
     pct,
     round(val/greatest(execs,1),2) "AVG",
     EXTRACTVALUE(DBMS_XMLGEN.GETXMLTYPE(q'~SELECT trim(substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,200)) text FROM &check_access_pdb.SQLTEXT WHERE SQL_ID='~'||regexp_substr(a.top_sql,'\w+')||''' and dbid='||a.dbid||' and rownum<2'),'//TEXT') SQL_TEXT
FROM (SELECT rownum r,
             ratio_to_report(val) over() pct,
             a.* 
      from(
          SELECT /*+ordered use_nl(s hs)*/
                   &base,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total),
                   max(plan_hash_value) KEEP(dense_rank LAST ORDER BY elapsed_time_total)  top_phv,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total) top_sql,
                   count(distinct sql_id) sqls,
                   max(dbid) dbid,
                   typ,
                   count(distinct decode('&base','plan_hash_value',sql_id,s.plan_hash_value)) phvs,
                   decode(typ,'mem',MAX(s.sharable_mem)/1024/1024,
                      SUM(decode(nvl(typ,'ela'),
                                    'exec',s.elapsed_time,
                                    'parse',s.elapsed_time,
                                    'cpu',s.cpu_time,
                                    'read',(s.disk_reads + s.buffer_gets),
                                    'write',s.direct_writes,
                                    'io',s.iowait,
                                    'cc',s.ccwait,
                                    'load',LOADS,
                                    'sort',SORTS,
                                    'fetch',END_OF_FETCH_COUNT,
                                    'row',ROWS_PROCESSED,
                                    'px',PX_SERVERS_EXECS,
                                    s.elapsed_time))) val,
                   nullif(SUM(s.executions),0) execs,
                   sum(s.PARSE_CALLS) parse,
                   sum(s.px_servers_execs) px_count
            FROM (SELECT s.*, SUM(executions) over(partition by &base, qry.typ) execs_,qry.typ
                  FROM   qry,&&awr$sqlstat s
                  WHERE  (&filter)
                  AND    s.begin_interval_time between qry.st and ed
                  AND    (qry.inst in('A','0') or qry.inst= ''||s.instance_number)) s
            WHERE execs_>0 and delta_flag>0 OR execs_=0 AND delta_flag=0
            GROUP  BY &base,typ
            ORDER  BY decode(typ,'exec',execs,'parse',parse,val) desc nulls last) a) a
WHERE  r<=50
order  by r