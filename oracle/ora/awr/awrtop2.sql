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
            READ={READ}
            WRITE={WRITE}
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
WITH qry AS (SELECT nvl(upper(nvl(:V1,:INSTANCE)),'A') inst,
                    nullif(lower(:V2),'a') sqid,
                    to_timestamp(coalesce(:V3,:starttime,to_char(sysdate-7,'YYMMDDHH24MI')),'YYMMDDHH24MI') st,
                    to_timestamp(coalesce(:V4,:endtime,to_char(sysdate+1,'YYMMDDHH24MI')),'YYMMDDHH24MI') ed
             FROM dual)
SELECT pct,
       &grp, 
       plan_hash, &sqls
       last_call,
       execs,
       fetches,
       parses,
       seens,
       ela_total,ela_avg,avgio "Cost/IO",&field
       iowait,cpu,ccwait,clwait,apwait,plsql,
       &ver cellio,oflin,oflout,
       reads,writes,buff,
       rws "ROWS",
       px,
       extractvalue(dbms_xmlgen.getxmltype(q'~SELECT trim(substr(regexp_replace(to_char(substr(sql_text, 1, 500)),'[[:space:][:cntrl:]]+',' '),1,200)) text FROM &check_access_pdb.sqltext WHERE sql_id='~'||regexp_substr(a.top_sql,'\w+')||''' and dbid='||a.dbid||' and rownum<2'),'//TEXT') sql_text
FROM   (SELECT a.*, row_number() OVER(ORDER BY val DESC NULLS LAST) r,
               ratio_to_report(val) OVER() pct
        FROM (
            SELECT &grp,top_sql,dbid,
                   plan_hash,
                   to_char(lastest,'MM-DD"|"HH24:MI') last_call,
                   execs,
                   loads,
                   parses,
                   seens,
                   sqls,
                   mem / exe1 mem,
                   ela ela_total,
                   ela_avg,
                   cpu / ela cpu,
                   iowait/nullif(ioreqs,0) avgio,
                   nullif(round(iowait / ela,3),0) iowait,
                   nullif(round(ccwait / ela,3),0) ccwait,
                   nullif(round(clwait / ela,3),0) clwait,
                   nullif(round(apwait / ela,3),0) apwait,
                   nullif(round(plsql / ela,3),0) plsql,
                   nullif(read / exe1,0) reads,
                   nullif(buff / exe1,0) buff,
                   nullif(write / exe1,0) writes,
                   nullif(FETCH / exe1,0) fetches,
                   nullif(rws / exe1,0) rws,
                   nullif(px / exe1,0) px,
                   nullif(oflin/exe1,0) oflin,
                   nullif(oflout/exe1,0) oflout,
                   nullif(cellio/exe1,0) cellio,
                   &orderby/exe1 val
            FROM   (SELECT --+no_expand
                           &grp,
                           max(dbid) dbid,
                           max(sql_id) KEEP(dense_rank LAST ORDER BY elapsed_time_total) top_sql,
                           count(DISTINCT sql_id) sqls,
                           plan_hash_value plan_hash,
                           count(1) seens,
                           max(begin_interval_time) lastest,
                           sum(execs) execs,
                           sum(loads) loads,
                           sum(parse_calls) parses,
                           avg(sharable_mem/1024/ 1024) mem,
                           sum(elapsed_time) ela,
                           round(sum(elapsed_time)/nullif(decode(sum(execs),0,floor(sum(parse_calls)/greatest(sum(px_servers_execs),1)),sum(execs)),0),2) ela_avg,
                           sum(cpu_time ) cpu,
                           sum(iowait) iowait,
                           sum(ioreqs) ioreqs,
                           sum(ccwait) ccwait,
                           sum(clwait) clwait,
                           sum(apwait) apwait,
                           sum(plsexec_time+javexec_time) plsql,
                           sum(cellio) cellio,
                           sum(oflin) oflin,
                           sign(sum(oflin))*sum(oflout) oflout,
                           sum(greatest(disk_reads,phyread)) read,
                           sum(nvl(phywrite,0)+nvl(direct_writes*512*1024,0)) write,
                           sum(buffer_gets) buff,
                           sum(fetches) FETCH,
                           sum(rows_processed) rws,
                           sum(px_servers_execs) px,
                           decode('&avg',
                                  'avg',
                                  greatest(sum(execs),0,1),
                                  1) exe1
                    FROM (SELECT s.*, executions+CASE WHEN flag_=1 AND first_value(flag_) over(partition by dbid,instance_number,sql_id,plan_hash_value,instance_start ORDER BY snap_id RANGE BETWEEN 1 FOLLOWING AND 1 FOLLOWING) IS NULL then 1 else 0 end execs
                          FROM   qry,&&awr$sqlstat s
                          WHERE  (qry.sqid = &grp OR qry.sqid IS NULL)
                          AND    (&filter)
                          AND    s.end_interval_time BETWEEN qry.st AND ed
                          AND    (qry.inst IN('A','0') OR qry.inst= ''||s.instance_number))
                    GROUP  BY &grp, plan_hash_value)) a)a
WHERE  r <= 50
