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
       (SELECT NAME
         FROM   v$active_services
         WHERE  NAME = (SELECT SERVICE_NAME FROM v$session WHERE sid = (SELECT sys_context('USERENV', 'SID') FROM dual))
         UNION ALL
         SELECT 'SYS$USERS'
         FROM   DUAL
         WHERE  NOT EXISTS (SELECT NAME
                 FROM   v$active_services
                 WHERE  NAME = (SELECT SERVICE_NAME FROM v$session WHERE sid = (SELECT sys_context('USERENV', 'SID') FROM dual)))),
       (SELECT to_number(SUBSTR(banner, 17, 2)) vers, SUBSTR(banner, 17, 3) cver FROM v$version WHERE substr(banner, 1, 3) = 'Ora'),
       (SELECT SUBSTR(UPPER(VALUE), 1, 5) typd FROM v$parameter WHERE NAME = 'instance_type'),
       (SELECT DECODE(VALUE, 'BASIC', 1, 0) stlv FROM v$parameter WHERE NAME = 'statistics_level'), (SELECT COUNT(*) dasm FROM v$asm_diskgroup);

-- memory configuration
/* oratop s1 */
PROMPT CONFIGURATION:
PROMPT ==============
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */ *
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          SUM(VALUE) taas
         FROM   gv$sysmetric
         WHERE  metric_name = 'Database Time Per Sec'
         AND    group_id = 3),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          COUNT(*) sess, COUNT(DISTINCT username) duser
         FROM   gv$session
         WHERE  TYPE <> 'BACKGROUND'
         AND    username IS NOT NULL
         AND    SCHEMA# != 0),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          to_char(MAX(end_time), 'hh24:mi:ss') dbts, SUM(VALUE) spga
         FROM   gv$sysmetric
         WHERE  metric_name = 'Total PGA Allocated'
         AND    group_id = 3), (SELECT (SYSDATE - startup_time) * 86400 uptm FROM v$instance),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          SUM(VALUE) scpu, COUNT(DISTINCT inst_id) inst
         FROM   gv$osstat
         WHERE  stat_name = 'NUM_CPUS'),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          SUM(VALUE) ssga
         FROM   gv$sga),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          SUM(VALUE) prob
         FROM   GV$DIAG_INFO
         WHERE  NAME = 'Active Problem Count'),
       (SELECT SUM(fra) reco FROM (SELECT SPACE_USED / GREATEST(SPACE_LIMIT, 1) * 100 fra FROM V$RECOVERY_FILE_DEST UNION SELECT 0 fra FROM dual)),
       (SELECT initcap(substr(sys_context('USERENV', 'DATABASE_ROLE'), -7, 16)) dbro FROM dual),
       (SELECT SUM(ar) dgar
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   sofar ar
                  FROM   gv$recovery_progress
                  WHERE  TYPE = 'Media Recovery'
                  AND    ITEM = 'Active Apply Rate'
                  AND    rownum = 1
                  UNION
                  SELECT 0 ar
                  FROM   dual)),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          MAX(VALUE) pgag
         FROM   gv$pgastat
         WHERE  NAME = 'aggregate PGA target parameter');

-- load details
/* oratop s2 */
PROMPT LOAD DETAILS:
PROMPT =============
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 inid, hcpu, sgfr, utps, ucps, saas, mbps, ssrt, iorl, load, upga, aspq, dbcp, dbwa, iops, asct, isct, cpas, ioas, waas, dcpu, ncpu, logr, phyr, phyw,
 temp, dbtm
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id inid, SUM(decode(metric_name, 'CPU Usage Per Sec', VALUE, 0)) dcpu,
          SUM(decode(metric_name, 'Host CPU Utilization (%)', VALUE, 0)) hcpu, SUM(decode(metric_name, 'I/O Megabytes per Second', VALUE, 0)) mbps,
          SUM(decode(metric_name, 'SQL Service Response Time', VALUE, 0)) ssrt,
          SUM(decode(metric_name, 'Average Synchronous Single-Block Read Latency', VALUE, 0)) iorl,
          SUM(decode(metric_name, 'Current OS Load', VALUE, 0)) load, SUM(decode(metric_name, 'Active Parallel Sessions', VALUE, 0)) aspq,
          SUM(decode(metric_name, 'Database CPU Time Ratio', VALUE, 0)) dbcp, SUM(decode(metric_name, 'Database Wait Time Ratio', VALUE, 0)) dbwa,
          SUM(decode(metric_name, 'I/O Requests per Second', VALUE, 0)) iops
         FROM   gv$sysmetric
         WHERE  metric_name IN ('CPU Usage Per Sec', 'Host CPU Utilization (%)', 'I/O Megabytes per Second', 'SQL Service Response Time',
                                'Average Synchronous Single-Block Read Latency', 'Current OS Load', 'Active Parallel Sessions', 'Database CPU Time Ratio',
                                'Database Wait Time Ratio', 'I/O Requests per Second')
         AND    group_id = 2
         GROUP  BY inst_id),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id id1, SUM(decode(metric_name, 'Shared Pool Free %', VALUE, 0)) sgfr,
          SUM(decode(metric_name, 'User Transaction Per Sec', VALUE, 0)) utps, SUM(decode(metric_name, 'User Calls Per Sec', VALUE, 0)) ucps,
          SUM(decode(metric_name, 'Average Active Sessions', VALUE, 0)) saas, SUM(decode(metric_name, 'Total PGA Allocated', VALUE, 0)) upga,
          SUM(decode(metric_name, 'Logical Reads Per Sec', VALUE, 0)) logr, SUM(decode(metric_name, 'Physical Reads Per Sec', VALUE, 0)) phyr,
          SUM(decode(metric_name, 'Physical Writes Per Sec', VALUE, 0)) phyw, SUM(decode(metric_name, 'Temp Space Used', VALUE, 0)) temp,
          SUM(decode(metric_name, 'Database Time Per Sec', VALUE, 0)) dbtm
         FROM   gv$sysmetric
         WHERE  metric_name IN
                ('Shared Pool Free %', 'User Transaction Per Sec', 'User Calls Per Sec', 'Logical Reads Per Sec', 'Physical Reads Per Sec',
                 'Physical Writes Per Sec', 'Temp Space Used', 'Database Time Per Sec', 'Average Active Sessions', 'Total PGA Allocated')
         AND    group_id = 3
         GROUP  BY inst_id),
       (SELECT id2, SUM(asct) asct, SUM(isct) isct, SUM(cpas) cpas, SUM(ioas) ioas, SUM(waas) waas
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   inst_id id2, SUM(DECODE(status, 'ACTIVE', 1, 0)) asct, COUNT(*) isct, SUM(DECODE(status, 'ACTIVE', decode(WAIT_TIME, 0, 0, 1), 0)) cpas,
                   SUM(DECODE(status, 'ACTIVE', decode(wait_class, 'User I/O', 1, 0), 0)) ioas,
                   SUM(DECODE(status, 'ACTIVE', decode(WAIT_TIME, 0, decode(wait_class, 'User I/O', 0, 1), 0), 0)) waas
                  FROM   gv$session
                  WHERE  TYPE <> 'BACKGROUND'
                  AND    username IS NOT NULL
                  AND    SCHEMA# != 0
                  GROUP  BY inst_id
                  UNION ALL
                  SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   inst_id id2, 0 asct, 0 isct, 0 cpas, 0 ioas, 0 waas
                  FROM   gv$instance)
         GROUP  BY id2),
       (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          inst_id id3, TO_NUMBER(VALUE) ncpu
         FROM   gv$osstat
         WHERE  stat_name = 'NUM_CPUS')
WHERE  id1 = inid
AND    id2 = inid
AND    id3 = inid
AND    ROWNUM <= 5
ORDER  BY dbtm DESC;

-- event commulative
/* oratop s3a */
PROMPT EVENT COMMULATIVE:
PROMPT ==================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 event, totwa, twsec, avgms, ROUND(RATIO_TO_REPORT(twsec) OVER() * 100) pctwa, wclas, evtid
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          EVENT, SUM(TOTAL_WAITS) totwa, SUM(TIME_WAITED) / 100 twsec, AVG(AVERAGE_WAIT) * 10 avgms, WAIT_CLASS wclas, EVENT_ID evtid
         FROM   GV$SYSTEM_EVENT
         WHERE  WAIT_CLASS <> 'Idle'
         GROUP  BY EVENT, WAIT_CLASS, EVENT_ID
         HAVING SUM(TOTAL_WAITS) > 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          'DB CPU' event, 0 totwa, SUM(VALUE) / 100 twsec, 0 avgms, NULL wclas, 19 evtid
         FROM   GV$SYSSTAT
         WHERE  NAME LIKE '%CPU used by this session%'
         ORDER  BY twsec DESC)
WHERE  ROWNUM < 6;

-- event in realtime
/* oratop s3b */
PROMPT EVENT REAL-TIME:
PROMPT ================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 event, totwa, twsec, avgms, ROUND(RATIO_TO_REPORT(twsec) OVER() * 100) pctwa, wclas, evtid
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          SW.EVENT, SUM(SE.TOTAL_WAITS) totwa, SUM(SE.TIME_WAITED) / 100 twsec, SUM(SE.TIME_WAITED) / (GREATEST(SUM(SE.TOTAL_WAITS), 1) * 10) avgms,
          SW.WAIT_CLASS wclas, SW.EVENT# evtid
         FROM   GV$SESSION_WAIT_CLASS SE
         JOIN   GV$SESSION SW
         ON     SE.INST_ID = SW.INST_ID
         AND    SE.SID = SW.SID
         WHERE  SE.wait_class != 'Idle'
         AND    SW.wait_class != 'Idle'
         GROUP  BY SW.EVENT, SW.WAIT_CLASS, SW.EVENT#
         HAVING SUM(SE.TOTAL_WAITS) > 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          'DB CPU' event, 0 totwa, SUM(VALUE) / 100 twsec, 0 avgms, NULL wclas, 19 evtid
         FROM   GV$SESSTAT se
         JOIN   GV$SESSION s2
         ON     se.INST_ID = s2.INST_ID
         AND    se.SID = s2.SID
         WHERE  se.STATISTIC# = 19
         AND    se.value > 0
         AND    s2.wait_class != 'Idle'
         ORDER  BY twsec DESC)
WHERE  ROWNUM < 6;

-- session details (file block)
/* oratop s4a */
PROMPT SESSION DETAILS FILE/BLOCK:
PROMPT ===========================
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
 s.WAIT_TIME trm4, s.inst_id id4, s.sid sid4, p.spid pid4, decode(p.BACKGROUND, 1, 'B/G', decode(s.username, NULL, 'F/G', s.username)) usr4,
 decode(p.PNAME, NULL, s.program, p.PNAME) prg4, s.module modl, s.action actn, p.PGA_USED_MEM pgau, p.PGA_ALLOC_MEM pgac, p.PGA_FREEABLE_MEM pgaf,
 x.pgax pgax, c.COMMAND_NAME opn, DECODE(s.PLSQL_SUBPROGRAM_ID, NULL, s.SQL_ID, NULL) sqid,
 DECODE(s.FINAL_BLOCKING_SESSION_STATUS, 'VALID', to_char(s.FINAL_BLOCKING_INSTANCE) || ':' || to_char(s.FINAL_BLOCKING_SESSION), NULL) bses,
 s.status st4, decode(s.state, 'WAITING', decode(s.wait_class, 'User I/O', 'I/O', s.state), 'CPU') su4,
 CASE
     WHEN s.STATE <> 'WAITING' AND s.TIME_SINCE_LAST_WAIT_MICRO < 1000000 THEN
      'cpu runqueue'
     ELSE
      event
 END ev4, s.wait_class wc4, s.WAIT_TIME_MICRO siw, s.last_call_et lcet, s.server sded, s.SERVICE_NAME svcn,
 DECODE(n.name, NULL, NULL, '*' || n.name) lp2n,
 DECODE(s.ROW_WAIT_OBJ#, -1, NULL, substr(to_char(s.ROW_WAIT_FILE#) || ':' || to_char(s.ROW_WAIT_BLOCK#), 1, 24)) fbon
FROM   GV$SESSION s
JOIN   gv$process p
ON     (p.inst_id = s.inst_id AND p.addr = s.paddr)
LEFT   OUTER JOIN v$sqlcommand c
ON     (s.command = c.COMMAND_TYPE)
LEFT   OUTER JOIN v$LATCHNAME n
ON     (s.p2 = n.latch#), (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
         inst_id, MAX(PGA_MAX_MEM) pgax
        FROM   GV$PROCESS
        GROUP  BY inst_id) x
WHERE  x.inst_id = s.inst_id
AND    s.wait_class <> 'Idle'
ORDER  BY siw DESC, lcet DESC;

-- session details (detail)
/* oratop s4b */
PROMPT SESSION DETAILS:
PROMPT ================
WITH SQA AS
 (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */ /*+ NO_MONITOR */
   INST_ID, PARSING_SCHEMA_NAME, MODULE, ACTION, SQL_ID, substr(SQL_TEXT, 1, 64) sql_text, EXECUTIONS, BUFFER_GETS, DISK_READS, ELAPSED_TIME, CPU_TIME,
   USER_IO_WAIT_TIME, (CONCURRENCY_WAIT_TIME + CLUSTER_WAIT_TIME + APPLICATION_WAIT_TIME + PLSQL_EXEC_TIME + JAVA_EXEC_TIME) wait, ROWS_PROCESSED,
   PX_SERVERS_EXECUTIONS, USERS_EXECUTING, (s.buffer_gets / GREATEST(s.disk_reads + s.buffer_gets, 1)) * 100 bhr
  FROM   GV$SQLAREA s
  WHERE  EXECUTIONS > 0
  AND    USERS_EXECUTING > 0
  AND    PARSING_USER_ID != 0
  AND    COMMAND_TYPE NOT IN (47, 170)
  AND    SQL_TEXT NOT LIKE '%oratop%')
SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
 *
FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          INST_ID, PARSING_SCHEMA_NAME, MODULE, ACTION, SQL_ID, SQL_TEXT, EXECUTIONS, BUFFER_GETS, DISK_READS, ELAPSED_TIME, CPU_TIME, USER_IO_WAIT_TIME,
          wait, ROWS_PROCESSED, PX_SERVERS_EXECUTIONS, USERS_EXECUTING, bhr
         FROM   SQA
         WHERE  PX_SERVERS_EXECUTIONS = 0
         UNION
         SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
          x.INST_ID, x.PARSING_SCHEMA_NAME, x.MODULE, x.ACTION, x.SQL_ID, x.SQL_TEXT, x.EXECUTIONS, x.BUFFER_GETS, x.DISK_READS, x.ELAPSED_TIME,
          x.CPU_TIME, x.USER_IO_WAIT_TIME, x.wait, x.ROWS_PROCESSED, x.PX_SERVERS_EXECUTIONS, x.USERS_EXECUTING, x.bhr
         FROM   (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   INST_ID, PARSING_SCHEMA_NAME, MODULE, ACTION, SQL_ID, SQL_TEXT, EXECUTIONS, BUFFER_GETS, DISK_READS, ELAPSED_TIME, CPU_TIME,
                   USER_IO_WAIT_TIME, wait, ROWS_PROCESSED, PX_SERVERS_EXECUTIONS, USERS_EXECUTING, bhr
                  FROM   SQA
                  WHERE  PX_SERVERS_EXECUTIONS > 0) x,
                (SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */
                   SQL_ID, MAX(USERS_EXECUTING) USERS_EXECUTING
                  FROM   SQA
                  WHERE  PX_SERVERS_EXECUTIONS > 0
                  GROUP  BY SQL_ID) y
         WHERE  x.USERS_EXECUTING = y.USERS_EXECUTING
         AND    x.sql_id = y.sql_id)
ORDER  BY ELAPSED_TIME / greatest(decode(PX_SERVERS_EXECUTIONS, 0, EXECUTIONS, PX_SERVERS_EXECUTIONS), 1) DESC;


-- sql plan
/* oratop s05*/
--PROMPT SQL PLAN
--WITH VPLAN as (        SELECT  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */  /*+ NO_MONITOR */                s1.INST_ID,                s1.SQL_ID,                p1.PLAN_HASH_VALUE,                upper(rtrim(s1.sql_text)) text,                MAX(p1.child_number) child_number          from  GV$SQL s1          JOIN  GV$SQL_PLAN p1            on  s1.inst_id=p1.inst_id           and  s1.sql_id=p1.sql_id           and  s1.child_number=p1.child_number           and  s1.ADDRESS=p1.ADDRESS           and  s1.hash_value=p1.hash_value           and  s1.PLAN_HASH_VALUE=p1.PLAN_HASH_VALUE         where  p1.SQL_ID= :sqlid           and rownum = 1      group by  s1.INST_ID, s1.SQL_ID, p1.PLAN_HASH_VALUE, s1.sql_text      order by child_number desc   )   SELECT /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */      to_char(p.PLAN_HASH_VALUE),        p.ID,         substr(lpad(' ',p.depth) || p.operation ||         decode(p.options,NULL,'',' '|| p.options),1,80),        substr(p.object_name,1,14),        p.child_number,       vp.text,       p.cardinality,       p.cost,       (CASE when p.object_type like 'TABLE%' then t.STALE_STATS             when p.object_type like 'INDEX%' then i.STALE_STATS             else NULL end)       from GV$SQL_PLAN p      JOIN VPLAN vp        on vp.inst_id=p.inst_id       and vp.PLAN_HASH_VALUE=p.PLAN_HASH_VALUE       and vp.sql_id=p.sql_id      LEFT OUTER JOIN dba_tab_statistics t on               t.table_name = p.object_name               and t.owner= p.object_owner               and t.partition_name is null               and UPPER(p.object_type) not like '%TEMP%'       LEFT OUTER JOIN dba_ind_statistics i on               i.index_name = p.object_name               and i.owner= p.object_owner               and i.partition_name is null      WHERE  p.child_number = vp.child_number        AND  p.sql_id = vp.sql_id         AND  p.inst_id = vp.inst_id        AND  p.child_number = vp.child_number         AND  p.PLAN_HASH_VALUE = vp.PLAN_HASH_VALUE    ORDER BY  p.ID;

-- tablespace details
--/* oratop s06*/
-- PROMPT TABLESPACE DETAILS
--SELECT  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */  /*+ NO_MONITOR */         d.tablespace_name                          tbsn,         DECODE(d.contents,'UNDO', NVL(u.bytes, 0),           NVL(a.bytes - NVL(f.bytes, 0), 0))       tbsu,         d.status                                   tbss,          d.contents                                 tbsc,         d.extent_management                        tbse,          d.segment_space_management                 tbsm,         d.bigfile                                  tbsf,         d.LOGGING                                  tbsl,         d.RETENTION                                tbsr,         d.ENCRYPTED                                tbsy,         d.BLOCK_SIZE                               tbsb,         NVL(a.count, 1)                            tbsi,          a.maxb                                     tbsz    FROM  sys.dba_tablespaces d,         (   SELECT tablespace_name,                     SUM(bytes) bytes,                     SUM(maxbytes) maxb,                     COUNT(file_id) count                from dba_data_files            GROUP BY tablespace_name) a,          (   select tablespace_name,                    sum(bytes) bytes                from dba_free_space            group by tablespace_name) f,         (   SELECT tablespace_name,                     SUM(bytes) bytes                FROM dba_undo_extents               WHERE                    status IN ('ACTIVE','UNEXPIRED')            GROUP BY tablespace_name) u               WHERE                    d.tablespace_name = a.tablespace_name(+)                 AND d.tablespace_name = f.tablespace_name(+)                 AND d.tablespace_name = u.tablespace_name(+)                 AND NOT (d.extent_management = 'LOCAL'                     and d.contents = 'TEMPORARY')  UNION ALL  SELECT d.tablespace_name                          tbsn,         NVL(t.bytes, 0)                            tbsu,          d.status                                   tbss,          d.contents                                 tbsc,         d.extent_management                        tbse,          d.segment_space_management                 tbsm,         d.bigfile                                  tbsf,         d.LOGGING                                  tbsl,         d.RETENTION                                tbsr,         d.ENCRYPTED                                tbsy,         d.BLOCK_SIZE                               tbsb,         NVL(a.count, 1)                            tbsi,          a.maxb                                     tbsz     FROM sys.dba_tablespaces d,         (  select tablespace_name,                   sum(bytes) bytes,                   SUM(maxbytes) maxb,                   count(file_id) count              from dba_temp_files          group by tablespace_name) a,    (  select  /*+ OPT_PARAM('_optimizer_adaptive_plans','false') */                  ss.tablespace_name ,                  sum((ss.used_blocks*ts.blocksize)) bytes              from gv$sort_segment ss,                  sys.ts$ ts             where ss.tablespace_name = ts.name          group by ss.tablespace_name) t   WHERE d.tablespace_name = a.tablespace_name(+)     AND d.tablespace_name = t.tablespace_name(+)     AND d.extent_management ='LOCAL'     AND d.contents = 'TEMPORARY'   ORDER BY 1;
