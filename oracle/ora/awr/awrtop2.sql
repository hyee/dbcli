/*[[
    Show AWR Top SQLs for a specific period. Usage: @@NAME {[0|<inst>] [a|<sql_id>] [yymmddhhmi] [yymmddhhmi]} [-avg] [-<order_by_fields>] [-m|-p] [-u|-f"<filter>"]
    -m    : group by signature instead of SQL Id
    -p    : group by plan hash value instead of SQL Id
    -u    : only show the records whose parsing_schema_name=sys_context('userenv','current_schema')
    -avg  : display and order by average cost per execution

    Sample Output:
    ==============
     ELA#    SQL_ID      PLAN_HASH  LAST_CALL   EXECS    FETCHES  PARSES  SEENS  ELA   IOWAIT  CPU   CCWAIT CLWAIT APWAIT PLSQL  CELLIO   ...
    ----- ------------- ---------- ----------- -------- -------- -------- ----- ------ ------ ------ ------ ------ ------ ----- --------- ...
    69.2% 310wr50c2fjv0 3971591178 04-12|09:00 601.23 K 601.20 K   2.40 M   668  2.85d   0.0%  98.7%   0.0%   0.0%   0.0%  0.0%      0  B ...
    15.0% ard6ysp2ufm1n  881395945 04-12|09:00 601.23 K 601.22 K   2.40 M   668 14.89h   0.0%  95.4%   0.0%   0.0%   0.0%  0.0%      0  B ...
     2.0% a8zxxqa1hcc7f 4063065057 04-12|09:00 601.23 K 601.21 K   2.40 M   668  1.97h   0.0%  72.7%   0.0%   0.0%   0.0%  0.0%      0  B ...
     1.7% 7v8dacmx3t3td 1117094054 04-12|09:00 601.23 K 601.23 K   2.40 M   668  1.68h   0.0%  66.6%   0.0%   0.0%   0.0%  0.0%      0  B ...
     1.7% d3ddjhh624zy9 4219360880 04-12|09:00 600.66 K 601.20 K   2.40 M   668  1.64h   0.0%  69.8%   0.0%   0.0%   0.0%  0.0%      0  B ...
     1.5% 68gsknzub3950          0 04-12|09:00      0        0        0     167  1.44h   0.0%  61.1%   0.0%   0.0%   0.0%  1.6%      0  B ...
     1.4% d6a0tfanz9b15          0 04-12|09:00      0        0        0     167  1.40h   0.0%  63.7%   0.0%   0.0%   0.0%  1.9%      0  B ...
     1.4% ayxf7qwpa2mhj          0 04-12|09:00      0        0        0     167  1.38h   0.0%  64.5%   0.0%   0.0%   0.0%  1.9%      0  B ...
     1.3% 2gx6530gfrus4          0 04-12|09:00      0        0        0     167  1.33h   0.0%  65.9%   0.0%   0.0%   0.0%  1.9%      0  B ...
     1.3% 1bvuy52rj19k1          0 04-12|09:00      0        0        0     167  1.31h   0.0%  66.7%   0.0%   0.0%   0.0%  1.9%      0  B ...
    
    --[[
        &grp: s={sql_id}, m={signature}, p={null}
        &sqls: s={}, m={sqls,top_sql,}, p={sqls,top_sql,}
        &filter: s={1=1},u={PARSING_SCHEMA_NAME=nvl('&0',sys_context('userenv','current_schema'))},f={}
        &orderby: {
            default={ela}
            ELA_TOTAL={ela*exe1}
            EXECS={EXECS}
            FETCHES={FETCHES}
            PARSES={PARSES}
            IOWAIT={IOWAIT}
            CPU={CPU}
            CCWAIT={CCWAIT}
            CLWAIT={CLWAIT}
            APWAIT={APWAIT}
            PLSQL={PLSQL}
            CELLIO={CELLIO}
            OFLIN={OFLIN}
            OFLOUT={OFLOUT}
            READS={READS}
            WRITES={WRITES}
            BUFF={BUFF}
            ROWS={RWS}
            PX={PX}
        }
        &field: {
            default={},
            CPU={val CPU_TM,}
            CCWAIT={val CC_TM,}
            CLWAIT={val CL_TM,}
            APWAIT={val AP_TM,}
            PLSQL={val PLSQL_TM,}
        }
        &avg: df={total} avg={avg}
        @ver: 11.2={} default={--}
        @check_access_pdb: awrpdb={AWR_PDB_} default={dba_hist_}
    --]]
]]*/

ORA _sqlstat

col ela,ela_avg,ela_total,CPU_TM,CC_TM,CL_TM,AP_TM,PLSQL_TM,Cost/IO for usmhd2
col iowait,cpu,clwait,apwait,plsql,ccwait,pct format pct1
col reads,writes,mem,cellio,oflin,oflout,buff format kmg
col execs,FETCHES,loads,parses,rows,PX format tmb
set autohide col
WITH qry as (SELECT nvl(upper(NVL(:V1,:INSTANCE)),'A') inst,
                    nullif(lower(:V2),'a') sqid,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI') ed
             FROM Dual)
SELECT pct,
       &grp, 
       plan_hash, &sqls
       last_call,
       execs,
       FETCHES,
       parses,
       seens,
       ela_total,ela_avg,avgio "Cost/IO",&field
       iowait,cpu,ccwait,clwait,apwait,plsql,
       &ver cellio,oflin,oflout,
       reads,writes,buff,
       RWS "ROWS",
       PX,
       EXTRACTVALUE(DBMS_XMLGEN.GETXMLTYPE(q'~SELECT trim(substr(regexp_replace(to_char(SUBSTR(sql_text, 1, 500)),'[[:space:][:cntrl:]]+',' '),1,200)) text FROM &check_access_pdb.SQLTEXT WHERE SQL_ID='~'||regexp_substr(a.top_sql,'\w+')||''' and dbid='||a.dbid||' and rownum<2'),'//TEXT') SQL_TEXT
FROM   (SELECT a.*, row_number() over(order by val desc nulls last) r,
               ratio_to_report(val) over() pct
        FROM (
            SELECT &grp,top_sql,dbid,
                   plan_hash,
                   to_char(lastest,'MM-DD"|"HH24:MI') last_call,
                   execs,
                   LOADs,
                   parses,
                   seens,
                   sqls,
                   mem / exe1 mem,
                   ela ela_total,
                   ela_avg,
                   CPU / ela CPU,
                   iowait/nullif(ioreqs,0) avgio,
                   nullif(round(iowait / ela,3),0) iowait,
                   nullif(round(ccwait / ela,3),0) ccwait,
                   nullif(round(clwait / ela,3),0) clwait,
                   nullif(round(apwait / ela,3),0) apwait,
                   nullif(round(PLSQL / ela,3),0) PLSQL,
                   nullif(READ / exe1,0) READS,
                   nullif(buff / exe1,0) buff,
                   nullif(WRITE / exe1,0) WRITES,
                   nullif(FETCH / exe1,0) FETCHES,
                   nullif(RWS / exe1,0) rws,
                   nullif(PX / exe1,0) PX,
                   nullif(oflin/exe1,0) oflin,
                   nullif(oflout/exe1,0) oflout,
                   nullif(cellio/exe1,0) cellio,
                   &orderby/exe1 val
            FROM   (SELECT --+no_expand
                           &grp,
                           max(dbid) dbid,
                           max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total) top_sql,
                           count(distinct sql_id) sqls,
                           plan_hash_value plan_hash,
                           count(1) SEENS,
                           MAX(begin_interval_time) lastest,
                           SUM(executions) execs,
                           SUM(LOADS) LOADs,
                           SUM(PARSE_CALLS) parses,
                           AVG(sharable_mem/1024/ 1024) mem,
                           SUM(elapsed_time) ela,
                           round(SUM(elapsed_time)/nullif(decode(SUM(executions),0,floor(sum(PARSE_CALLS)/greatest(sum(px_servers_execs),1)),sum(executions)),0),2) ela_avg,
                           SUM(cpu_time ) CPU,
                           SUM(iowait) iowait,
                           SUM(ioreqs) ioreqs,
                           SUM(CCWAIT) ccwait,
                           SUM(CLWAIT) clwait,
                           SUM(apwait) apwait,
                           SUM(PLSEXEC_TIME+JAVEXEC_TIME) PLSQL,
                           SUM(cellio) cellio,
                           SUM(oflin) oflin,
                           sign(SUM(oflin))*SUM(oflout) oflout,
                           SUM(greatest(disk_reads,phyread)) READ,
                           SUM(nvl(phywrite,direct_writes)) WRITE,
                           sum(buffer_gets) buff,
                           SUM(FETCHES) FETCH,
                           SUM(ROWS_PROCESSED) RWS,
                           SUM(PX_SERVERS_EXECS) PX,
                           decode('&avg',
                                  'avg',
                                  greatest(SUM(executions),0,1),
                                  1) exe1
                   FROM  (SELECT s.*, SUM(executions) over(partition by &grp, plan_hash_value) execs_
                          FROM   qry,&&awr$sqlstat s
                          WHERE  (qry.sqid = &grp or qry.sqid is null)
                          AND    (&filter)
                          AND    s.end_interval_time between qry.st and ed
                          AND    (qry.inst in('A','0') or qry.inst= ''||s.instance_number))
                   WHERE execs_>0 and delta_flag>0 OR execs_=0 AND delta_flag=0
                    GROUP  BY &grp, plan_hash_value)) a)a
WHERE  r <= 50
