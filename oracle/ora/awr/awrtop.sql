/*[[Show AWR Top SQLs for a specific period. Usage: awrtop [0|<inst>] [ela|exec|cpu|io|cc|fetch|sort|px|row|load|parse|read|write|mem] [yymmddhhmi] [yymmddhhmi]
    --[[
        &filter: default={1=1}, f={}
    --]]
]]*/

ORA _sqlstat

WITH qry as (SELECT nvl(upper(:V1),'A') inst,
                    lower(nvl(:V2,'ela')) typ,
                    to_timestamp(nvl(:V3,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,''||(:V3+1),to_char(sysdate,'YYMMDDHH24MI')),'YYMMDDHH24MI')  ed from dual) 
SELECT /*+ordered use_nl(a b)*/
     r "#",
     a.sql_id,
     plan_hash,
     execs,
     parse,
     lpad(to_char(val, decode(sign(val - 1e6), -1, 'fm999990.0', 'fm0.00EEEE')),8) value,
     lpad(to_char(decode(typ,'mem',null,val/nvl(execs,nullif(parse,0))),decode(sign(val/nvl(execs,nullif(parse,0)) - 1e6), -1, 'fm999990.0', 'fm0.00EEEE')),8) "AVG",
     substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,150) text
FROM (SELECT rownum r,a.* from(
          SELECT /*+ordered use_nl(s hs)*/
                   sql_id,
                   qry.typ,
                   ''||MAX(s.plan_hash_value) KEEP(dense_rank LAST ORDER BY elapsed_time_total) plan_hash,
                   decode(typ,'mem',MAX(s.sharable_mem)/1024/1024,
                      SUM(decode(nvl(qry.typ,'ela'),
                                    'exec',s.elapsed_time/60,
                                    'parse',s.elapsed_time/60,
                                    'cpu',s.cpu_time/60,
                                    'read',(s.disk_reads + s.buffer_gets),
                                    'write',s.direct_writes,
                                    'io',s.iowait/60,
                                    'cc',s.ccwait/60,
                                    'load',LOADS,
                                    'sort',SORTS,
                                    'fetch',END_OF_FETCH_COUNT,
                                    'row',ROWS_PROCESSED,
                                    'px',PX_SERVERS_EXECS,
                                    s.elapsed_time/60)))val,      
                   nullif(SUM(s.executions),0) execs,
                   sum(s.PARSE_CALLS) parse
            FROM   qry,&&awr$sqlstat s
            WHERE  (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
            AND    s.end_time BETWEEN qry.st and qry.ed
            AND    (&filter)
            GROUP  BY sql_id,qry.typ
            ORDER  BY decode(qry.typ,'exec',execs,'parse',parse,val) desc nulls last)a) a,
           Dba_Hist_Sqltext b
WHERE  a.sql_id = b.sql_id
AND    r<=50
union all
SELECT 51,lpad('-',13,'-'),lpad('-',10,'-'),null,null,null,lpad('-',8,'-'),lpad('-',120,'-') from dual
union all
SELECT null,'FILTER:',null,null,null,
      lpad(typ,8),lpad('inst:'||inst,8),
      'Time:'||to_char(st,'YYYY  DD/MON/HH24:MI')||' -- '||to_char(ed,'DD/MON/HH24:MI')||
      ' | FORMAT:AWRSQL 0/inst ela/cpu/io/cc/fetch/row/load/parse/read/write/mem yymmddhhmi yymmddhhmi' from qry
order  by 1