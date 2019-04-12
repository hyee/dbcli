/*[[Show database metrics within recent 10 minutes.  Usage: @@NAME [-h]
    -h: target views are gv$xxxmetric_history
    --[[
        @ver: 12={} 11={--}
        &opt:  default={} h={_HISTORY}
        &mins: default={1/144} h={84/1440}
        @cell: {
            12={'-',
                [[grid={topic="V$CELL_GLOBAL_HISTORY"}
                SELECT METRIC_NAME,
                       round(CASE
                                 WHEN TRIM(METRIC_TYPE) IN ('%', 'us') THEN
                                  SUM(METRIC_VALUE / div)/count(1)
                                 ELSE
                                  SUM(METRIC_VALUE / div / c)
                             END,
                             2) VALUE,
                       regexp_replace(METRIC_TYPE, 'bytes?', 'MB') unit,
                       COUNT(DISTINCT cell_hash) cells,
                       median(METRIC_VALUE / div) CELL_MED,
                       MIN(METRIC_VALUE / div) CELL_MIN,
                       MAX(METRIC_VALUE / div) CELL_MAX,
                       COUNT(1) snaps
                FROM   (SELECT a.*,
                               CASE
                                   WHEN METRIC_TYPE LIKE '%byte%' THEN
                                    1024 * 1024
                                   ELSE
                                    1
                               END div,
                               COUNT(DISTINCT begin_time) over(PARTITION BY cell_hash, metric_name) c
                        FROM   v$cell_global_history a
                        WHERE  METRIC_VALUE > 0
                        AND    END_TIME >= SYSDATE - &mins)
                GROUP  BY metric_name, metric_type
                ORDER  BY metric_type, VALUE DESC
                ]],
            } 
            default={}
        }
    --]]
]]*/
set sep4k on
COL WAITED,AVG_WAIT,CPU|TIME,CPU|QUEUE,DBTIM,ELA/CALL,CPU/CALL,DBTIME/CALL,read,write for usmhd2
col dbtime,SMALLS,READS,LARGES,WRITES,PCT,%,FG,CPU|UT,CPU|LIMIT for pct2
COL MBPS FOR KMG
COL CALLS,IOPS,WAITS,GOODNESS FOR TMB

grid {
    [[ grid={topic="GV$RSRCMGRMETRIC&opt (Per Second)"}
        SELECT  (SELECT NAME FROM V$RSRC_PLAN WHERE IS_TOP_PLAN='TRUE' AND ROWNUM<2) LAST_PLAN,
                CONSUMER_GROUP_NAME,
                round(SUM(NUM_CPUS/c)) "CPU|ALLOC",
                round(SUM(CPU_CONSUMED_TIME /c/ secs * 1e3)) "CPU|TIME",
                RATIO_TO_REPORT(sum(CPU_CONSUMED_TIME)) OVER() "%",
                round(SUM(CPU_WAIT_TIME /c/ secs * 1e3)) "CPU|QUEUE",
                round(SUM(AVG_CPU_UTILIZATION * CPU_CONSUMED_TIME) / NULLIF(SUM(CPU_CONSUMED_TIME), 0) / 100, 4) "CPU|UT",
                round(AVG(CPU_UTILIZATION_LIMIT) / 100, 4) "CPU|LIMIT",
                '|' "|",
                round(SUM(AVG_RUNNING_SESSIONS/c), 2) "SESSIONS|ACTIVE",
                round(SUM(AVG_WAITING_SESSIONS/c), 2) "SESSIONS|QUEUED",
                round(SUM(RUNNING_SESSIONS_LIMIT/c)) "SESSIONS|LIMIT",
                '|' "|",
                round(SUM(IO_MEGABYTES/c/ secs * 1024 * 1024), 2) MBPS,
                round(SUM(IO_REQUESTS /c/ secs), 2) IOPS,
                RATIO_TO_REPORT(sum(IO_MEGABYTES)) OVER() "%"
        &ver    ,'|' "|",
        &ver    round(SUM(AVG_ACTIVE_PARALLEL_STMTS/c), 2) "PX_STMT|ACTIVE",
        &ver    round(SUM(AVG_QUEUED_PARALLEL_STMTS/c), 2) "PX_STMT|QUEUED",
        &ver    round(SUM(AVG_ACTIVE_PARALLEL_SERVERS/c), 2) "PX_PROC|ACTIVE",
        &ver    round(SUM(AVG_QUEUED_PARALLEL_SERVERS/c), 2) "PX_PROC|QUEUED",
        &ver    round(SUM(PARALLEL_SERVERS_LIMIT/c)) "PX_PROC|LIMIT"
        FROM   (SELECT a.*, INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id) c FROM gv$rsrcmgrmetric&opt a)
        GROUP  BY CONSUMER_GROUP_NAME
        HAVING GREATEST(SUM(CPU_CONSUMED_TIME),SUM(IO_REQUESTS))>0
        ORDER  BY "CPU|TIME" desc,IOPS desc
    ]],
    '-', 
    {   
        [[ grid={topic="GV$SERVICEMETRIC&opt (Per Second)"}
            SELECT SERVICE_NAME,
                ROUND(SUM(CALLSPERSEC/c), 2) CALLS,
                ROUND(SUM(DBTIMEPERSEC/c), 2) DBTIM,
                RATIO_TO_REPORT(sum(DBTIMEPERSEC/c)) OVER() "%",
                ROUND(SUM(DBTIMEPERSEC * CALLSPERSEC) / SUM(CALLSPERSEC), 2) "DBTIME/CALL",
                ROUND(SUM(ELAPSEDPERCALL * CALLSPERSEC) / SUM(CALLSPERSEC), 2) "ELA/CALL",
                ROUND(SUM(CPUPERCALL * CALLSPERSEC) / SUM(CALLSPERSEC), 2) "CPU/CALL"
            FROM   (SELECT a.*, INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id) c FROM GV$SERVICEMETRIC&opt a WHERE GROUP_ID=6) a
            WHERE  CALLSPERSEC > 0
            GROUP  BY SERVICE_NAME
            ORDER  BY DBTIM DESC
        ]],
        '-',
        [[ grid={topic="GV$FILEMETRIC&opt"}
            SELECT TABLESPACE_NAME,
                    round(MBPS) MBPS,
                    round(IOPS, 2) iops,
                    round(ratio_to_report(iops) over(),4) "%",
                    round(reads / iops, 4) reads,
                    round(writes / iops, 4) writes,
                    '|' "|",
                    round((rt + wt) * 1e4 / iops,2) avg_wait,
                    round(rt * 1e4 / iops,2) read,
                    round(wt * 1e4 / iops,2) write
            FROM   (SELECT TABLESPACE_NAME,
                        SUM((PHYSICAL_READS + PHYSICAL_WRITES)/c/secs) IOPS,
                        SUM((PHYSICAL_BLOCK_READS + PHYSICAL_BLOCK_WRITES) *BYTES/blocks/c/secs) MBPS,
                        SUM((PHYSICAL_READS) /c/secs) reads,
                        SUM((PHYSICAL_WRITES) /c/secs) writes,
                        SUM(PHYSICAL_READS * AVERAGE_READ_TIME/c/secs) rt,
                        SUM(PHYSICAL_WRITES * AVERAGE_WRITE_TIME/c/secs) wt
                    FROM   (SELECT a.*, INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id) c FROM gv$filemetric&opt A)
                    JOIN   dba_Data_files
                    USING  (file_id)
                    GROUP  BY TABLESPACE_NAME)
            WHERE  round(IOPS) > 0
            ORDER  BY iops DESC
        ]],
        '-',
        [[ grid={topic="GV$IOFUNCMETRIC&opt"}
            SELECT  FUNCTION_NAME,
                    NULLIF(ROUND(LATENCY / NULLIF(IOS, 0),2),0) AVG_WAIT,
                    ROUND(MBPS) MBPS,
                    ROUND(IOPS, 2) IOPS,
                    RATIO_TO_REPORT(IOPS) OVER() "%",
                    ROUND(SMALLS / NULLIF(IOPS, 0), 4) SMALLS,
                    ROUND(LARGES / NULLIF(IOPS, 0), 4) LARGES,
                    ROUND(READS / NULLIF(IOPS, 0), 4) READS,
                    ROUND(WRITES / NULLIF(IOPS, 0), 4) WRITES
            FROM   (SELECT FUNCTION_NAME,
                        SUM((AVG_WAIT_TIME * (SMALL_READ_IOPS + SMALL_WRITE_IOPS + LARGE_READ_IOPS + LARGE_WRITE_IOPS)) * 1e3) LATENCY,
                        SUM((SMALL_READ_MBPS + LARGE_READ_MBPS + SMALL_WRITE_MBPS + LARGE_WRITE_MBPS) * 1024 * 1024/c) MBPS,
                        SUM((SMALL_READ_IOPS + SMALL_WRITE_IOPS + LARGE_READ_IOPS + LARGE_WRITE_IOPS)/c) IOPS,
                        SUM(decode(AVG_WAIT_TIME,0,0,SMALL_READ_IOPS + SMALL_WRITE_IOPS + LARGE_READ_IOPS + LARGE_WRITE_IOPS)) IOS,
                        SUM((SMALL_READ_IOPS + SMALL_WRITE_IOPS)/c) SMALLS,
                        SUM((LARGE_READ_IOPS + LARGE_WRITE_IOPS)/c) LARGES,
                        SUM((SMALL_READ_IOPS + LARGE_READ_IOPS)/c) READS,
                        SUM((SMALL_WRITE_IOPS + LARGE_WRITE_IOPS)/c) WRITES
                    FROM   (SELECT a.*, INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id) c FROM gv$iofuncmetric&opt a)
                    GROUP  BY FUNCTION_NAME)
            WHERE GREATEST(MBPS,IOPS) >0 
            ORDER  BY IOPS DESC
        ]],
        '-',
        [[grid={topic="GV$WAITCLASSMETRIC&opt (Per Second)"}
            SELECT WAIT_CLASS,
                ROUND(SUM(DBTIME_IN_WAIT * TIME_WAITED) / NULLIF(SUM(TIME_WAITED), 0)/100, 4) DBTIME,
                '|' "|",
                ROUND(SUM(TIME_WAITED /c/secs) * 1E4) WAITED,
                RATIO_TO_REPORT(SUM(TIME_WAITED)) OVER() "%",
                ROUND(SUM(TIME_WAITED_FG)/NULLIF(SUM(TIME_WAITED),0),4) FG,
                '|' "|",
                ROUND(SUM(WAIT_COUNT/c/secs), 2) WAITS,
                ROUND(SUM(WAIT_COUNT_FG)/NULLIF(SUM(WAIT_COUNT),0),4) FG,
                '|' "|",
                ROUND(1E4 * SUM(TIME_WAITED) / NULLIF(SUM(WAIT_COUNT), 0),2) AVG_WAIT,
                SUM(AVERAGE_WAITER_COUNT/c) WAITERS
            FROM   (SELECT a.*, INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id) c FROM gv$waitclassmetric&opt a)
            JOIN   (SELECT DISTINCT WAIT_CLASS#, WAIT_CLASS FROM v$event_name)
            USING  (WAIT_CLASS#)
            GROUP  BY WAIT_CLASS
            HAVING ROUND(SUM(WAIT_COUNT /c/ secs), 2)>0
            ORDER  BY WAITED DESC
        ]],
        '-',
        [[grid={topic="GV$EVENTMETRIC (Per Second)"}
            SELECT *
            FROM   (SELECT wait_class,
                        event,
                        ROUND(SUM(DBTIME_IN_WAIT * TIME_WAITED) / NULLIF(SUM(total_Wait), 0)/100, 4) DBTIME,
                        round(SUM(TIME_WAITED) / nullif(SUM(WAIT_COUNT), 0) * 1e4, 2) avg_Wait,
                        round(SUM(TIME_WAITED / INTSIZE_CSEC) * 1E6,2) WAITED,
                        round(SUM(WAIT_COUNT / INTSIZE_CSEC) * 100, 2) WAITS,
                        round(SUM(NUM_SESS_WAITING), 2) SESS
                    FROM   gv$eventmetric
                    JOIN   (SELECT DISTINCT wait_class,wait_class#, event#, SUBSTR(NAME,1,40) event FROM v$event_name WHERE wait_class != 'Idle')
                    USING  (event#)
                    JOIN   (select inst_id,wait_class#, DBTIME_IN_WAIT,TIME_WAITED total_Wait from gv$waitclassmetric) 
                    USING  (inst_id,wait_class#)
                    GROUP  BY wait_class, event
                    HAVING round(SUM(TIME_WAITED / INTSIZE_CSEC) * 1E6) > 0
                    ORDER  BY WAITED DESC)
            WHERE  rownum <= 50
        ]], &cell
        '|',
        [[grid={topic="GV$SYSMETRIC&opt"}
            SELECT * FROM (
                SELECT  METRIC_NAME,
                        ROUND(
                            case when instr(METRIC_UNIT,'%')>0 or metric_name like '%Average%' then 
                                 AVG(value/div)
                            else sum(value/c/div)
                            end
                        ,3) VALUE,
                        replace(INITCAP(regexp_substr(TRIM(METRIC_UNIT),'^\S+')),'Bytes','Megabtyes') UNIT,
                        round(median(value/div),3) "Med",
                        round(min(value/div),3) "Min",
                        round(max(value/div),3) "Max"
                FROM (SELECT a.*, 
                             INTSIZE_CSEC / 100 secs,count(distinct begin_time) over(partition by inst_id,METRIC_NAME) c,
                             case when upper(trim(METRIC_UNIT)) like 'BYTE%' then 1024*1024 else 1 end div
                      FROM   gv$sysmetric&opt A 
                      WHERE  group_id=2
                      AND    value >0 )
                GROUP BY METRIC_NAME,METRIC_UNIT)
            ORDER BY UNIT,value desc]]
    }
}