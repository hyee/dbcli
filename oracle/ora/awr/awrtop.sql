/*[[Show AWR Top SQLs for a specific period. Usage: @@NAME {[0|<inst>] [ela|exec|cpu|io|cc|fetch|sort|px|row|load|parse|read|write|mem] [yymmddhhmi] [yymmddhhmi]} [-m] [-f"<filter>"] 
    --[[
        &filter: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &BASE : s={sql_id}, m={signature}
        &v2   : df={ela} default={}
    --]]
]]*/
set feed off
col &v2,avg format smhd2
ORA _sqlstat
col pct for pct2

WITH qry as (SELECT coalesce(upper(:V1),''||:instance,'A') inst,
                    lower(nvl(:V2,'ela')) typ,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,to_char(sysdate,'YYMMDDHH24MI')),'YYMMDDHH24MI')  ed from dual)
SELECT /*+ordered use_nl(a b)*/
     a.sql_id,
     phvs,
     plan_hash top_phv,
     execs,
     parse,
     val &v2,
     pct,
     round(val/nullif(decode(execs,0,floor(parse/greatest(px_count,1)),execs),0),2) "AVG",
     (SELECT trim(substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,200)) text FROM DBA_HIST_SQLTEXT WHERE SQL_ID=regexp_substr(a.sql_id,'\w+') and dbid=a.dbid and rownum<2) SQL_TEXT
FROM (SELECT rownum r,
             ratio_to_report(val) over() pct,
             a.* 
      from(
          SELECT /*+ordered use_nl(s hs)*/
                   max(sql_id)  KEEP(dense_rank LAST ORDER BY elapsed_time_total)||case when '&base'!='sql_id' and regexp_like(&base,'^\d+$') then '|'||&base end sql_id,
                   max(sql_id) sqlid,
                   max(dbid) dbid,
                   qry.typ,
                   count(distinct s.plan_hash_value) phvs,
                   ''||MAX(s.plan_hash_value) KEEP(dense_rank LAST ORDER BY elapsed_time_total) plan_hash,
                   decode(typ,'mem',MAX(s.sharable_mem)/1024/1024,
                      SUM(decode(nvl(qry.typ,'ela'),
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
            FROM   qry,&&awr$sqlstat s
            WHERE  (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
            AND    s.end_time BETWEEN qry.st and qry.ed
            AND    (&filter)
            GROUP  BY &base,qry.typ
            ORDER  BY decode(qry.typ,'exec',execs,'parse',parse,val) desc nulls last) a) a
WHERE  r<=50
order  by r