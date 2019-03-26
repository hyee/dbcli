/*[[Show AWR metric. Usage: @@NAME [yymmddhh24mi] [yymmddhh24mi] [instances]

 -h: target views are gv$xxxmetric_history
    --[[
        @ver: 11={} 10={--}
        &opt:  default={} h={_HISTORY}
        &mins: default={1/144} h={84/1440}
        &v1: default={&starttime}
        &v2: default={&endtime}
        @cell: {
            12={
				'-',
				[[grid={topic="DBA_HIST_CELL_GLOBAL (Per Second)",max_rows=50,bypassemptyrs='on'}
				SELECT NAME, round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) , 2) VALUE
				FROM   (SELECT metric_name, NAME, SUM(metric_value/secs) metric_value
				        FROM   (SELECT metric_name,
				                       metric_value v,
				                       secs,
				                       metric_value - lag(metric_value) over(PARTITION BY a.dbid, cell_hash, INCARNATION_NUM, metric_name ORDER BY a.snap_id) metric_value,
				                       REPLACE(metric_name, 'bytes', 'megabytes') NAME
				                FROM  (select * from (&snaps) where instance_number=1) , dba_hist_cell_global a
				                WHERE  a.snap_id between minid+1 and maxid)
				        GROUP  BY metric_name, NAME)
				WHERE  round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) , 2) > 0
				ORDER  BY VALUE DESC
				]],
			} 
            default={}
        }
    --]]
]]*/
set sep4k on feed off verify off

var snaps varchar2(4000);
BEGIN
	:snaps := q'[
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
		        WHERE  ('&3' IS NULL OR instr(',&v3,', ',' || instance_number || ',') > 0)
		        AND    s.end_interval_time BETWEEN nvl(to_date('&1', 'YYMMDDHH24MI') - 1.1 / 24, SYSDATE - 7) AND
		               nvl(to_date('&2', 'YYMMDDHH24MI'), SYSDATE)) a
		WHERE  minid < maxid
		AND    snap_id IN (minid, maxid)]';
END;
/

COL WAITED,AVG_WAIT,CPU|TIME,CPU|QUEUE,DBTIM,ELA/CALL,CPU/CALL,DBTIME/CALL,read,write for usmhd2
col dbtime,SMALLS,READS,LARGES,WRITES,PCT,%,FG,CPU|UT,CPU|LIMIT for pct2
COL MBPS,phyrds,phywrs,redo FOR KMG
COL CALLS,EXEC,COMMITS,ROLLBACKS,IOS_WAIT,IOPS,WAITS,GOODNESS,AAS,OPTIMAL,MULTIPASS,ONEPASS FOR TMB
col sql,io,cpu,parse,cc,cl,app,gccu,gccr for pct2

grid {
    [[ grid={topic="DBA_HIST_SERVICE_STAT (Per Second)"}
		SELECT *
		FROM   (SELECT service_name,
		               &ver insts,
		               stat_name,
		               CASE
		                   WHEN stat_name LIKE '%time%' AND stat_name != 'DB time' OR stat_name = 'DB CPU' THEN
		                    ROUND(VALUE / NULLIF(MAX(DECODE(stat_name, 'DB time', VALUE)) OVER(PARTITION BY service_name), 0), 4)
		                   ELSE
		                    VALUE
		               END val
		        FROM   (SELECT nvl(service_name, '--TOTAL--') service_name,
							   &ver nvl2(service_name,sys.stragg(DISTINCT instance_number||','),'') insts,
		                       stat_name,
		                       round(SUM(flag * VALUE / secs * CASE
		                                     WHEN stat_name LIKE 'physical%' THEN
		                                      (SELECT 0 + VALUE
		                                       FROM   dba_hist_parameter b
		                                       WHERE  a.dbid = b.dbid
		                                       AND    b.parameter_name = 'db_block_size'
		                                       AND    rownum < 2)
											 WHEN stat_name like 'gc %time' THEN
											   10000
		                                     ELSE
		                                       1
		                                 END),
		                             2) VALUE
		                FROM    (SELECT * FROM DBA_HIST_SERVICE_STAT NATURAL JOIN(&snaps)) a
		                GROUP  BY stat_name, ROLLUP(service_name)
		                HAVING round(SUM(flag * VALUE / secs), 2) > 0) a)
		PIVOT(MAX(val)
		FOR    stat_name IN('logons cumulative' logons,
		                    'physical reads' phyrds,
		                    'physical writes' phywrs,
		                    'redo size' redo,
		                    'DB time' DBTIM,
		                    'sql execute elapsed time' SQL,
		                    'user I/O wait time' io,
		                    'DB CPU' CPU,
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
		                    'workarea executions - optimal' OPTIMAL,
		                    'workarea executions - multipass' multipass,
		                    'workarea executions - onepass' onepass))
		ORDER  BY DBTIM DESC
    ]],
    '-', 
    {   
        [[ grid={topic="DBA_HIST_IOSTAT_FUNCTION"}
			SELECT  FUNCTION_NAME,
					NULLIF(ROUND(LATENCY, 2), 0) AVG_WAIT,
					ROUND(IOS,2) IOS_WAIT,
					ROUND(MBPS, 2) MBPS,
					ROUND(IOPS, 2) IOPS,
					RATIO_TO_REPORT(IOPS) OVER() "%",
					ROUND(SMALLS / NULLIF(IOPS, 0), 4) SMALLS,
					ROUND(LARGES / NULLIF(IOPS, 0), 4) LARGES,
					ROUND(READS / NULLIF(IOPS, 0), 4) READS,
					ROUND(WRITES / NULLIF(IOPS, 0), 4) WRITES
			FROM   (SELECT  nvl(FUNCTION_NAME,'--TOTAL--') FUNCTION_NAME,
							SUM(WAIT_TIME * 1e3 * flag) / nullif(SUM(NUMBER_OF_WAITS * flag), 0) LATENCY,
							SUM(NUMBER_OF_WAITS * flag / secs) IOS,
							SUM((SMALL_READ_MEGABYTES + LARGE_READ_MEGABYTES + SMALL_WRITE_MEGABYTES + LARGE_WRITE_MEGABYTES) * 1024 * 1024 * flag / secs) MBPS,
							SUM((SMALL_READ_REQS + SMALL_WRITE_REQS + LARGE_READ_REQS + LARGE_WRITE_REQS) * flag / secs) IOPS,
							SUM((SMALL_READ_REQS + SMALL_WRITE_REQS) * flag / secs) SMALLS,
							SUM((LARGE_READ_REQS + LARGE_WRITE_REQS) * flag / secs) LARGES,
							SUM((SMALL_READ_REQS + LARGE_READ_REQS) * flag / secs) READS,
							SUM((SMALL_WRITE_REQS + LARGE_WRITE_REQS) * flag / secs) WRITES
					FROM    (SELECT * FROM dba_hist_iostat_function NATURAL JOIN(&snaps)) a
					GROUP  BY ROLLUP(FUNCTION_NAME))
			WHERE  GREATEST(MBPS, IOPS) > 0
			ORDER  BY IOPS DESC
        ]],
        '-',
        [[grid={topic="DBA_HIST_SYSTEM_EVENT (Per Second)"}
			WITH time_model AS
			 (SELECT hs1.*, SUM(p.value) over(PARTITION BY hs1.dbid, hs1.snap_id) cpu_count
			  FROM   (select * from dba_hist_sys_time_model NATURAL JOIN(&snaps)) hs1, dba_hist_parameter p
			  WHERE  hs1.snap_id = p.snap_id(+)
			  AND    hs1.instance_number = p.instance_number(+)
			  AND    hs1.dbid = p.dbid(+)
			  AND    p.parameter_name(+) = 'cpu_count'
			  AND    hs1.stat_name IN ('DB time', 'DB CPU', 'background cpu time')),
			db_time AS
			 (SELECT /*+materialize*/
			          SUM(VALUE * flag) db_time
			  FROM   time_model
			  WHERE  stat_name = 'DB time')
			SELECT '- * ON CPU *' event,
			       NULL wait_class,
			       MAX(cpu_count) counts,
			       NULL timeouts,
			       SUM(VALUE * flag/secs)  waited,
			       round(SUM(VALUE * flag) / max(db_time)*100,2) "% DB",
			       round(SUM(VALUE * flag/secs) / MAX(cpu_count), 2) avg_wait
			FROM   time_model a,db_time
			WHERE  stat_name != 'DB time'
			UNION ALL
			SELECT *
			FROM   (SELECT nvl(event_name, '- Wait Class: ' || nvl(wait_class, 'All')) event,
			               nvl2(event_name, wait_class, ''),
			               SUM(total_Waits * flag/secs) counts,
			               SUM(total_timeouts * flag) / nullif(SUM(total_Waits * flag), 0) timeouts,
			               round(SUM(time_waited_micro * flag/secs), 2)  waited,
			               round(SUM(time_waited_micro * flag) / (SELECT db_time FROM db_time b)*100,2) db_time,
			               round(SUM(time_waited_micro * flag) / nullif(SUM(total_Waits * flag), 0), 2) avg_wait
			        FROM   (SELECT *
			                FROM   dba_hist_system_event NATURAL JOIN(&snaps)
			                WHERE  wait_class != 'Idle') a
			        GROUP  BY ROLLUP(wait_class, event_name)
			        HAVING SUM(time_waited_micro * flag) > 0
			        ORDER  BY grouping_id(wait_class, event_name) DESC, abs(waited) DESC)
			WHERE  ROWNUM <= 30
        ]],
		
		 &cell
        '|',
        [[grid={topic="DBA_HIST_SYSMETRIC_SUMMARY"}
            SELECT * FROM (
                SELECT  METRIC_NAME,
                        ROUND(
                            case when instr(METRIC_UNIT,'%')>0 then 
                                 AVG(AVERAGE/div)
                            else sum(AVERAGE/c/div)
                            end
                        ,2) VALUE,
                        replace(INITCAP(regexp_substr(TRIM(METRIC_UNIT),'^\S+')),'Bytes','Megabtyes') UNIT
                FROM (SELECT a.*, 
                             INTSIZE / 100 secs,count(distinct begin_time) over(partition by a.instance_number,METRIC_NAME) c,
                             case when upper(trim(METRIC_UNIT)) like 'BYTE%' then 1024*1024 else 1 end div
                      FROM   dba_hist_sysmetric_summary A 
                      JOIN   (&snaps)  b
					  ON     a.snap_id between minid+1 and maxid
					  AND    a.dbid=b.dbid
					  AND    a.instance_number=b.instance_number
                      WHERE  group_id=2
                      AND    AVERAGE >0)
                GROUP BY METRIC_NAME,METRIC_UNIT)
			WHERE VALUE>0
            ORDER BY UNIT,value desc]]
    }
}