/*[[
  Show current top activities
  --[[
    @ALIAS: TOP
    @VERSION: 11.0={}
  --]]
]]*/
-- db info
SET feed off digits 3
/* oratop s0a*/
PROMPT DB INFO:
PROMPT ========
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */*
FROM   (SELECT sys_context('USERENV', 'DB_UNIQUE_NAME') dbnm FROM dual),
       (SELECT name
         FROM   v$active_services
         WHERE  name = (SELECT service_name FROM v$session WHERE sid = (SELECT sys_context('USERENV', 'SID') FROM dual))
         UNION  ALL
         SELECT 'SYS$USERS'
         FROM   dual
         WHERE  NOT EXISTS (SELECT name
                 FROM   v$active_services
                 WHERE  name = (SELECT service_name FROM v$session WHERE sid = (SELECT sys_context('USERENV', 'SID') FROM dual)))),
       (SELECT to_number(substr(banner, 17, 2)) vers, substr(banner, 17, 3) cver FROM v$version WHERE substr(banner, 1, 3) = 'Ora'),
       (SELECT substr(upper(value), 1, 5) typd FROM v$parameter WHERE name = 'instance_type'),
       (SELECT decode(value, 'BASIC', 1, 0) stlv FROM v$parameter WHERE name = 'statistics_level'), (SELECT count(*) dasm FROM v$asm_diskgroup);

-- memory configuration
/* oratop s1 */
PROMPT CONFIGURATION:
PROMPT ==============
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */ *
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          sum(value) taas
         FROM   gv$sysmetric
         WHERE  metric_name = 'Database Time Per Sec'
         AND    group_id = 3),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          count(*) sess, count(DISTINCT username) duser
         FROM   gv$session
         WHERE  type <> 'BACKGROUND'
         AND    username IS NOT NULL
         AND    schema# != 0),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          to_char(max(end_time), 'hh24:mi:ss') dbts, sum(value) spga
         FROM   gv$sysmetric
         WHERE  metric_name = 'Total PGA Allocated'
         AND    group_id = 3), (SELECT (sysdate - startup_time) * 86400 uptm FROM v$instance),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          sum(value) scpu, count(DISTINCT inst_id) inst
         FROM   gv$osstat
         WHERE  stat_name = 'NUM_CPUS'),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          sum(value) ssga
         FROM   gv$sga),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          sum(value) prob
         FROM   gv$diag_info
         WHERE  name = 'Active Problem Count'),
       (SELECT sum(fra) reco FROM (SELECT space_used / greatest(space_limit, 1) * 100 fra FROM v$recovery_file_dest UNION SELECT 0 fra FROM dual)),
       (SELECT initcap(substr(sys_context('USERENV', 'DATABASE_ROLE'), -7, 16)) dbro FROM dual),
       (SELECT sum(ar) dgar
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   sofar ar
                  FROM   gv$recovery_progress
                  WHERE  type = 'Media Recovery'
                  AND    item = 'Active Apply Rate'
                  AND    rownum = 1
                  UNION
                  SELECT 0 ar
                  FROM   dual)),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          max(value) pgag
         FROM   gv$pgastat
         WHERE  name = 'aggregate PGA target parameter');

-- load details
/* oratop s2 */
PROMPT LOAD DETAILS:
PROMPT =============
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 inid, hcpu, sgfr, utps, ucps, saas, mbps, ssrt, iorl, load, upga, aspq, dbcp, dbwa, iops, asct, isct, cpas, ioas, waas, dcpu, ncpu, logr, phyr, phyw,
 temp, dbtm
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id inid, sum(decode(metric_name, 'CPU Usage Per Sec', value, 0)) dcpu,
          sum(decode(metric_name, 'Host CPU Utilization (%)', value, 0)) hcpu, sum(decode(metric_name, 'I/O Megabytes per Second', value, 0)) mbps,
          sum(decode(metric_name, 'SQL Service Response Time', value, 0)) ssrt,
          sum(decode(metric_name, 'Average Synchronous Single-Block Read Latency', value, 0)) iorl,
          sum(decode(metric_name, 'Current OS Load', value, 0)) load, sum(decode(metric_name, 'Active Parallel Sessions', value, 0)) aspq,
          sum(decode(metric_name, 'Database CPU Time Ratio', value, 0)) dbcp, sum(decode(metric_name, 'Database Wait Time Ratio', value, 0)) dbwa,
          sum(decode(metric_name, 'I/O Requests per Second', value, 0)) iops
         FROM   gv$sysmetric
         WHERE  metric_name IN ('CPU Usage Per Sec', 'Host CPU Utilization (%)', 'I/O Megabytes per Second', 'SQL Service Response Time',
                                'Average Synchronous Single-Block Read Latency', 'Current OS Load', 'Active Parallel Sessions', 'Database CPU Time Ratio',
                                'Database Wait Time Ratio', 'I/O Requests per Second')
         AND    group_id = 2
         GROUP  BY inst_id),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id id1, sum(decode(metric_name, 'Shared Pool Free %', value, 0)) sgfr,
          sum(decode(metric_name, 'User Transaction Per Sec', value, 0)) utps, sum(decode(metric_name, 'User Calls Per Sec', value, 0)) ucps,
          sum(decode(metric_name, 'Average Active Sessions', value, 0)) saas, sum(decode(metric_name, 'Total PGA Allocated', value, 0)) upga,
          sum(decode(metric_name, 'Logical Reads Per Sec', value, 0)) logr, sum(decode(metric_name, 'Physical Reads Per Sec', value, 0)) phyr,
          sum(decode(metric_name, 'Physical Writes Per Sec', value, 0)) phyw, sum(decode(metric_name, 'Temp Space Used', value, 0)) temp,
          sum(decode(metric_name, 'Database Time Per Sec', value, 0)) dbtm
         FROM   gv$sysmetric
         WHERE  metric_name IN
                ('Shared Pool Free %', 'User Transaction Per Sec', 'User Calls Per Sec', 'Logical Reads Per Sec', 'Physical Reads Per Sec',
                 'Physical Writes Per Sec', 'Temp Space Used', 'Database Time Per Sec', 'Average Active Sessions', 'Total PGA Allocated')
         AND    group_id = 3
         GROUP  BY inst_id),
       (SELECT id2, sum(asct) asct, sum(isct) isct, sum(cpas) cpas, sum(ioas) ioas, sum(waas) waas
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   inst_id id2, sum(decode(status, 'ACTIVE', 1, 0)) asct, count(*) isct, sum(decode(status, 'ACTIVE', decode(wait_time, 0, 0, 1), 0)) cpas,
                   sum(decode(status, 'ACTIVE', decode(wait_class, 'User I/O', 1, 0), 0)) ioas,
                   sum(decode(status, 'ACTIVE', decode(wait_time, 0, decode(wait_class, 'User I/O', 0, 1), 0), 0)) waas
                  FROM   gv$session
                  WHERE  type <> 'BACKGROUND'
                  AND    username IS NOT NULL
                  AND    schema# != 0
                  GROUP  BY inst_id
                  UNION  ALL
                  SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   inst_id id2, 0 asct, 0 isct, 0 cpas, 0 ioas, 0 waas
                  FROM   gv$instance)
         GROUP  BY id2),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id id3, to_number(value) ncpu
         FROM   gv$osstat
         WHERE  stat_name = 'NUM_CPUS')
WHERE  id1 = inid
AND    id2 = inid
AND    id3 = inid
AND    rownum <= 5
ORDER  BY dbtm DESC;

-- event commulative
/* oratop s3a */
PROMPT EVENT CUMULATIVE:
PROMPT =================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 event, totwa, twsec, avgms, round(ratio_to_report(twsec) OVER() * 100) pctwa, wclas, evtid
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          event, sum(total_waits) totwa, sum(time_waited) / 100 twsec, avg(average_wait) * 10 avgms, wait_class wclas, event_id evtid
         FROM   gv$system_event
         WHERE  wait_class <> 'Idle'
         GROUP  BY event, wait_class, event_id
         HAVING sum(total_waits) > 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          'DB CPU' event, 0 totwa, sum(value) / 100 twsec, 0 avgms, NULL wclas, 19 evtid
         FROM   gv$sysstat
         WHERE  name LIKE '%CPU used by this session%'
         ORDER  BY twsec DESC)
WHERE  rownum < 6;

-- event in realtime
/* oratop s3b */
PROMPT EVENT REAL-TIME:
PROMPT ================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 event, totwa, twsec, avgms, round(ratio_to_report(twsec) OVER() * 100) pctwa, wclas, evtid
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          sw.event, sum(se.total_waits) totwa, sum(se.time_waited) / 100 twsec, sum(se.time_waited) / (greatest(sum(se.total_waits), 1) * 10) avgms,
          sw.wait_class wclas, sw.event# evtid
         FROM   gv$session_wait_class se
         JOIN   gv$session sw
         ON     se.inst_id = sw.inst_id
         AND    se.sid = sw.sid
         WHERE  se.wait_class != 'Idle'
         AND    sw.wait_class != 'Idle'
         GROUP  BY sw.event, sw.wait_class, sw.event#
         HAVING sum(se.total_waits) > 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          'DB CPU' event, 0 totwa, sum(value) / 100 twsec, 0 avgms, NULL wclas, 19 evtid
         FROM   gv$sesstat se
         JOIN   gv$session s2
         ON     se.inst_id = s2.inst_id
         AND    se.sid = s2.sid
         WHERE  se.statistic# = 19
         AND    se.value > 0
         AND    s2.wait_class != 'Idle'
         ORDER  BY twsec DESC)
WHERE  rownum < 6;

-- session details (file block)
/* oratop s4a */
PROMPT SESSION DETAILS FILE/BLOCK:
PROMPT ===========================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 s.wait_time trm4, s.inst_id id4, s.sid sid4, p.spid pid4, decode(p.background, 1, 'B/G', decode(s.username, NULL, 'F/G', s.username)) usr4,
 decode(p.pname, NULL, s.program, p.pname) prg4, s.module modl, s.action actn, p.pga_used_mem pgau, p.pga_alloc_mem pgac, p.pga_freeable_mem pgaf,
 x.pgax pgax, c.command_name opn, decode(s.plsql_subprogram_id, NULL, s.sql_id, NULL) sqid,
 decode(s.final_blocking_session_status, 'VALID', to_char(s.final_blocking_instance) || ':' || to_char(s.final_blocking_session), NULL) bses,
 s.status st4, decode(s.state, 'WAITING', decode(s.wait_class, 'User I/O', 'I/O', s.state), 'CPU') su4,
 CASE
     WHEN s.state <> 'WAITING' AND s.time_since_last_wait_micro < 1000000 THEN
      'cpu runqueue'
     ELSE
      event
 END ev4, s.wait_class wc4, s.wait_time_micro siw, s.last_call_et lcet, s.server sded, s.service_name svcn,
 decode(n.name, NULL, NULL, '*' || n.name) lp2n,
 decode(s.row_wait_obj#, -1, NULL, substr(to_char(s.row_wait_file#) || ':' || to_char(s.row_wait_block#), 1, 24)) fbon
FROM   gv$session s
JOIN   gv$process p
ON     (p.inst_id = s.inst_id AND p.addr = s.paddr)
LEFT   OUTER JOIN v$sqlcommand c
ON     (s.command = c.command_type)
LEFT   OUTER JOIN v$latchname n
ON     (s.p2 = n.latch#), (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
         inst_id, max(pga_max_mem) pgax
        FROM   gv$process
        GROUP  BY inst_id) x
WHERE  x.inst_id = s.inst_id
AND    s.wait_class <> 'Idle'
ORDER  BY siw DESC, lcet DESC;

-- session details (detail)
/* oratop s4b */
PROMPT SESSION DETAILS:
PROMPT ================
WITH sqa AS
 (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
   inst_id, parsing_schema_name, module, action, sql_id, substr(sql_text, 1, 64) sql_text, executions, buffer_gets, disk_reads, elapsed_time, cpu_time,
   user_io_wait_time, (concurrency_wait_time + cluster_wait_time + application_wait_time + plsql_exec_time + java_exec_time) wait, rows_processed,
   px_servers_executions, users_executing, (s.buffer_gets / greatest(s.disk_reads + s.buffer_gets, 1)) * 100 bhr
  FROM   gv$sqlarea s
  WHERE  executions > 0
  AND    users_executing > 0
  AND    parsing_user_id != 0
  AND    command_type NOT IN (47, 170)
  AND    sql_text NOT LIKE '%oratop%')
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
 *
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id, parsing_schema_name, module, action, sql_id, sql_text, executions, buffer_gets, disk_reads, elapsed_time, cpu_time, user_io_wait_time,
          wait, rows_processed, px_servers_executions, users_executing, bhr
         FROM   sqa
         WHERE  px_servers_executions = 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          x.inst_id, x.parsing_schema_name, x.module, x.action, x.sql_id, x.sql_text, x.executions, x.buffer_gets, x.disk_reads, x.elapsed_time,
          x.cpu_time, x.user_io_wait_time, x.wait, x.rows_processed, x.px_servers_executions, x.users_executing, x.bhr
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   inst_id, parsing_schema_name, module, action, sql_id, sql_text, executions, buffer_gets, disk_reads, elapsed_time, cpu_time,
                   user_io_wait_time, wait, rows_processed, px_servers_executions, users_executing, bhr
                  FROM   sqa
                  WHERE  px_servers_executions > 0) x,
                (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   sql_id, max(users_executing) users_executing
                  FROM   sqa
                  WHERE  px_servers_executions > 0
                  GROUP  BY sql_id) y
         WHERE  x.users_executing = y.users_executing
         AND    x.sql_id = y.sql_id)
ORDER  BY elapsed_time / greatest(decode(px_servers_executions, 0, executions, px_servers_executions), 1) DESC;


-- sql plan
/* oratop s05*/
--PROMPT SQL PLAN
--WITH VPLAN as (        SELECT  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */  /*+ NO_MONITOR */                s1.INST_ID,                s1.SQL_ID,                p1.PLAN_HASH_VALUE,                upper(rtrim(s1.sql_text)) text,                MAX(p1.child_number) child_number          from  GV$SQL s1          JOIN  GV$SQL_PLAN p1            on  s1.inst_id=p1.inst_id           and  s1.sql_id=p1.sql_id           and  s1.child_number=p1.child_number           and  s1.ADDRESS=p1.ADDRESS           and  s1.hash_value=p1.hash_value           and  s1.PLAN_HASH_VALUE=p1.PLAN_HASH_VALUE         where  p1.SQL_ID= :sqlid           and rownum = 1      group by  s1.INST_ID, s1.SQL_ID, p1.PLAN_HASH_VALUE, s1.sql_text      order by child_number desc   )   SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */      to_char(p.PLAN_HASH_VALUE),        p.ID,         substr(lpad(' ',p.depth) || p.operation ||         decode(p.options,NULL,'',' '|| p.options),1,80),        substr(p.object_name,1,14),        p.child_number,       vp.text,       p.cardinality,       p.cost,       (CASE when p.object_type like 'TABLE%' then t.STALE_STATS             when p.object_type like 'INDEX%' then i.STALE_STATS             else NULL end)       from GV$SQL_PLAN p      JOIN VPLAN vp        on vp.inst_id=p.inst_id       and vp.PLAN_HASH_VALUE=p.PLAN_HASH_VALUE       and vp.sql_id=p.sql_id      LEFT OUTER JOIN dba_tab_statistics t on               t.table_name = p.object_name               and t.owner= p.object_owner               and t.partition_name is null               and UPPER(p.object_type) not like '%TEMP%'       LEFT OUTER JOIN dba_ind_statistics i on               i.index_name = p.object_name               and i.owner= p.object_owner               and i.partition_name is null      WHERE  p.child_number = vp.child_number        AND  p.sql_id = vp.sql_id         AND  p.inst_id = vp.inst_id        AND  p.child_number = vp.child_number         AND  p.PLAN_HASH_VALUE = vp.PLAN_HASH_VALUE    ORDER BY  p.ID;

-- tablespace details
--/* oratop s06*/
-- PROMPT TABLESPACE DETAILS
--SELECT  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */  /*+ NO_MONITOR */         d.tablespace_name                          tbsn,         DECODE(d.contents,'UNDO', NVL(u.bytes, 0),           NVL(a.bytes - NVL(f.bytes, 0), 0))       tbsu,         d.status                                   tbss,          d.contents                                 tbsc,         d.extent_management                        tbse,          d.segment_space_management                 tbsm,         d.bigfile                                  tbsf,         d.LOGGING                                  tbsl,         d.RETENTION                                tbsr,         d.ENCRYPTED                                tbsy,         d.BLOCK_SIZE                               tbsb,         NVL(a.count, 1)                            tbsi,          a.maxb                                     tbsz    FROM  sys.dba_tablespaces d,         (   SELECT tablespace_name,                     SUM(bytes) bytes,                     SUM(maxbytes) maxb,                     COUNT(file_id) count                from dba_data_files            GROUP BY tablespace_name) a,          (   select tablespace_name,                    sum(bytes) bytes                from dba_free_space            group by tablespace_name) f,         (   SELECT tablespace_name,                     SUM(bytes) bytes                FROM dba_undo_extents               WHERE                    status IN ('ACTIVE','UNEXPIRED')            GROUP BY tablespace_name) u               WHERE                    d.tablespace_name = a.tablespace_name(+)                 AND d.tablespace_name = f.tablespace_name(+)                 AND d.tablespace_name = u.tablespace_name(+)                 AND NOT (d.extent_management = 'LOCAL'                     and d.contents = 'TEMPORARY')  UNION ALL  SELECT d.tablespace_name                          tbsn,         NVL(t.bytes, 0)                            tbsu,          d.status                                   tbss,          d.contents                                 tbsc,         d.extent_management                        tbse,          d.segment_space_management                 tbsm,         d.bigfile                                  tbsf,         d.LOGGING                                  tbsl,         d.RETENTION                                tbsr,         d.ENCRYPTED                                tbsy,         d.BLOCK_SIZE                               tbsb,         NVL(a.count, 1)                            tbsi,          a.maxb                                     tbsz     FROM sys.dba_tablespaces d,         (  select tablespace_name,                   sum(bytes) bytes,                   SUM(maxbytes) maxb,                   count(file_id) count              from dba_temp_files          group by tablespace_name) a,    (  select  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */                  ss.tablespace_name ,                  sum((ss.used_blocks*ts.blocksize)) bytes              from gv$sort_segment ss,                  sys.ts$ ts             where ss.tablespace_name = ts.name          group by ss.tablespace_name) t   WHERE d.tablespace_name = a.tablespace_name(+)     AND d.tablespace_name = t.tablespace_name(+)     AND d.extent_management ='LOCAL'     AND d.contents = 'TEMPORARY'   ORDER BY 1;
