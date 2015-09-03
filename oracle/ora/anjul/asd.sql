/* [[ Active Sessions Detailed 11g+
--[[
@BASE:11.2 ={}
]]--
]] */


  SELECT SESS.inst_id,
         SESS.sid,
         SESS.SERIAL#,
         SESS.STATUS,
         SESS.username,
         SESS.osuser,
         substr(SESS.program,1,19) program,
         sess.module,
         sess.action,
         sess.client_identifier,
         NVL (SESS.sql_id, sm.sql_id) SQL_ID,
         ROUND ( ( (SA.elapsed_time / NULLIF (SA.executions, 0)) / 1000000), 3)
            avg_etime,
         SA.EXECUTIONS EXECS,
         SUBSTR (SA.SQL_TEXT, 0, 64) SQL_TEXT,
         TRIM (SESS.machine || ' - ' || SESS.PROCESS) "PROCESS",
         P.INST_ID || ' - ' || P.SPID "SPID",
         SESS.logon_time,
         NVL ( (SYSDATE - sess.sql_exec_start) * 86400, sess.last_call_et)
            "Duration",
         SM.FETCHES,
            TO_CHAR (
               FLOOR (
                    NVL ( (SYSDATE - sess.sql_exec_start) * 86400,
                         sess.last_call_et)
                  / 86400),
               '999')
         || ' d '
         || TRIM (
               TO_CHAR (
                  FLOOR (
                       MOD (
                          NVL ( (SYSDATE - sess.sql_exec_start) * 86400,
                               sess.last_call_et),
                          86400)
                     / 3600),
                  '00'))
         || ' hr '
         || TRIM (
               TO_CHAR (
                  FLOOR (
                       MOD (
                          NVL ( (SYSDATE - sess.sql_exec_start) * 86400,
                               sess.last_call_et),
                          3600)
                     / 60),
                  '00'))
         || ' min '
            "Duration in Hours",
         sess.event,
         SESS.prev_sql_id,
         -- p1text,p1,p1raw, p2text,p2,p3text,p3,
         (SELECT    owner
                 || '.'
                 || object_name
                 || '('
                 || DBMS_ROWID.rowid_create (1,
                                             row_wait_obj#,
                                             row_wait_file#,
                                             row_wait_block#,
                                             row_wait_row#)
                 || ')'
            FROM dba_objects
           WHERE object_id = ROW_WAIT_OBJ#)
            "OBJECT",
         WAIT_CLASS,
         BLOCKING_SESSION_STATUS,
         BLOCKING_INSTANCE || ' : ' || BLOCKING_SESSION
            "Blocker: Instance : Session ID",
         --  to_char(SM.BINDS_XML),
         ROUND (SM.BUFFER_GETS) "BUFFER GETS",
         ROUND (SM.DISK_READS) "DISK READS",
         ROUND (SM.APPLICATION_WAIT_TIME / 1e6, 2) "APPLICATION WT(s)",
         ROUND (SM.CLUSTER_WAIT_TIME / 1e6, 2) "CLUSTER WT(s)",
         ROUND (SM.CONCURRENCY_WAIT_TIME / 1e6, 2) "CONCURRENCY WT(s)",
         ROUND (SM.USER_IO_WAIT_TIME / 1e6, 2) "USERIO WT(s)",
         ROUND (SM.CPU_TIME / 1e6, 2) "CPU TIME(s)",
         SM.PX_SERVERS_ALLOCATED "PX_THREADS",
         SM.SQL_PLAN_HASH_VALUE PHV,
         SA.SQL_PROFILE,
         SA.SQL_PLAN_BASELINE
    FROM GV$SESSION SESS,
         GV$SQL_MONITOR SM,
         GV$SQL SA,
         GV$PROCESS p
   WHERE     SESS.username IS NOT NULL
         AND SESS.PADDR = P.ADDR
         AND sess.inst_id = P.INST_ID
         AND SESS.INST_ID = SM.INST_ID(+)
         AND SESS.SID = SM.SID(+)
         AND SESS.SERIAL# = SM.SESSION_SERIAL#(+)
         AND SESS.SQL_EXEC_ID = SM.SQL_EXEC_ID(+)
         AND SESS.SQL_EXEC_START = SM.SQL_EXEC_START(+)
         AND SESS.SQL_ID = SA.SQL_ID(+)
         AND SESS.SQL_CHILD_NUMBER = SA.CHILD_NUMBER(+)
         AND SESS.INST_ID = SA.INST_ID(+)
         AND (sess.status = 'ACTIVE' OR sm.status = 'EXECUTING')
         AND NVL ( (SYSDATE - sess.sql_exec_start) * 86400, sess.last_call_et) > 0
ORDER BY NVL ( (SYSDATE - sess.sql_exec_start) * 86400, sess.last_call_et) DESC;
