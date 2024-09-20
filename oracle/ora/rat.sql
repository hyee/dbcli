/*[[Show workload replay info. Usage: @@NAME [<id>]

]]*/
SET AUTOHIDE COL FEED OFF VERIFY OFF
COL DUR FOR smhd2
COL COUNT|CALLS,USER|CALLS for tmb2
COL DONE|CALLS for pct2
COL "DB|TIME,NETWORK|TIME,THINK|TIME,PAUSE|TIME,TIME|GAIN" for usmhd2
SELECT ID,
       NAME,
       CAPTURE_ID "CAP|ID",
       PARALLEL "IS|RAC",
       (NUM_CLIENTS-NUM_CLIENTS_DONE)||'/'||NUM_CLIENTS "NUM|CLIENTS",
       FILTER_SET_NAME "FILTER|SETNAME",
       SQLSET_OWNER "SQLSET|OWNER",
       SQLSET_NAME "SQLSET|NAME",
       SCHEDULE_NAME "SCHEDULE|NAME",
       CASE SYNCHRONIZATION
           WHEN 'TRUE' THEN
            'TRUE(SCN)'
           WHEN 'FALSE' THEN
            'FALSE(TIME)'
           ELSE
            SYNCHRONIZATION
       END "SYNC|TYPE",
       CONNECT_TIME_SCALE "CONN|SCALE",
       THINK_TIME_SCALE "THINK|SCALE",
       THINK_TIME_AUTO_CORRECT "AUTO|SCALE",
       SCALE_UP_MULTIPLIER "SCALE|MUTIS",
       '|' "|",
       --DIRECTORY,                
       STATUS,
       --PREPARE_TIME,
       to_char(START_TIME,'MM-DD/HH24:MI') start_time,
       to_char(END_TIME,'MM-DD/HH24:MI') end_time,
       nvl(DURATION_SECS,86400*(sysdate-START_TIME))     "DUR",
       '|' "|",
       USER_CALLS        "USER|CALLS",
       round(USER_CALLS/(select nullif(USER_CALLS-USER_CALLS_UNREPLAYABLE,0) FROM dba_workload_captures B where b.id=a.capture_id),5) "DONE|CALLS",
       DBTIME            "DB|TIME",
       ELAPSED_TIME_DIFF "TIME|GAIN",
       NETWORK_TIME      "NETWORK|TIME",
       THINK_TIME        "THINK|TIME",
       nullif(PAUSE_TIME,0) "PAUSE|TIME",
       '|' "|",
       --AWR_DBID          "AWR|DBID",
       AWR_BEGIN_SNAP    "AWR|BEGIN",
       AWR_END_SNAP      "AWR|END",
       AWR_EXPORTED      "AWR|EXPORT",
       ERROR_CODE        "ERR|CODE",
       ERROR_MESSAGE     "ERR|MESG",
       DIR_PATH          "DIR|PATH",
       REPLAY_DIR_NUMBER "DIR|NUM"
FROM   (select * from dba_workload_replays WHERE  dbid = :dbid ORDER BY START_TIME DESC) A
WHERE  rownum<=20;

VAR c1 refcursor "Workload Replay Info";
VAR c2 refcursor "Workload Capture Info";
VAR c3 refcursor "Workload Threads Info";

DECLARE
  rid INT := regexp_substr(:v1,'^\d+$');
  cid INT;
  status VARCHAR2(50);
BEGIN
  SELECT max(capture_id),
         max(status)
  INTO cid,status
  FROM  dba_workload_replays WHERE id=rid;

  IF status IS NOT NULL THEN
      OPEN :c1 FOR SELECT * FROM dba_workload_replays WHERE id=rid;
      OPEN :c2 FOR SELECT * FROM dba_workload_captures WHERE id=cid;
      IF status = 'IN PROGRESS' THEN
          OPEN :c3 FOR 
              SELECT sid||'@'||inst_id sid,
                     CLIENT_PID "Client|PID",
                     nullif(CLOCK,0) "CLOCK|SCN",
                     nullif(NEXT_TICKER,0) "NEXT|SCN",
                     nullif(WAIT_FOR_SCN,0) "WAIT|SCN",
                     nullif(DEPENDENT_SCN,0) "DEP|SCN",
                     nullif(STATEMENT_SCN,0) "STMT|SCN",
                     nullif(COMMIT_WAIT_SCN,0) "COMMIT|SCN",
                     nullif(POST_COMMIT_SCN,0) "POST|SCN",
                     USER_CALLS        "USER|CALLS",
                     CALL_COUNTER      "COUNT|CALLS",
                     DBTIME            "DB|TIME",
                     nullif(TIME_GAIN-TIME_LOSS,0) "TIME|GAIN",
                     NETWORK_TIME      "NETWORK|TIME",
                     THINK_TIME        "THINK|TIME",
                     '|' "|",
                     WRC_ID "WRC|ID",
                     event,
                     FILE_ID,
                     FILE_NAME,
                     PROGRAM,
                     LOGON_TIME
              FROM gv$workload_replay_thread 
              WHERE file_id>0
              ORDER BY WRC_ID;
      END IF;
  END IF;
END;
/

SET PIVOT 1
PRINT c1
SET PIVOT 1
PRINT c2
SET PIVOT DEFAULT
PRINT c3