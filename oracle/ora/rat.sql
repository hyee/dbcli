/*[[
    Show Real Application Testing info. Usage: @@NAME [{<replay id> [text|html]} | pause | resume | cancel]
    Parameters:
    -----------
    text|html: when specified then generate the target replay report
    pause    : pause the running workload replay task
    resume   : resume the running workload replay task
    cancel   : cancel(abort) the replay task, after the operation the task cannot be resumed

    If too many session on 'WCR: replay lock order"/buffer busy waits" or "gc current block busy", add parameter dscn_off=true to the WRC client to ignore SCN dependencies during replay.
    If too many session on WCR: replay clock, try setting dscn_off=false to speed up the replay
    If the captured workload contains the PL/SQL with refcursors, try setting _wcr_control=1(19.21+)
    set max_idle_blocker_time=1 to reduce row lock contention issue 
    Ref: https://westzq1.github.io/oracle/2019/02/22/Oracle-Database-Workload-Replay.html
    --[[
        @VER122: 12.2={} default={--}
        @check_access_wrr: sys.wrr$_replay_scn_order={1} default={0}
    --]]
]]*/
SET AUTOHIDE COL FEED OFF VERIFY OFF
COL DUR FOR smhd2
COL COUNT|CALLS,USER|CALLS for tmb2
COL DONE|CALLS for pct2
COL "DB|TIME,NETWORK|TIME,THINK|TIME,PAUSE|TIME,TIME|GAIN" for usmhd2
COL CAPTURE_CONN FOR A50

VAR c0 refcursor "Workload Replay Summary";
VAR c1 refcursor "Workload Replay Info";
VAR c11 refcursor "Workload Replay Connection Map(30)";
VAR c12 refcursor "Workload Replay Filter Set";
VAR c2 refcursor "Workload Capture Info";
VAR c3 refcursor "Workload Threads Info";
VAR rpt CLOB;

DECLARE
    v1     VARCHAR2(128) := upper(:v1);
    rid    INT := regexp_substr(v1,'^\d+$');
    cid    INT;
    clock  NUMBER;
    status VARCHAR2(50);
    fset   VARCHAR2(50);
    options SYS.ODCIVARCHAR2LIST;
BEGIN
    BEGIN
        status := CASE WHEN dbms_workload_replay.is_replay_paused() THEN 'YES' ELSE 'NO' END;
        EXCEPTION WHEN OTHERS THEN NULL;
    END;
    IF v1 IN('PAUSE','RESUME','CANCEL') THEN
        IF status IS NULL THEN
            raise_application_error(-20001,'No workload replay task is paused or running');
        END IF;
        IF upper(:v1)='PAUSE' THEN
            dbms_workload_replay.pause_replay();
        ELSIF upper(:v1)='RESUME' THEN
            dbms_workload_replay.resume_replay();
        ELSE
            dbms_workload_replay.cancel_replay();
        END IF;
    END IF;

    options := SYS.ODCIVARCHAR2LIST('_AUTO_AWR_EXPORT',
                                    'DBMS_LOCK_SYNC',
                                    'DO_NO_WAIT_COMMITS',
                                    'DISABLE_DB_LINKS',
                                    'DISABLE_GEN_REMAP',
                                    'MONITOR_CLIENTS',
                                    'REPLAY_TIMEOUT_ENABLED',
                                    'REPLAY_TIMEOUT_MIN',
                                    'REPLAY_TIMEOUT_MAX',
                                    'REPLAY_TIMEOUT_FACTOR');
    dbms_output.put_line('Replay Attributes:');
    dbms_output.put_line('==================');
    FOR i in 1..options.count LOOP
        BEGIN
            dbms_output.put_line(rpad(options(i),30)||' = '||dbms_workload_replay.get_advanced_parameter(options(i)));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    /*IF status is NOT NULL THEN
        FOR r in(SELECT case when event like 'WCR%' then event
                             when file_id > 0 then 'WCR: Executing'
                             else 'WCR: Idle'
                        end event,COUNT(1) c 
                 FROM   gv$workload_replay_thread
                 GROUP BY case when event like 'WCR%' then event
                             when file_id > 0 then 'WCR: Executing'
                             else 'WCR: Idle'
                        end
                 ORDER BY 1) LOOP
            dbms_output.put_line('  '||rpad(r.event,30)||' = '|| r.c ||' theads');
        END LOOP;
    END IF;
    */
    IF status is NOT NULL THEN
        FOR r in(SELECT event, count(1) c 
                 FROM   gv$workload_replay_thread
                 WHERE  event LIKE 'WCR%'
                 GROUP  by event
                 ORDER BY 1) LOOP
            dbms_output.put_line(rpad(r.event,30)||' = '|| r.c ||' threads');
        END LOOP;
        SELECT MAX(clock) 
        into   clock
        FROM   gv$workload_replay_thread;

        SELECT round(100*max(clock-min_scn)/max(max_scn-min_scn),4)
        INTO  clock
        FROM (
            $IF &check_access_wrr=1 $THEN
            SELECT MIN(post_commit_scn) min_scn, MAX(post_commit_scn) max_scn  
            FROM   sys.wrr$_replay_scn_order
            UNION ALL
            $END
            SELECT start_scn min_scn,end_scn max_scn
            FROM   dba_workload_captures 
            WHERE  id in(select capture_id from dba_workload_replays where status='IN PROGRESS')
        ) 
        WHERE clock between min_scn AND max_scn
        AND   rownum < 2;

        IF clock > 0 THEN
            dbms_output.put_line(rpad('WCR: Progress',30)||' = '|| clock || ' %');
        END IF;
    END IF;
    dbms_output.put_line(rpad('IS_REPLAY_PAUSED',30)||' = '|| nvl(status,'NOT STARTED'));
    dbms_output.put_line('.');
    OPEN :c0 FOR
        SELECT ID,
               NAME,
               CAPTURE_ID "CAP|ID",
               PARALLEL "IS|RAC",
               &VER122 NULLIF(RAC_MODE,'GLOBAL_SYNC') "RAC|MODE",
               &VER122 NULLIF(PLSQL_MODE,'TOP_LEVEL') "PLSQL|MODE",
               &VER122 NULLIF(QUERY_ONLY,'N') "QUERY|ONLY",
               (NUM_CLIENTS-NUM_CLIENTS_DONE)||'/'||NUM_CLIENTS "NUM|CLIENTS",
               FILTER_SET_NAME "FILTER|SETNAME",
               SQLSET_OWNER "SQLSET|OWNER",
               SQLSET_NAME "SQLSET|NAME",
               SCHEDULE_NAME "SCHEDULE|NAME",
               CASE SYNCHRONIZATION
                   WHEN 'TRUE' THEN
                     $IF dbms_db_version.version<12 $THEN
                       'TRUE(OBJECT_ID)' 
                     $ELSE 
                       'TRUE(SCN)' 
                     $END
                   WHEN 'FALSE' THEN
                       'FALSE(TIME)'
                   ELSE
                       SYNCHRONIZATION
               END "SYNC|TYPE",
               CONNECT_TIME_SCALE "CONN|SCALE",
               THINK_TIME_SCALE "THINK|SCALE",
               THINK_TIME_AUTO_CORRECT "AUTO|CORRECT",
               SCALE_UP_MULTIPLIER "SCALE|MUTIP",
               '|' "|",
               --DIRECTORY,                
               STATUS,
               --PREPARE_TIME,
               to_char(START_TIME,'MM-DD/HH24:MI') start_time,
               to_char(END_TIME,'MM-DD/HH24:MI') end_time,
               86400*(decode(status,'IN PROGRESS',sysdate,END_TIME)-START_TIME) "DUR",
               '|' "|",
               USER_CALLS        "USER|CALLS",
               round(USER_CALLS/(select nullif(USER_CALLS,0) FROM dba_workload_captures B where b.id=a.capture_id),5) "DONE|CALLS",
               DBTIME            "DB|TIME",
               NETWORK_TIME      "NETWORK|TIME",
               ELAPSED_TIME_DIFF "TIME|GAIN",
               THINK_TIME        "THINK|TIME",
               nullif(PAUSE_TIME,0) "PAUSE|TIME",
               '|' "|",
               --AWR_DBID          "AWR|DBID",
               AWR_BEGIN_SNAP    "AWR|BEGIN",
               AWR_END_SNAP      "AWR|END",
               AWR_EXPORTED      "AWR|EXPORT",
               REPLAY_DIR_NUMBER "DIR|NUM",
               DIRECTORY         "DIR|NAME",
               ERROR_CODE        "ERR|CODE",
               ERROR_MESSAGE     "ERR|MESG"
        FROM   (select * from dba_workload_replays WHERE  dbid = :dbid ORDER BY START_TIME DESC) A
        WHERE  rownum<=20;
    SELECT max(capture_id),
           max(status),
           max(filter_set_name)
    INTO cid,status,fset
    FROM  dba_workload_replays WHERE id=rid;

    IF status IS NOT NULL THEN
        IF lower(:v2) in('text','html') THEN
            :rpt := DBMS_WORKLOAD_REPLAY.REPORT(rid,upper(:V2));
        END IF;
        OPEN :c1 FOR SELECT * FROM dba_workload_replays WHERE id=rid;
        OPEN :c11 FOR
            SELECT * FROM (
                SELECT * 
                FROM dba_workload_connection_map 
                WHERE replay_id=rid 
                ORDER BY nvl2(REPLAY_CONN,1,0),conn_id
            ) WHERE ROWNUM<=30;

        IF fset IS NOT NULL THEN
            OPEN :c12 FOR SELECT * FROM dba_workload_filters WHERE set_name=fset;
        END IF;

        IF cid IS NOT NULL THEN
            OPEN :c2 FOR SELECT * FROM dba_workload_captures WHERE id=cid;
        END IF;

        IF status = 'IN PROGRESS' THEN
            OPEN :c3 FOR 
                SELECT sid||'@'||inst_id sid,
                       CLIENT_PID "Client|PID",
                       nullif(CLOCK,0) "CLOCK|SCN",
                       nullif(WAIT_FOR_SCN,0) "WAIT|SCN",
                       nullif(DEPENDENT_SCN,0) "DEPEND|SCN",
                       nullif(STATEMENT_SCN,0) "STMT|SCN",
                       nullif(COMMIT_WAIT_SCN,0) "COMMIT|SCN",
                       nullif(POST_COMMIT_SCN,0) "POST|SCN",
                       USER_CALLS        "USER|CALLS",
                       CALL_COUNTER      "COUNT|CALLS",
                       DBTIME            "DB|TIME",
                       NETWORK_TIME      "NETWORK|TIME",
                       nullif(TIME_GAIN-TIME_LOSS,0) "TIME|GAIN",
                       THINK_TIME        "THINK|TIME",
                       '|' "|",
                       WRC_ID "WRC|ID",
                       event,
                       FILE_ID,
                       nullif(NEXT_TICKER,0) NEXT_TICKER,
                       FILE_NAME,
                       PROGRAM,
                       LOGON_TIME
                FROM gv$workload_replay_thread 
                WHERE file_id>0
                AND   event not like 'WCR%'
                ORDER BY WRC_ID;
        END IF;
    END IF;
END;
/
PRINT c0
SET PIVOT 1
PRINT c1
SET PIVOT 1
PRINT c2
SET PIVOT DEFAULT
PRINT c11
PRINT c12
PRINT c3

save rpt rat_&V1..txt