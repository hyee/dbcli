/*[[Show AWR Top SQLs for a specific period. Usage: @@NAME {[0|<inst>] [ela|exec|cpu|io|cc|fetch|sort|px|row|load|parse|read|write|mem] [yymmddhhmi] [yymmddhhmi]} [-m] [-f"<filter>"] 
    --[[
        &filter: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &BASE : s={sql_id}, m={signature}
    --]]
]]*/
set feed off
col value,avg format smhd2
ORA _sqlstat

WITH qry as (SELECT coalesce(upper(:V1),''||:instance,'A') inst,
                    lower(nvl(:V2,'ela')) typ,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,''||(:V3+1),to_char(sysdate,'YYMMDDHH24MI')),'YYMMDDHH24MI')  ed from dual)
SELECT /*+ordered use_nl(a b)*/
     r "#",
     a.sql_id,
     plan_hash,
     execs,
     parse,
     val value,
     val/nvl(execs,nullif(parse,0)) "AVG",
     substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,200) text
FROM (SELECT rownum r,a.* from(
          SELECT /*+ordered use_nl(s hs)*/
                   max(sql_id)  KEEP(dense_rank LAST ORDER BY elapsed_time_total)||case when '&base'!='sql_id' and regexp_like(&base,'^\d+$') then '|'||&base end sql_id,
                   max(sql_id) sqlid,
                   qry.typ,
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
                                    s.elapsed_time)))val,
                   nullif(SUM(s.executions),0) execs,
                   sum(s.PARSE_CALLS) parse
            FROM   qry,&&awr$sqlstat s
            WHERE  (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
            AND    s.end_time BETWEEN qry.st and qry.ed
            AND    (&filter)
            GROUP  BY &base,qry.typ
            ORDER  BY decode(qry.typ,'exec',execs,'parse',parse,val) desc nulls last)a) a,
           Dba_Hist_Sqltext b
WHERE  a.sqlid = b.sql_id
AND    r<=50

order  by 1