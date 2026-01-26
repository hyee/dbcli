/*[[Show DataGuard status
    Ref: https://github.com/karlarao/scripts/tree/master/data_guard
    --[[
        @ALIAS: dataguard
        @ver122 : 12.2={} defult={--}
    --]]
]]*/
set feed off autohide on
PRO Parameters:
PRO ===========
WITH r AS
 (SELECT NAME, VALUE
  FROM   V$PARAMETER
  WHERE  NAME LIKE 'log_archive_dest_%'
  AND    VALUE IS NOT NULL)
SELECT * FROM (
    SELECT r.name,r.value
    FROM   r
    JOIN (SELECT DISTINCT regexp_substr(NAME, '\d+$') n 
          FROM r 
          WHERE NAME LIKE 'log_archive_dest%' AND NAME NOT LIKE 'log_archive_dest_state%'
          ) r1
    ON     r1.n = regexp_substr(r.NAME, '\d+$')
    UNION ALL
    SELECT name,value
    FROM   V$PARAMETER
    WHERE  NAME like 'fal_%' 
    or     NAME like '%data%guard%' 
    or     NAME like '%log_archive_max_processes%' 
    or     description like '%standby%')
ORDER BY substr(name,1,16),regexp_substr(name,'\d+$'),name;

PRO v$dataguard_config:
PRO ===================
SELECT * FROM V$DATAGUARD_CONFIG;

PRO v$archive_dest:
PRO ===============
SELECT gvad.dest_id        dest#,
       gvas.dest_name,
       gvas.destination,   
       gvas.database_mode,
       gvas.archived_seq#,
       gvas.applied_seq#,
       gvas.recovery_mode,
       gvas.protection_mode,
       gvad.archiver,
       gvad.transmit_mode,
       gvad.affirm,
       gvad.async_blocks,
       gvad.net_timeout,
       gvad.delay_mins,
       gvad.reopen_secs    reopen,
       gvad.register,
       gvad.binding,
       gvad.compression,
       gvad.status,
       gvas.gap_status,
       gvad.target,
       gvad.schedule,
       gvad.process,
       gvad.mountid        mountid,
       gvad.FAIL_DATE,
       gvad.FAIL_SEQUENCE,
       gvad.FAIL_BLOCK,
       gvad.FAILURE_COUNT,
       gvad.MAX_FAILURE,
       gvad.ERROR
FROM   v$archive_dest gvad, v$archive_dest_status gvas
WHERE  gvad.dest_id = gvas.dest_id
AND    gvad.destination IS NOT NULL
ORDER  BY gvad.dest_id\G

PRO gv$dataguard_status:
PRO ====================
SELECT *
FROM   (SELECT gvi.thread#, dest_id dest#, TIMESTAMP, message
        FROM   gv$dataguard_status gvds, gv$instance gvi
        WHERE  gvds.inst_id = gvi.inst_id
        AND    severity IN ('Error', 'Fatal')
        ORDER  BY TIMESTAMP DESC, thread#)
WHERE  ROWNUM <= 30;

PRO gv$managed_standby:
PRO ===================
&ver122 SELECT inst_id,thread#, pid, role,client_pid, client_role,action,  sequence#, block#,block_count, delay_mins
&ver122 FROM   gv$dataguard_process
&ver122 where sequence#>0;

SELECT inst_id,thread#, process, pid, status, client_process, client_pid, sequence#, block#, delay_mins,active_agents, known_agents
FROM   gv$managed_standby
WHERE  (NULLIF(client_process,'N/A') IS NOT NULL OR process like 'MRP%')
ORDER  BY sequence#,thread#, process;

COL SLOT,SOURCE_DBID,SOURCE_DB_UNIQUE_NAME,CON_ID NOPRINT
col "bytes,Redo/Sec,Complete/Sec,Apply/Sec" for kmg
PRO Archive Rate:
PRO =============
SELECT a.dest_id,
       b.target,
       a.thread#,
       TO_CHAR(first_time,'yyyy-mm-dd')||' '||TO_CHAR(MIN(first_time),'HH24:MI')||' ~ '||TO_CHAR(MAX(next_time),'HH24:MI') first_time,
       FLOOR(to_char(first_time,'HH24')/8) slot,
       ROUND(SUM(BLOCKS*BLOCK_SIZE)/nullif(MAX(next_time)-MIN(first_time),0)/86400) "Redo/Sec",
       AVG(BLOCKS*BLOCK_SIZE/86400/nullif(completion_time-first_time,0)) "Complete/Sec",
       ROUND(COUNT(1)/nullif(MAX(next_time)-MIN(first_time),0)/24,2) "Switches/Hour"
FROM   v$archived_log a, v$archive_dest b,v$database c
WHERE  a.dest_id = b.dest_id
AND    a.resetlogs_change#=c.resetlogs_change#
AND    b.target IN('LOCAL','STANDBY')
AND    first_time>sysdate-7
GROUP  BY b.target, a.dest_id,a.thread#,TO_CHAR(first_time,'yyyy-mm-dd'),FLOOR(to_char(first_time,'HH24')/8)
ORDER  BY first_time desc,slot desc,a.dest_id,a.thread#;

PRO Apply stats:
PRO ============
SELECT dest_id,
       target,
       thread#,
       MAX(sequence#) max_sequence#,
       MAX(CASE WHEN applied = 'YES' THEN sequence# END) max_applied#,
       MAX(CASE WHEN standby_dest!='YES' or applied = 'YES' then next_time end) max_next_time,
       COUNT(1) logs,
       SUM(CASE WHEN applied = 'YES' THEN 1 END) applies,
       SUM(CASE WHEN target='PRIMARY' AND sequence#>max_apl THEN standbys-trans END) missings
FROM   (
    SELECT b.target,
           a.*,
           COUNT(DISTINCT decode(b.target,'STANDBY',a.dest_id)) OVER() standbys,
           DECODE(a.standby_dest,'PRIMARY',SUM(decode(b.target,'STANDBY',1,0)) OVER(PARTITION BY a.thread#,a.sequence#)) trans,
           MAX(CASE WHEN b.target='STANDBY' AND a.applied='YES' THEN sequence# END) OVER(PARTITION BY a.thread#) max_apl
    FROM   v$archived_log a, v$archive_dest b,v$database c
    WHERE  a.dest_id = b.dest_id
    AND    a.resetlogs_change#=c.resetlogs_change#
    AND    a.standby_dest=decode(b.target,'STANDBY','YES','PRIMARY','NO',a.standby_dest)
)
GROUP  BY target, dest_id,thread#
ORDER  BY 1, 2,3;

SELECT ARCH.THREAD# "Thread",
       ARCH.SEQUENCE# "Last Sequence Received",
       APPL.SEQUENCE# "Last Sequence Applied",
       (ARCH.SEQUENCE# - APPL.SEQUENCE#) "Difference"
FROM   (SELECT THREAD#, MAX(SEQUENCE#) KEEP(DENSE_RANK LAST ORDER BY FIRST_TIME) SEQUENCE#
        FROM   V$ARCHIVED_LOG
        WHERE  resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
        GROUP BY THREAD#) ARCH,
       (SELECT THREAD#, MAX(SEQUENCE#) KEEP(DENSE_RANK LAST ORDER BY FIRST_TIME) SEQUENCE#
        FROM   V$LOG_HISTORY
        WHERE  resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
        GROUP BY THREAD#) APPL
WHERE  ARCH.THREAD# = APPL.THREAD#
ORDER  BY 1;


PRO v$dataguard_stats(for LGWR log transport and real time apply):
PRO ==============================================================
SELECT A.*,TO_CHAR(SYSDATE,'MM/DD/YYYY HH24:MI:SS') "SYSDATE" FROM v$dataguard_stats A;

PRO v$standby_event_histogram
PRO =========================
SELECT NAME,
       MIN("TIME") || ' ~ ' || MAX("TIME") "TIME",
       MIN(TIME) SLOT,
       unit,
       SUM("COUNT") "Count",
       MAX(LAST_TIME_UPDATED) LAST_TIME_UPDATED
FROM   v$standby_event_histogram
WHERE  "COUNT" > 0
GROUP  BY NAME, UNIT, FLOOR(TIME / 6)
ORDER  BY unit DESC, SLOT;

PRO v$standby_logs:
PRO ===============
PRO Standby groups should be larger than redo log groups
PRO If redo size > standby size: results in Transport Lag by RFS process
PRO If redo size < standby size: results in Apply Lag by MRP process
PRO *********************************************************************
SELECT thread#, bytes, rd.cnt redo_groups, st.cnt standby_groups, st.actives standby_actives, st.errs standby_erros
FROM   (SELECT thread#, bytes, COUNT(DISTINCT GROUP#) cnt FROM v$log GROUP BY thread#, bytes) rd
FULL   JOIN (SELECT thread#,
                    bytes,
                    COUNT(DISTINCT GROUP#) cnt,
                    COUNT(DISTINCT DECODE(status, 'ACTIVE', group#)) actives,
                    COUNT(DISTINCT CASE WHEN status NOT IN ('ACTIVE', 'UNASSIGNED') THEN group# END) errs
             FROM   v$standby_log
             GROUP  BY thread#, bytes) st
USING  (thread#, bytes)
ORDER  BY 1, 2;


PRO v$archive_gap:
PRO ==============
SELECT * FROM v$archive_gap;
