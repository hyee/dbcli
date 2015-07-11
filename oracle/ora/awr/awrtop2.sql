/*[[
    Show AWR Top SQLs for a specific period. Usage: awrtop2 [-m] [0|<inst>] [a|<sql_id>] [total|avg] [yymmddhhmi] [yymmddhhmi] [exec|ela|cpu|io|cc|fetch|rows|load|parse|read|write|mem] 
    --[[
        &grp: s={sql_id}, m={signature}
        &filter: s={1=1},u={PARSING_SCHEMA_NAME||''=sys_context('userenv','current_schema')},f={}
    --]]
]]*/

ORA _sqlstat

WITH qry as (SELECT nvl(upper(:V1),'A') inst,
                    nullif(lower(:V2),'a') sqid,
                    nvl(lower(:V3),'total') calctype,
                    to_timestamp(nvl(:V4,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V5,''||(:V4+1),to_char(sysdate,'YYMMDDHH24MI')),'YYMMDDHH24MI') ed,
                    lower(nvl(:V6,'ela')) sorttype
             FROM Dual) 
SELECT &grp,
       plan_hash,
       last_call,
       lpad(replace(to_char(exe,decode(sign(exe - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) execs,
       lpad(replace(to_char(LOAD,decode(sign(LOAD - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) loads,
       lpad(replace(to_char(parse,decode(sign(parse - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) parses,
       seens,
       lpad(replace(to_char(mem,decode(sign(mem - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) memory,
       lpad(replace(to_char(ela,decode(sign(ela - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) elapsed,
       lpad(replace(to_char(CPU,decode(sign(CPU - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) CPU_TIM,
       lpad(replace(to_char(iowait,decode(sign(iowait - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) io_wait,
       lpad(replace(to_char(ccwait,decode(sign(ccwait - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) cc_wait,
       lpad(replace(to_char(ccwait,decode(sign(clwait - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) cl_wait,
       lpad(replace(to_char(PLSQL,decode(sign(PLSQL - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) "PL/SQL",
       lpad(replace(to_char(JAVA,decode(sign(JAVA - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) JAVA_TM,
       lpad(replace(to_char(READ,decode(sign(READ - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) READS_MB,
       lpad(replace(to_char(WRITE,decode(sign(WRITE - 1e5),-1,'fm99990.09','fm0.00EEEE')),'+0'),7) WRITES_MB,
       lpad(replace(to_char(FETCH,decode(sign(FETCH - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) FETCHS,
       lpad(replace(to_char(RWS,decode(sign(RWS - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) "ROWS",
       lpad(replace(to_char(PX,decode(sign(PX - 1e5),-1,'fm99990','fm0.00EEEE')),'+0'),7) PX_SVRS,
       (SELECT substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,100) text FROM DBA_HIST_SQLTEXT WHERE SQL_ID=a.sq_id) SQL_TEXT
FROM   (SELECT &grp,sq_id,
               plan_hash,
               to_char(lastest,'MM-DD"|"HH24:MI') last_call,
               exe,
               LOAD,
               parse,
               seens,
               mem / exe1 mem,
               ela / exe1 ela,
               CPU / exe1 CPU,
               iowait / exe1 iowait,
               ccwait / exe1 ccwait,
               clwait / exe1 clwait,
               PLSQL / exe1 PLSQL,
               JAVA / exe1 JAVA,
               READ / exe1 READ,
               WRITE / exe1 WRITE,
               FETCH / exe1 FETCH,
               RWS / exe1 rws,
               PX / exe1 PX,
               row_number() over(order by decode(sorttype, 'exec', exe, 'load', load, 'parse', parse, 
                                               'mem', mem, 'ela', ela, 'cpu', cpu, 'io', iowait, 'plsql', plsql, 
                                               'java', java, 'read', read, 'write', write, 'fetch', fetch, 
                                               'rows', rws, 'px', px,'cc',ccwait)/exe1 desc nulls last) r
        FROM   (SELECT --+no_expand
                       &grp,
                       max(sql_id) sq_id,
                       plan_hash_value plan_hash,
                       qry.sorttype,
                       count(1) SEENS,
                       MAX(begin_interval_time) lastest,
                       SUM(executions) exe,
                       SUM(LOADS) LOAD,
                       SUM(PARSE_CALLS) parse,
                       AVG(sharable_mem/1024/ 1024) mem,
                       SUM(elapsed_time /60) ela,
                       SUM(cpu_time /60) CPU,
                       SUM(iowait /60) iowait,
                       SUM(CCWAIT /60) ccwait,
                       SUM(CLWAIT /60) clwait,
                       SUM(PLSEXEC_TIME /60) PLSQL,
                       SUM(JAVEXEC_TIME /60) JAVA,
                       SUM(disk_reads + s.buffer_gets) READ,
                       SUM(direct_writes) WRITE,
                       SUM(END_OF_FETCH_COUNT) FETCH,
                       SUM(ROWS_PROCESSED) RWS,
                       SUM(PX_SERVERS_EXECS) PX,
                       decode(max(qry.calctype),
                              'avg',
                              SUM(NVL(NULLIF(executions, 0),
                                      NULLIF(PARSE_CALLS, 0))),
                              1) exe1
                FROM   qry,&&awr$sqlstat s
                WHERE  s.snap_id = s.snap_id
                AND    s.instance_number = s.instance_number
                AND    s.dbid = s.dbid
                AND    (qry.sqid = &grp or qry.sqid is null)
                AND    (&filter)
                AND    s.begin_interval_time between qry.st and ed
                AND    (qry.inst in('A','0') or qry.inst= ''||s.instance_number)
                GROUP  BY &grp, plan_hash_value,qry.sorttype)) a
WHERE  r <= 50
