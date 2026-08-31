/*[[
    Show Real Application Testing info. Usage: @@NAME [-diag] [-rm|-rrm] [{<replay id> [text|html]} | pause | resume | cancel]
    Parameters:
    -----------
    -rm      : build the resource manager plan DBCLI_RAT_PLAN, whose consumer group DBCLI_RAT_GROUP
               is defined with max_idle_blocker_time=3, so a session holding a lock while idle for
               3 seconds is rolled back. That releases the row locks and lets the pending SCN
               dependencies proceed, which is the usual way to unblock a replay hanging with many
               idle WRC clients.
               The users of the running replay sessions are mapped into that group by ORACLE_USER,
               so the other sessions are not affected. If no replay session is found then nobody is
               mapped and the plan stays harmless, map the users manually in that case.
    -rrm     : remove the objects above: reset resource_manager_plan to empty, drop the plan with
               all of its directives, remove every mapping pointing to the group(by calling
               set_consumer_group_mapping with a NULL group) and drop the group.
               Both options first remove whatever exists, -rrm simply stops after that step.
               The order matters: the plan has to be reset before it can be dropped, and the
               mappings have to be removed before the group can be dropped.
               Both require the ADMINISTER RESOURCE MANAGER and the ALTER SYSTEM privileges.
    -diag    : analyze why the replay is hanging, i.e. there are still lots of captured calls pending
               while many WRC clients stay idle. It reports:
                 1) the distribution of the replay thread waits(WCR events vs real database waits)
                 2) the SCN dependency chain: which thread is waiting for which thread's commit
                 3) the replay sessions that are stuck on a real database wait(row lock/buffer busy/...),
                    this is the root cause in most cases
                 4) the per-instance WRC coverage, a missing WRC on any instance stalls everything
                 5) the threads that are only waiting for the replay clock(ticker), which usually means
                    connect_time_scale / think_time_scale is stretching the schedule
               Note: the replay calls are bound to the captured connections, NOT taken from a global
               queue. So one stuck connection blocks every call that depends on its commit, and the
               other WRC clients cannot take over its work.
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
        &diag  : default={0} diag={1}
        &diagp : default={--} diag={}
        &rm    : default={0} rm={1} rrm={2}
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
VAR cd1 refcursor "Diag-1: SCN Dependency Chain";
VAR cd2 refcursor "Diag-2: Replay Sessions Stuck On Real Waits";
VAR cd3 refcursor "Diag-3: Per-Instance WRC Coverage";
VAR cd4 refcursor "Diag-4: Threads Waiting For The Replay Clock";
VAR rpt CLOB;

DECLARE
    v1     VARCHAR2(128) := upper(:v1);
    rid    INT := regexp_substr(v1,'^\d+$');
    cid    INT;
    clock  NUMBER;
    status VARCHAR2(50);
    paused VARCHAR2(3);
    fset   VARCHAR2(50);
    cnt    INT;
    options SYS.ODCIVARCHAR2LIST;
    c_plan  CONSTANT VARCHAR2(30) := 'DBCLI_RAT_PLAN';
    c_group CONSTANT VARCHAR2(30) := 'DBCLI_RAT_GROUP';
BEGIN
    BEGIN
        status := CASE WHEN dbms_workload_replay.is_replay_paused() THEN 'YES' ELSE 'NO' END;
        EXCEPTION WHEN OTHERS THEN NULL;
    END;
    paused := status;
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
                                    'REPLAY_TIMEOUT_FACTOR',
                                    'USE_RECORDED_SYSGUID',
                                    'USE_RECORDED_RANDOM',
                                    'USE_RECORDED_SYSDATETIME');
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
        FROM   (select * from dba_workload_replays ORDER BY START_TIME DESC) A
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

    --=================== Hang Diagnosis ===================
    --Note: host/bind variables cannot be placed inside $IF..$END, so a runtime
    --      IF is used here instead of the conditional compilation directive
    IF &diag=1 AND paused IS NOT NULL THEN
        dbms_output.put_line('Replay Hang Diagnosis:');
        dbms_output.put_line('======================');
        FOR r IN(SELECT * FROM dba_workload_replays WHERE id=rid) LOOP
            dbms_output.put_line(rpad('Sync Mode',32)||' = '||r.synchronization||
                                 CASE WHEN r.synchronization IN('TRUE','SCN')
                                      THEN '   <== commit order preserved, one stuck commit blocks its followers'
                                      WHEN r.synchronization='OBJECT_ID'
                                      THEN '   <== waits for every commit on the referenced objects'
                                 END);
            dbms_output.put_line(rpad('Connect Time Scale',32)||' = '||r.connect_time_scale||
                                 CASE WHEN r.connect_time_scale>100
                                      THEN '   <== stretched, sessions connect later than captured' END);
            dbms_output.put_line(rpad('Think Time Scale',32)||' = '||r.think_time_scale||
                                 CASE WHEN r.think_time_scale>100
                                      THEN '   <== stretched, calls are paced slower than captured' END);
            dbms_output.put_line(rpad('Scale-Up Multiplier',32)||' = '||r.scale_up_multiplier||
                                 CASE WHEN r.scale_up_multiplier>1
                                      THEN '   <== scale-up sessions only replay read-only calls, they are idle by design' END);
        END LOOP;

        dbms_output.put_line(lpad('-',60,'-'));
        dbms_output.put_line('Distribution of the replay thread waits:');
        FOR r IN(SELECT evt,COUNT(1) c
                 FROM  (SELECT CASE WHEN event LIKE 'WCR:%' THEN event
                                    ELSE 'NON-WCR: '||NVL(event,'<idle>')
                               END evt
                        FROM   gv$workload_replay_thread)
                 GROUP  BY evt
                 ORDER  BY c DESC) LOOP
            dbms_output.put_line('  '||rpad(r.evt,42)||' = '||r.c);
        END LOOP;

        SELECT COUNT(1)
        INTO   cnt
        FROM   gv$workload_replay_thread
        WHERE  file_id>0
        AND    wait_for_scn IS NOT NULL;
        dbms_output.put_line(lpad('-',60,'-'));
        dbms_output.put_line('Threads blocked by SCN dependencies : '||cnt);
        IF cnt>0 THEN
            dbms_output.put_line('  -> see "Diag-1: SCN Dependency Chain" for who waits for whom');
        END IF;

        SELECT COUNT(1)
        INTO   cnt
        FROM   gv$workload_replay_thread t, gv$session s
        WHERE  t.file_id>0
        AND    t.sid=s.sid
        AND    t.inst_id=s.inst_id
        AND    s.event NOT LIKE 'WCR:%'
        AND    s.wait_class!='Idle';
        dbms_output.put_line('Replay sessions stuck on real waits : '||cnt);
        IF cnt>0 THEN
            dbms_output.put_line('  -> ROOT CAUSE candidate, see "Diag-2: Replay Sessions Stuck On Real Waits"');
        END IF;

        SELECT COUNT(1)
        INTO   cnt
        FROM   gv$workload_replay_thread
        WHERE  file_id>0
        AND    next_ticker>0
        AND    wait_for_scn IS NULL;
        dbms_output.put_line('Threads only waiting for the clock  : '||cnt);
        IF cnt>0 THEN
            dbms_output.put_line('  -> paced by connect_time_scale/think_time_scale, see "Diag-4"');
        END IF;

        BEGIN
            IF dbms_workload_replay.get_advanced_parameter('REPLAY_TIMEOUT_ENABLED')='FALSE' THEN
                dbms_output.put_line(lpad('-',60,'-'));
                dbms_output.put_line('* Replay timeout is DISABLED, a stuck call hangs the replay forever.');
                dbms_output.put_line('  Enable it online: exec dbms_workload_replay.set_replay_timeout(TRUE,10,60,4)');
            END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
        END;

        --Diag-1: which thread is waiting for which thread's commit
        OPEN :cd1 FOR
            WITH t AS(
                SELECT /*+materialize*/ sid,inst_id,wrc_id,file_id,event,program,
                       clock,wait_for_scn,dependent_scn,statement_scn,commit_wait_scn,post_commit_scn,
                       user_calls,call_counter,next_ticker
                FROM   gv$workload_replay_thread
                WHERE  file_id>0)
            SELECT w.sid||'@'||w.inst_id "WAITING|SID",
                   w.wrc_id "WRC|ID",
                   NVL(w.event,'<idle>') "WAITING|EVENT",
                   w.wait_for_scn "WAIT|SCN",
                   w.dependent_scn "DEPEND|SCN",
                   w.call_counter "CALLS",
                   '|' "|",
                   b.sid||'@'||b.inst_id "BLOCKING|SID",
                   b.wrc_id "B|WRC",
                   NVL(b.event,'<idle>') "BLOCKING|EVENT",
                   b.commit_wait_scn "B|COMMIT_SCN",
                   b.post_commit_scn "B|POST_SCN",
                   b.call_counter "B|CALLS",
                   b.file_id "B|FILE_ID",
                   CASE WHEN b.event IS NULL OR b.event NOT LIKE 'WCR:%'
                        THEN 'ROOT CAUSE: blocked by a real database wait'
                        ELSE 'waiting inside the replay engine' END "NOTE"
            FROM   t w, t b
            WHERE  w.wait_for_scn IS NOT NULL
            AND    (b.commit_wait_scn = w.wait_for_scn OR b.post_commit_scn = w.wait_for_scn)
            ORDER  BY "NOTE", w.sid;

        --Diag-2: the replay sessions that are stuck on a real database wait
        OPEN :cd2 FOR
            SELECT s.inst_id,
                   s.sid,
                   s.serial#,
                   t.wrc_id "WRC|ID",
                   t.file_id "FILE|ID",
                   t.call_counter "CALLS",
                   t.wait_for_scn "WAIT|SCN",
                   '|' "|",
                   s.event,
                   s.wait_class "WAIT|CLASS",
                   round(s.seconds_in_wait) "SECS|IN_WAIT",
                   s.blocking_instance "BLK|INST",
                   s.blocking_session "BLK|SID",
                   s.final_blocking_instance "FBLK|INST",
                   s.final_blocking_session "FBLK|SID",
                   s.sql_id,
                   s.row_wait_obj# "ROW|OBJ#"
            FROM   gv$session s, gv$workload_replay_thread t
            WHERE  t.file_id>0
            AND    t.sid=s.sid
            AND    t.inst_id=s.inst_id
            AND    s.event NOT LIKE 'WCR:%'
            AND    s.wait_class!='Idle'
            ORDER  BY s.seconds_in_wait DESC;

        --Diag-3: a missing WRC on any instance stalls the whole replay
        OPEN :cd3 FOR
            SELECT inst_id,
                   COUNT(DISTINCT wrc_id) "WRC|COUNT",
                   COUNT(1) "THREADS",
                   SUM(CASE WHEN event='WCR: replay client notify' THEN 1 ELSE 0 END) "IDLE|NOTIFY",
                   SUM(CASE WHEN event LIKE 'WCR:%' THEN 0 ELSE 1 END) "NON|WCR",
                   SUM(CASE WHEN wait_for_scn IS NOT NULL THEN 1 ELSE 0 END) "WAIT|SCN",
                   MAX(clock) "MAX|CLOCK"
            FROM   gv$workload_replay_thread
            GROUP  BY inst_id
            ORDER  BY inst_id;

        --Diag-4: threads that are only paced by the replay clock
        OPEN :cd4 FOR
            SELECT *
            FROM  (SELECT sid||'@'||inst_id "SID",
                          wrc_id "WRC|ID",
                          NVL(event,'<idle>') event,
                          clock "CLOCK|SCN",
                          next_ticker "NEXT|TICKER",
                          next_ticker-clock "TICKS|BEHIND",
                          user_calls "USER|CALLS",
                          call_counter "COUNT|CALLS",
                          file_id,
                          file_name
                   FROM   gv$workload_replay_thread
                   WHERE  file_id>0
                   AND    next_ticker>0
                   ORDER  BY next_ticker-clock DESC)
            WHERE  rownum<=20;
    END IF;

    --=================== Resource Manager ==================
    --&rm=1(-rm): drop whatever exists, then create;  &rm=2(-rrm): drop only
    IF &rm>0 THEN
        dbms_output.put_line('Resource Manager:');
        dbms_output.put_line('==================');

        --1) reset the plan first, a plan that is in use cannot be dropped
        BEGIN
            EXECUTE IMMEDIATE 'ALTER SYSTEM SET resource_manager_plan=''''';
            dbms_output.put_line('* resource_manager_plan is reset to empty');
            EXCEPTION WHEN OTHERS THEN
                raise_application_error(-20001,'* cannot reset resource_manager_plan: '||sqlerrm);
        END;

        --2) drop the plan together with all of its directives
        BEGIN
            dbms_resource_manager.clear_pending_area();
            dbms_resource_manager.create_pending_area();
            dbms_resource_manager.delete_plan_cascade(plan=>c_plan);
            dbms_resource_manager.submit_pending_area();
            dbms_output.put_line('* plan '||c_plan||' is dropped');
            EXCEPTION WHEN OTHERS THEN
                dbms_output.put_line('* plan '||c_plan||' is absent or cannot be dropped: '||sqlerrm);
        END;

        --3) drop the mappings, set_consumer_group_mapping with a NULL group removes the rule
        FOR r IN(SELECT attribute,value
                 FROM   dba_rsrc_group_mappings
                 WHERE  consumer_group = c_group) LOOP
            BEGIN
                dbms_resource_manager.set_consumer_group_mapping(
                    attribute      => r.attribute,
                    value          => r.value,
                    consumer_group => NULL);
                dbms_output.put_line('* unmapped '||r.attribute||' = '||r.value);
                EXCEPTION WHEN OTHERS THEN
                    dbms_output.put_line('* cannot unmap '||r.attribute||' = '||r.value||': '||sqlerrm);
            END;
        END LOOP;

        --4) drop the group at last, it fails while a mapping still refers to it
        BEGIN
            dbms_resource_manager.clear_pending_area();
            dbms_resource_manager.create_pending_area();
            dbms_resource_manager.delete_consumer_group(consumer_group=>c_group);
            dbms_resource_manager.submit_pending_area();
            dbms_output.put_line('* consumer group '||c_group||' is dropped');
            EXCEPTION WHEN OTHERS THEN
                dbms_output.put_line('* group '||c_group||' is absent or cannot be dropped: '||sqlerrm);
        END;

        IF &rm=2 THEN
            RETURN;
        END IF;

        BEGIN
            dbms_resource_manager.clear_pending_area();
            dbms_resource_manager.create_pending_area();
            dbms_resource_manager.create_consumer_group(
                consumer_group => c_group,
                comment        => 'dbcli: RAT replay sessions, idle blockers are rolled back after 3s');
            dbms_resource_manager.create_plan(
                plan    => c_plan,
                comment => 'dbcli: RAT replay, max_idle_blocker_time=3');
            dbms_resource_manager.create_plan_directive(
                plan                  => c_plan,
                group_or_subplan      => c_group,
                comment               => 'roll back the session if it blocks others while idle for 3s',
                max_idle_blocker_time => 3);
            dbms_resource_manager.create_plan_directive(
                plan             => c_plan,
                group_or_subplan => 'SYS_GROUP',
                comment          => 'dbcli: not affected');
            dbms_resource_manager.create_plan_directive(
                plan             => c_plan,
                group_or_subplan => 'OTHER_GROUPS',
                comment          => 'dbcli: not affected by max_idle_blocker_time');
            dbms_resource_manager.validate_pending_area();
            dbms_resource_manager.submit_pending_area();
            dbms_output.put_line('* plan '||c_plan||' created, group '||c_group||' with max_idle_blocker_time=3');
            EXCEPTION WHEN OTHERS THEN
                dbms_output.put_line('* cannot create the plan: '||sqlerrm);
                dbms_output.put_line('  the ADMINISTER RESOURCE MANAGER privilege is required');
        END;

        --only the users of the running replay sessions are mapped into the group
        cnt := 0;
        FOR r IN(SELECT DISTINCT s.username
                 FROM   gv$session s, gv$workload_replay_thread t
                 WHERE  t.sid=s.sid
                 AND    t.inst_id=s.inst_id
                 AND    s.username IS NOT NULL
                 AND    s.username NOT IN('SYS','SYSTEM')) LOOP
            BEGIN
                dbms_resource_manager.set_consumer_group_mapping(
                    attribute      => dbms_resource_manager.oracle_user,
                    value          => r.username,
                    consumer_group => c_group);
                dbms_output.put_line('* mapped ORACLE_USER '||r.username||' -> '||c_group);
                cnt := cnt+1;
                EXCEPTION WHEN OTHERS THEN
                    dbms_output.put_line('* cannot map user '||r.username||': '||sqlerrm);
            END;
        END LOOP;

        IF cnt=0 THEN
            dbms_output.put_line('* no replay session found, nobody is mapped into '||c_group||' yet.');
            dbms_output.put_line('  map the replay users manually:');
            dbms_output.put_line('  exec dbms_resource_manager.set_consumer_group_mapping(dbms_resource_manager.oracle_user,''<USER>'','''||c_group||''')');
            return;
        END IF;

        BEGIN
            EXECUTE IMMEDIATE 'ALTER SYSTEM SET resource_manager_plan='''||c_plan||'''';
            dbms_output.put_line('* resource_manager_plan = '||c_plan);
            EXCEPTION WHEN OTHERS THEN
                dbms_output.put_line('* cannot enable the plan: '||sqlerrm);
        END;
        dbms_output.put_line('  to switch it off: rat -rrm');
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
&diagp PRINT cd1
&diagp PRINT cd2
&diagp PRINT cd3
&diagp PRINT cd4

save rpt rat_&V1..txt