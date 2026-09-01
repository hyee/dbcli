/*[[Show AWR metric. Usage: @@NAME [yymmddhh24mi] [yymmddhh24mi] [instances]

 -h: target views are gv$xxxmetric_history
    --[[
        @ver: 11={}
        &opt:  default={} h={_HISTORY}
        &mins: default={1/144} h={84/1440}
        &v1: default={&starttime}
        &v2: default={&endtime}
        @cell: {
            12={
                '-',
                [[grid={topic="DBA_HIST_CELL_GLOBAL (Per Second)",height=0,autohide='on'}
                SELECT NAME, round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) , 2) VALUE
                FROM   (SELECT metric_name, NAME, SUM(metric_value/secs) metric_value
                        FROM   (SELECT metric_name,
                                       metric_value v,
                                       secs,
                                       metric_value - lag(metric_value) over(PARTITION BY a.dbid, cell_hash, INCARNATION_NUM, metric_name ORDER BY a.snap_id) metric_value,
                                       REPLACE(metric_name, 'bytes', 'megabytes') NAME
                                FROM  (select * from (&snaps) where instance_number=1) , 
                                       dba_hist_cell_global a
                                WHERE  a.snap_id between minid+1 and maxid
                                AND    a.dbid='&dbid')
                        GROUP  BY metric_name, NAME)
                WHERE  round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) , 2) > 0
                ORDER  BY VALUE DESC
                ]],
            } 
            default={}
        }

        &snaps: {default={
            SELECT a.*,decode(snap_id,minid,-1,1) flag
            FROM   (SELECT dbid,
                        instance_number,
                        startup_time,
                        snap_id,
                        MIN(snap_id) over(PARTITION BY dbid, instance_number, startup_time) minid,
                        MAX(snap_id) over(PARTITION BY dbid, instance_number, startup_time) maxid,
                        round(86400 * (MAX(end_interval_time + 0)
                                over(PARTITION BY dbid, instance_number, startup_time) - MIN(end_interval_time + 0)
                                over(PARTITION BY dbid, instance_number, startup_time))) secs
                    FROM   dba_hist_snapshot s
                    WHERE  dbid='&dbid'
                    AND    ('&3' IS NULL OR instr(',&v3,', ',' || instance_number || ',') > 0)
                    AND    s.end_interval_time BETWEEN nvl(to_date('&1', 'YYMMDDHH24MI') - 1.1 / 24, SYSDATE - 7) AND
                        nvl(to_date('&2', 'YYMMDDHH24MI'), SYSDATE+1)) a
            WHERE  minid < maxid
            AND    snap_id IN (minid, maxid)
        }}
    --]]
]]*/
set sep4k on feed off verify off

COL WAITED,AVG_WAIT,CPU|TIME,CPU|QUEUE,DBTIM,ELA/CALL,CPU/CALL,DBTIME/CALL,read,write,gccu,gccr for usmhd2
col dbtime,SMALLS,READS,LARGES,WRITES,PCT,%,FG,CPU|UT,CPU|LIMIT for pct2
COL MBPS,phyrds,phywrs,redo FOR KMG
COL CALLS,EXEC,COMMITS,ROLLBACKS,IOS_WAIT,IOPS,WAITS,GOODNESS,AAS,OPTIMAL,MULTIPASS,ONEPASS FOR TMB
col sql,io,cpu,parse,cc,cl,app for pct2

grid {
    [[ grid={topic="DBA_HIST_SERVICE_STAT (Per Second)"}
        SELECT *
        FROM   (SELECT service_name,
                       insts,
                       stat_name,
                       CASE
                           WHEN stat_name = 'gc cr block receive time' THEN
                               round(value / nullif(max(decode(stat_name, 'gc cr blocks received', value)) OVER(PARTITION BY service_name), 0), 2)
                               WHEN stat_name = 'gc current block receive time' THEN
                               round(value / nullif(max(decode(stat_name, 'gc current blocks received', value)) OVER(PARTITION BY service_name), 0), 2)
                           WHEN stat_name LIKE '%time%' AND stat_name != 'DB time' OR stat_name = 'DB CPU' THEN
                               round(value / nullif(max(decode(stat_name, 'DB time', value)) OVER(PARTITION BY service_name), 0), 4)
                           ELSE
                               value
                       END val
                FROM   (SELECT nvl(service_name, '--TOTAL--') service_name,
                               nvl2(service_name,listagg(decode(r,1,instance_number),',') WITHIN GROUP(ORDER BY instance_number),'') insts,
                               stat_name,
                               round(sum(flag * value / secs * CASE
                                             WHEN stat_name LIKE 'physical%' THEN
                                              (SELECT 0 + value
                                               FROM   dba_hist_parameter b
                                               WHERE  a.dbid = b.dbid
                                               AND    b.parameter_name = 'db_block_size'
                                               AND    ROWNUM < 2)
                                             WHEN stat_name LIKE 'gc %time' THEN
                                               10000
                                             ELSE
                                               1
                                         END),
                                     2) value
                        FROM    (SELECT a.*,row_number() OVER(PARTITION BY stat_name,instance_number ORDER BY 1) r 
                                 FROM (SELECT * FROM dba_hist_service_stat NATURAL JOIN(&snaps)) a
                                 WHERE dbid=:dbid ) a
                        GROUP  BY stat_name, ROLLUP(service_name)
                        HAVING round(sum(flag * value / secs), 2) > 0) a)
        PIVOT(max(val)
        FOR    stat_name IN('logons cumulative' logons,
                            'physical reads' phyrds,
                            'physical writes' phywrs,
                            'redo size' redo,
                            'DB time' dbtim,
                            'sql execute elapsed time' sql,
                            'user I/O wait time' io,
                            'DB CPU' cpu,
                            'parse time elapsed' parse,
                            'concurrency wait time' cc,
                            'application wait time' app,
                            'cluster wait time' cl,
                            'gc current block receive time' gccu,
                            'gc cr block receive time' gccr,
                            'user calls' calls,
                            'execute count' exec,
                            'user commits' commits,
                            'user rollbacks' rollbacks,
                            'workarea executions - optimal' optimal,
                            'workarea executions - multipass' multipass,
                            'workarea executions - onepass' onepass))
        ORDER  BY dbtim DESC
    ]],
    '-', 
    {   
        [[ grid={topic="DBA_HIST_IOSTAT_FUNCTION"}
            SELECT  function_name,
                    nullif(round(latency, 2), 0) avg_wait,
                    round(ios,2) ios_wait,
                    round(mbps, 2) mbps,
                    round(iops, 2) iops,
                    ratio_to_report(iops) OVER() "%",
                    round(smalls / nullif(iops, 0), 4) smalls,
                    round(larges / nullif(iops, 0), 4) larges,
                    round(reads / nullif(iops, 0), 4) reads,
                    round(writes / nullif(iops, 0), 4) writes
            FROM   (SELECT  nvl(function_name,'--TOTAL--') function_name,
                            sum(wait_time * 1e3 * flag) / nullif(sum(number_of_waits * flag), 0) latency,
                            sum(number_of_waits * flag / secs) ios,
                            sum((small_read_megabytes + large_read_megabytes + small_write_megabytes + large_write_megabytes) * 1024 * 1024 * flag / secs) mbps,
                            sum((small_read_reqs + small_write_reqs + large_read_reqs + large_write_reqs) * flag / secs) iops,
                            sum((small_read_reqs + small_write_reqs) * flag / secs) smalls,
                            sum((large_read_reqs + large_write_reqs) * flag / secs) larges,
                            sum((small_read_reqs + large_read_reqs) * flag / secs) reads,
                            sum((small_write_reqs + large_write_reqs) * flag / secs) writes
                    FROM    (SELECT * FROM dba_hist_iostat_function NATURAL JOIN(&snaps)) a
                    WHERE  dbid=:DBID
                    GROUP  BY ROLLUP(function_name))
            WHERE  greatest(mbps, iops) > 0
            ORDER  BY iops DESC
        ]],
        '-',
        [[grid={topic="DBA_HIST_SYSTEM_EVENT (Per Second)"}
            WITH time_model AS
             (SELECT hs1.*, sum(p.value) OVER(PARTITION BY hs1.dbid, hs1.snap_id) cpu_count
              FROM   (SELECT * FROM dba_hist_sys_time_model NATURAL JOIN(&snaps)) hs1, dba_hist_parameter p
              WHERE  hs1.dbid=:dbid
              AND    hs1.snap_id = p.snap_id(+)
              AND    hs1.instance_number = p.instance_number(+)
              AND    hs1.dbid = p.dbid(+)
              AND    p.parameter_name(+) = 'cpu_count'
              AND    hs1.stat_name IN ('DB time', 'DB CPU', 'background cpu time')),
            db_time AS
             (SELECT /*+materialize*/
                      sum(value * flag) db_time
              FROM   time_model
              WHERE  stat_name = 'DB time')
            SELECT '- * ON CPU *' event,
                   NULL wait_class,
                   max(cpu_count) counts,
                   NULL timeouts,
                   sum(value * flag/secs)  waited,
                   round(sum(value * flag) / max(db_time)*100,2) "% DB",
                   round(sum(value * flag/secs) / max(cpu_count), 2) avg_wait
            FROM   time_model a,db_time
            WHERE  stat_name != 'DB time'
            UNION ALL
            SELECT *
            FROM   (SELECT nvl(event_name, '- Wait Class: ' || nvl(wait_class, 'All')) event,
                           nvl2(event_name, wait_class, ''),
                           sum(total_waits * flag/secs) counts,
                           sum(total_timeouts * flag) / nullif(sum(total_waits * flag), 0) timeouts,
                           round(sum(time_waited_micro * flag/secs), 2)  waited,
                           round(sum(time_waited_micro * flag) / (SELECT db_time FROM db_time b)*100,2) db_time,
                           round(sum(time_waited_micro * flag) / nullif(sum(total_waits * flag), 0), 2) avg_wait
                    FROM   (SELECT *
                            FROM   dba_hist_system_event NATURAL JOIN(&snaps)
                            WHERE  wait_class != 'Idle') a
                    GROUP  BY ROLLUP(wait_class, event_name)
                    HAVING sum(time_waited_micro * flag) > 0
                    ORDER  BY grouping_id(wait_class, event_name) DESC, abs(waited) DESC)
            WHERE  ROWNUM <= 30
        ]],
        
         &cell
        '|',
        [[grid={topic="DBA_HIST_SYSMETRIC_SUMMARY"}
            SELECT * 
            FROM (
                SELECT  metric_name,
                        round(max(maxval/div),2) "Max",
                        round(median(average/div),2) "Mid",
                        replace(initcap(regexp_substr(trim(metric_unit),'^\S+')),'Bytes','Megabytes') unit
                FROM (SELECT metric_name,metric_unit,
                             CASE WHEN instr(metric_unit,'%')>0 THEN max(maxval) ELSE 
                                sum(average)+max(maxval-average)+(sum(maxval-average)-max(maxval-average))/sqrt(count(1)) END maxval,
                             CASE WHEN instr(metric_unit,'%')>0 THEN avg(average) ELSE sum(average) END average,
                             CASE WHEN upper(trim(metric_unit)) LIKE 'BYTE%' THEN 1024*1024 ELSE 1 END div
                      FROM   dba_hist_sysmetric_summary a 
                      JOIN   (&snaps)  b
                      ON     a.snap_id BETWEEN minid+1 AND maxid
                      AND    a.dbid=b.dbid
                      AND    a.instance_number=b.instance_number
                      AND    a.metric_name NOT LIKE '% Per Txn'
                      AND    a.dbid=:dbid
                      WHERE  group_id=2
                      GROUP BY metric_name,metric_unit,a.snap_id,trunc(begin_time,'MI'))
                GROUP BY metric_name,metric_unit)
            WHERE "Mid">0
            ORDER BY unit,"Mid" DESC]]
    }
}