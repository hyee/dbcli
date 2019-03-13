/*[[Show AWR metric. Usage: @@NAME [yymmddhh24mi] [yymmddhh24mi] [instances]

 -h: target views are gv$xxxmetric_history
    --[[
        @ver: 12={} 11={--}
        &opt:  default={} h={_HISTORY}
        &mins: default={1/144} h={84/1440}
        &v1: default={&starttime}
        &v2: default={&endtime}
        @cell: {
            12={
				'-',
				[[grid={topic="DBA_HIST_CELL_GLOBAL (Per Second)",max_rows=50}
				SELECT NAME, round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) / (0 + '&dur'), 2) VALUE
				FROM   (SELECT metric_name,
							SUM(metric_value * decode(snap_id, 0+'&bs', -1, 1)) metric_value,
							REPLACE(metric_name, 'bytes', 'megabytes') NAME
						FROM   dba_hist_cell_global a
						WHERE  snap_id IN ('&bs', '&es')
						AND    metric_value > 0
						GROUP  BY metric_name)
				WHERE  round(metric_value / decode(NAME, metric_name, 1, 1024 * 1024) / (0 + '&dur'), 2) > 0
				ORDER  BY VALUE DESC
				]],
			} 
            default={}
        }
    --]]
]]*/
set sep4k on feed off

col bs1 new_value bs1
col bs new_value bs
col es new_value es
col dur new_value dur
col bt new_value bt
col st new_value st

set termout off
select a.* from (
	select min(snap_id) bs1,
	       min(case when s.end_interval_time >= nvl(to_date(:v1,'YYMMDDHH24MI'),SYSDATE - 7) then snap_id end) bs,
	       max(snap_id) es,
		   to_char(min(case when s.end_interval_time >= nvl(to_date(:v1,'YYMMDDHH24MI'),SYSDATE - 7) then end_interval_time end),'YYYY-MM-DD HH24:MI:SS') bt,
		   to_char(max(end_interval_time),'YYYY-MM-DD HH24:MI:SS') st,
	       nullif(round(86400*(max(end_interval_time+0)-min(case when s.end_interval_time >= nvl(to_date(:v1,'YYMMDDHH24MI'),SYSDATE - 7) then end_interval_time+0 end))),0) dur
	from  dba_hist_snapshot s
	where (:v3 is null or instr(',&v3,',','||instance_number||',')>0) 
	and   s.end_interval_time BETWEEN nvl(to_date(:v1,'YYMMDDHH24MI')-1.1/24,SYSDATE - 7) AND nvl(to_date(:V2,'YYMMDDHH24MI'),SYSDATE)
	group by startup_time
	order by es desc,bs desc) a
where rownum<2;
set termout on


COL WAITED,AVG_WAIT,CPU|TIME,CPU|QUEUE,DBTIM,ELA/CALL,CPU/CALL,DBTIME/CALL,read,write for usmhd2
col dbtime,SMALLS,READS,LARGES,WRITES,PCT,%,FG,CPU|UT,CPU|LIMIT for pct2
COL MBPS,phyrds,phywrs,redo FOR KMG
COL CALLS,EXEC,COMMITS,ROLLBACKS,IOS_WAIT,IOPS,WAITS,GOODNESS,AAS,OPTIMAL,MULTIPASS,ONEPASS FOR TMB
col sql,io,cpu,parse,cc,cl,app,gccu,gccr for pct2
PRO Time Range: &BT ~~~ &ST
PRO =======================================================
grid {
    [[ grid={topic="DBA_HIST_SERVICE_STAT (Per Second)"}
        SELECT *
		FROM   (SELECT service_name,
		               stat_name,
		               CASE
		                   WHEN stat_name LIKE '%time%' AND stat_name != 'DB time' OR stat_name='DB CPU' THEN
		                        ROUND(VALUE / NULLIF(MAX(DECODE(stat_name, 'DB time', VALUE)) OVER(PARTITION BY service_name), 0), 4)
		                   ELSE
		                        VALUE
		               END val
		        FROM   (SELECT nvl(service_name,'--TOTAL--') service_name, stat_name, 
				               round(SUM(DECODE(snap_id, 0+'&bs', -1, 1) * VALUE *
							   case when stat_name LIKE 'physical%' THEN  
							      (select 0+value from dba_hist_parameter b where a.dbid=b.dbid and b.parameter_name='db_block_size' and rownum<2) ELSE 1 END
							   ) / '&dur', 2) VALUE
		                FROM   DBA_HIST_SERVICE_STAT a
		                WHERE  snap_id IN ('&bs', '&es')
		                AND    ('&v3' is null or  instr(',&v3,',','||instance_number||',')>0) 
		                GROUP  BY stat_name,rollup(service_name)
		                HAVING round(SUM(DECODE(snap_id, 0+'&bs', -1, 1) * VALUE) / '&dur', 2) > 0) a)
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
		ORDER BY DBTIM DESC
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
					FROM   (SELECT a.*, DECODE(snap_id, 0 + '&es', 1, -1) flag, 0 + '&dur' secs 
					        FROM dba_hist_iostat_function a
							WHERE  snap_id IN ('&bs', '&es')
			                AND    ('&v3' IS NULL OR instr(',&v3,', ',' || instance_number || ',') > 0))
					GROUP  BY ROLLUP(FUNCTION_NAME))
			WHERE  GREATEST(MBPS, IOPS) > 0
			ORDER  BY IOPS DESC
        ]],
       
        '-',
        [[grid={topic="DBA_HIST_SYSTEM_EVENT (Per Second)"}
			WITH time_model AS
			 (SELECT hs1.*, DECODE(hs1.snap_id, 0 + '&es', 1, -1) flag, 0 + '&dur' secs, SUM(p.value) over(PARTITION BY hs1.dbid, hs1.snap_id) cpu_count
			  FROM   dba_hist_sys_time_model hs1, dba_hist_parameter p
			  WHERE  hs1.snap_id = p.snap_id(+)
			  AND    hs1.instance_number = p.instance_number(+)
			  AND    hs1.dbid = p.dbid(+)
			  AND    p.parameter_name(+) = 'cpu_count'
			  AND    ('&v3' IS NULL OR instr(',&v3,', ',' || hs1.instance_number || ',') > 0)
			  AND    hs1.stat_name IN ('DB time', 'DB CPU', 'background cpu time')
			  AND    hs1.snap_id IN ('&bs', '&es')),
			db_time AS
			 (SELECT /*+materialize*/
			          SUM(VALUE * flag) db_time
			  FROM   time_model
			  WHERE  stat_name = 'DB time')
			SELECT '- * ON CPU *' event,
			       NULL wait_class,
			       MAX(cpu_count) counts,
			       NULL timeouts,
			       SUM(VALUE * flag) / MAX(secs) waited,
			       round(SUM(VALUE * flag) / max(db_time)*100,2) "% DB",
			       round(SUM(VALUE * flag) / MAX(secs) / MAX(cpu_count), 2) avg_wait
			FROM   time_model a,db_time
			WHERE  stat_name != 'DB time'
			UNION ALL
			SELECT *
			FROM   (SELECT nvl(event_name, '- Wait Class: ' || nvl(wait_class, 'All')) event,
			               nvl2(event_name, wait_class, ''),
			               SUM(total_Waits * flag) / MAX(secs) counts,
			               SUM(total_timeouts * flag) / nullif(SUM(total_Waits * flag), 0) timeouts,
			               round(SUM(time_waited_micro * flag), 2) / MAX(secs) waited,
			               round(SUM(time_waited_micro * flag) / (SELECT db_time FROM db_time b)*100,2) db_time,
			               round(SUM(time_waited_micro * flag) / nullif(SUM(total_Waits * flag), 0), 2) avg_wait
			        FROM   (SELECT hs1.*, DECODE(hs1.snap_id, 0 + '&es', 1, -1) flag, 0 + '&dur' secs
			                FROM   dba_hist_system_event hs1
			                WHERE  snap_id IN ('&bs', '&es')
			                AND    ('&v3' IS NULL OR instr(',&v3,', ',' || hs1.instance_number || ',') > 0)
			                AND    wait_class != 'Idle') a
			        GROUP  BY ROLLUP(wait_class, event_name)
			        HAVING SUM(time_waited_micro * flag) > 0
			        ORDER  BY grouping_id(wait_class, event_name) DESC, abs(waited) DESC)
			WHERE  ROWNUM <= 30
        ]],
		'-',
		[[  grid={topic="DBA_HIST_ACTIVE_SESS_HISTORY"}
			SELECT aas, pct, program, event, sql_id, top_wait_obj
			FROM   (SELECT a.*,
						   first_value(nvl2(curr_obj#, curr_obj# || ' (' || aas || ')', '')) over(PARTITION BY program, event, sql_id ORDER BY nvl2(curr_obj#, 0, 1), aas DESC) top_wait_obj
					FROM   (SELECT  SUM(1) aas,
								    round(ratio_to_report(SUM(1)) over(), 4) pct,
									program,
									event,
									sql_id,
									curr_obj#,
									grouping_id(curr_obj#) gid
							FROM   (SELECT CASE
											WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
												REGEXP_REPLACE(SUBSTR(a.program, INSTR(a.program, '(')), '\d', 'n')
										END program,
										nvl(event,
											nvl2(NULLIF(TRIM(p1text),'p1'),
													'[' || TRIM(p1text) || nullif('|' || TRIM(p2text), '|') ||
													nullif('|' || TRIM(p3text), '|') || ']',
													'ON CPU')) event,
										nvl(sql_id, top_level_sql_id) sql_id,
										CASE
											WHEN current_obj# > 0 THEN
												'' || current_obj#
											WHEN p3text = '100*mode+namespace' AND p3 > power(2, 32) THEN
												'' || trunc(p3 / power(2, 32))
											WHEN p3text LIKE '%namespace' THEN
												'x$kglst#' || trunc(MOD(p3, power(2, 32)) / power(2, 16))
											WHEN p1text LIKE 'cache id' THEN
												(SELECT MAX(parameter) FROM v$rowcache WHERE cache# = p1)
											WHEN p1text = 'idn' THEN
												'v$db_object_cache hash#' || p1
											WHEN a.event LIKE 'latch%' AND p2text = 'number' THEN
												(SELECT MAX(NAME) FROM v$latchname WHERE latch# = p2)
										END curr_obj#
									FROM   dba_hist_Active_Sess_history a
									WHERE  snap_id between '&bs'+0 and '&es'+0
			                        AND    ('&v3' IS NULL OR instr(',&v3,', ',' || instance_number || ',') > 0))
							GROUP  BY program, event, sql_id, ROLLUP(curr_obj#)
							ORDER  BY pct DESC) a)
			WHERE  gid = 1
			AND    rownum <= 30
			AND    pct > 0
			ORDER  BY pct DESC
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
                             INTSIZE / 100 secs,count(distinct begin_time) over(partition by instance_number,METRIC_NAME) c,
                             case when upper(trim(METRIC_UNIT)) like 'BYTE%' then 1024*1024 else 1 end div
                      FROM   dba_hist_sysmetric_summary A 
                      WHERE  group_id=2
                      AND    AVERAGE >0
                      AND    ('&v3' is null or  instr(',&v3,',','||instance_number||',')>0) 
                      AND    snap_id between  '&bs'+0 and '&es'+0)
                GROUP BY METRIC_NAME,METRIC_UNIT)
			WHERE VALUE>0
            ORDER BY UNIT,value desc]]
    }
}