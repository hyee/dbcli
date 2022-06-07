/*[[
    Show AWR Top SQLs for a specific period. Usage: @@NAME {[0|<inst>] [ela|exec|cpu|io|cc|fetch|sort|px|row|load|parse|read|write|mem] [yymmddhhmi] [yymmddhhmi]} [-m|-p] [-u] [-f"<filter>"] 
    -m: group by force_maching_signature instead of sql_id
    -p: group by plan_hash_value instead of sql_id
    -u: only show the records whose parsing_schema_name=sys_context('userenv','current_schema')

    Sample Output:
    ==============
       SQL_ID     PHVS  TOP_PHV    EXECS  PARSE  ELA    PCT    AVG  SQL_TEXT                                     
    ------------- ---- ---------- ------ ------ ------ ------ ----- ---------------------------------------------
    310wr50c2fjv0    1 3971591178 120971 604862 19.01h 71.94% 0.57s SELECT A.EVENT, DATA , '$' FROM (SELECT /*+no
    ard6ysp2ufm1n    1 881395945  120972 604863  3.98h 15.06% 0.12s SELECT '[gv$sysstat]' || NAME, SUM(VALUE), ''
    68gsknzub3950    1 0                      0  1.45h  5.50%       BEGIN :1 := mon_db.startup(interval=>5,server
    a8zxxqa1hcc7f    1 4063065057 120972 604863 28.02m  1.77% 0.01s SELECT JSON_ARRAYAGG(JSON_OBJECT('event' IS D
    7v8dacmx3t3td    1 1117094054 120972 604551 22.84m  1.44% 0.01s SELECT COUNT(*) FROM GV$SESSION WHERE USERNAM
    d3ddjhh624zy9    1 4219360880 120971 604668 21.70m  1.37% 0.01s SELECT EVENT, EVENT || '|' || LISTAGG(NVL(W, 
    6hnhqahphpk8n    1 486334127   18413  18413 10.51m  0.66% 0.03s select free_mb from v$asm_diskgroup_stat wher
    d49r7pkbqqpgn    1 1811226007 120972      0  6.54m  0.41%     0 SELECT JSON_ARRAYAGG(JSON_OBJECT('event' IS D
    6uxga5vnsgugt    2 1018201100   5196   5196  4.07m  0.26% 0.05s select s.file#, s.block#, s.ts#, t.obj#, s.hw
    1u8v867f5ys43    1 2025954503  25140  25140  3.98m  0.25% 0.01s select ts#, file#, block#, hwmincr from seg$ 
    892d0vg7gatf5    1 1656552173 120972      0  3.08m  0.19%     0 SELECT MAX(A.VALUE), MIN(A.VALUE) FROM V$SESS
    3kqrku32p6sfn    1 1774581179     80   1212  3.00m  0.19% 2.25s MERGE /*+ OPT_PARAM('_parallel_syspls_obey_fo
    1q1spprb9m55h    2 2870263549    114    200  2.13m  0.13% 1.12s WITH MONITOR_DATA AS (SELECT INST_ID, KEY, NV
    50ycjbhy30sxv    1 670558803  120970      0  1.29m  0.08%     0 SELECT EVENT, EVENT || '|' || NVL(DATA, '|'),
    c179sut1vgpc8    1 1149183595   2002   2002  1.04m  0.07% 0.03s INSERT /*+ LEADING(@"SEL$F5BB74E1" "H"@"SEL$2

    --[[
        &filter: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &BASE : s={sql_id}, m={signature} p={plan_hash_value}
        &grp  : s={sql_id,phvs,top_phv top_plan,} m={signature,top_sql,phvs,top_phv top_plan,} p={top_phv plan_hash,phvs sqls,top_sql,}
        &v2   : df={ela} default={}
    --]]
]]*/
set feed off
col &v2,avg format usmhd2
ORA _sqlstat
col pct for pct2

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
     (SELECT trim(substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'['||chr(10)||chr(13)||chr(9)||' ]+',' '),1,200)) text FROM DBA_HIST_SQLTEXT WHERE SQL_ID=regexp_substr(a.top_sql,'\w+') and dbid=a.dbid and rownum<2) SQL_TEXT
FROM (SELECT rownum r,
             ratio_to_report(val) over() pct,
             a.* 
      from(
          SELECT /*+ordered use_nl(s hs)*/
                   &base,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total),
                   max(plan_hash_value) KEEP(dense_rank LAST ORDER BY elapsed_time_total)  top_phv,
                   max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total) top_sql,
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