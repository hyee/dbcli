/*[[Show DataGuard status
    Ref: https://github.com/karlarao/scripts/tree/master/data_guard
    --[[
        @ALIAS: dataguard
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
    SELECT r.*
    FROM   r
    JOIN (SELECT DISTINCT regexp_substr(NAME, '\d+$') n 
          FROM r 
          WHERE NAME LIKE 'log_archive_dest%' AND NAME NOT LIKE 'log_archive_dest_state%'
          ) r1
    ON     r1.n = regexp_substr(r.NAME, '\d+$')
    ORDER BY 0+r1.n,r.name)
UNION ALL
SELECT name,value
FROM   V$PARAMETER
WHERE  NAME LIKE 'fal_%';

PRO v$archive_dest:
PRO ===============
SELECT gvi.thread#,
       gvad.dest_id        dest#,
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
FROM   v$archive_dest gvad, v$instance gvi, v$archive_dest_status gvas
WHERE  gvad.dest_id = gvas.dest_id
--AND    gvi.thread#=gvas.archived_thread# 
AND    gvad.destination IS NOT NULL
ORDER  BY gvi.thread#, gvad.dest_id\G

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
SELECT thread#, process, pid, status, client_process, client_pid, sequence#, block#, delay_mins,active_agents, known_agents
FROM   gv$managed_standby
WHERE  NULLIF(client_process,'N/A') IS NOT NULL
ORDER  BY sequence#,thread#, process;

PRO Apply stats:
PRO ============
SELECT al.thrd "Thread", almax "Last Seq Received", lhmax "Last Seq Applied"
FROM   (SELECT thread# thrd, MAX(sequence#) almax
        FROM   v$archived_log
        WHERE  resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
        GROUP  BY thread#) al,
       (SELECT thread# thrd, MAX(sequence#) lhmax
        FROM   v$log_history
        WHERE  resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
        GROUP  BY thread#) lh
WHERE  al.thrd = lh.thrd;

PRO v$dataguard_stats(for LGWR log transport and real time apply):
PRO ==============================================================
SELECT * FROM v$dataguard_stats WHERE name LIKE '%lag%';
SELECT * FROM v$standby_event_histogram ORDER BY unit DESC, time;

PRO v$archive_gap:
PRO ==============
SELECT * FROM v$archive_gap;
