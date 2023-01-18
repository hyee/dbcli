/*[[ Analyze 'log file sync' event. Usage: @@NAME [<secs> |-d|-pdb [YYMMDDHH24MI] [YYMMDDHH24MI]] [-avg]
  <secs>: sample interval in seconds
  -avg  : show average values per second instead of total values
  -d    : analyze AWR views(DBA_HIST_*) instead of gv$ views
  -pdb  : analyze AWR PDB views(AWR_PDB_*) instead of gv$ views
  
  --[[
        &flag: default={1} d={dba_hist_} pdb={awr_pdb_}
        &div: default={1} avg={&V1}
        @CHECK_ACCESS_SL: SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
        @did : 12.2={nvl('&dbid'+0,sys_context('userenv','dbid')+0)} default={nvl('&dbid'+0,(select dbid from v$database))}
  --]]
]]*/

set feed off verify OFF
col pct FOR pct3
col delta FOR usmhd2
var cur refcursor
DECLARE
    qry VARCHAR2(32767):=q'!TABLE(gv$(CURSOR (SELECT event NAME, TIME_WAITED_MICRO micro, TOTAL_WAITS cnt, 'Event' typ
                                              FROM   v$system_event
                                              WHERE  (event IN ('log file sync', 'log file parallel write','gcs log flush sync','remote log force - commit') OR
                                                     (event LIKE 'LGWR%' AND event NOT LIKE '%idle'))
                                              AND    userenv('INSTANCE') = nvl('&instance', userenv('INSTANCE'))
                                              AND    time_waited_micro>0
                                              UNION ALL
                                              SELECT NAME, WAIT_TIME, gets, 'Latch'
                                              FROM   v$latch
                                              WHERE  (NAME LIKE 'redo%' OR LOWER(NAME) LIKE '%lgwr%')
                                              AND    wait_time > 0
                                              AND    userenv('INSTANCE') = nvl('&instance', userenv('INSTANCE'))
                                              UNION ALL
                                              SELECT TRIM(NAME), VALUE, NULL, 'Stat'
                                              FROM   v$sysstat
                                              WHERE  VALUE > 0
                                              AND    (name like 'redo%'  or 
                                                      name like '% log %' or 
                                                      name like '%rdma on commit%' or 
                                                      name in('user commits','user rollbacks') or
                                                      name like 'commit%' or 
                                                      name like '%current block%flush%')
                                              AND    userenv('INSTANCE') = nvl('&instance', userenv('INSTANCE')))))!';

    func VARCHAR2(2000);
BEGIN
    IF '&flag'='1' THEN
        IF dbms_db_version.version>11 THEN
            qry:='(SELECT * FROM '||qry||q'!
                  UNION ALL
                  SELECT METRIC_NAME,SUM(METRIC_VALUE),NULL,'Cell'
                  FROM   v$cell_global
                  WHERE  lower(METRIC_NAME) like '%log %'
                  AND    METRIC_VALUE>0
                  GROUP  BY METRIC_NAME)!';
        END IF;
        IF regexp_like(:V1,'^\d+$') THEN
            func :='FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
                    BEGIN
                        IF ID=1 THEN RETURN SYSTIMESTAMP;END IF;
                        &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
                        RETURN SYSTIMESTAMP;
                    END;';
            qry:=replace(q'!SELECT typ, NAME, SUM(DECODE(r, 1, -1, 1) * micro)/&div micro, SUM(DECODE(r, 1, -1, 1) * cnt)/&div cnt
                    FROM   (SELECT /*+no_merge ordered use_nl(timer stat)*/ROWNUM r, SYSDATE + numtodsinterval(&V1, 'second') mr FROM XMLTABLE('1 to 2')) dummy,
                           LATERAL (SELECT /*+no_merge*/do_sleep(dummy.r, dummy.mr) stime FROM dual) timer,
                           LATERAL (SELECT /*+no_merge*/*
                                    FROM   @QRY@
                                    WHERE  timer.stime IS NOT NULL)
                    GROUP  BY TYP, NAME
                    HAVING SUM(DECODE(r, 1, -1, 1) * micro)>0 !','@QRY@',qry);
        ELSE
            qry :=replace(q'!SELECT typ,NAME, SUM(micro) micro, SUM(cnt) cnt
                    FROM   @QRY@
                    GROUP  BY typ,NAME!','@QRY@',qry);
        END IF;
    ELSE
        func := q'!snap AS
                 (SELECT /*+materialize*/
                         DECODE(row_number() OVER(PARTITION BY instance_number ORDER BY mid), 1, mid, -1) mid, 
                         DECODE(row_number() OVER(PARTITION BY instance_number ORDER BY xid desc), 1, xid, -1) xxid, 
                         XID,secs, dbid, instance_number
                  FROM   (SELECT MIN(snap_id) mid, MAX(snap_id) XID, dbid, instance_number,SUM((end_interval_time+0)-(begin_interval_time+0))*86400 secs
                          FROM   &flag.snapshot
                          WHERE  dbid = &did
                          AND    end_interval_time+0 between nvl(to_date(nvl('&V1','&starttime'),'yymmddhh24mi'),sysdate-7) 
                                 and nvl(to_date(nvl('&V2','&endtime'),'yymmddhh24mi'),sysdate+1)
                          GROUP  BY dbid, instance_number, startup_time)),!';
        qry := q'!SELECT 'Event' typ,
                       event_name NAME,
                       SUM(TIME_WAITED_MICRO * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) micro,
                       SUM(TOTAL_WAITS * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) cnt
                FROM   snap a
                JOIN   &flag.system_event b
                USING  (dbid, instance_number)
                WHERE  dbid = &did
                AND    time_waited_micro > 0
                AND    snap_id IN (mid, XID)
                AND    (event_name IN ('log file sync', 'log file parallel write','gcs log flush sync','remote log force - commit') OR (event_name LIKE 'LGWR%' AND event_name NOT LIKE '%idle'))
                GROUP  BY event_name
                UNION ALL
                SELECT 'Latch' typ,
                       latch_name,
                       SUM(WAIT_TIME * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) micro,
                       SUM(GETS * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) cnt
                FROM   snap a
                JOIN   &flag.latch b
                USING  (dbid, instance_number)
                WHERE  dbid = &did --
                 AND   snap_id IN (mid, XID) --
                 AND   wait_time > 0 --
                 AND   (latch_name LIKE 'redo%' OR LOWER(latch_name) LIKE '%lgwr%')
                GROUP  BY latch_name
                UNION ALL
                SELECT 'Stat' typ, stat_name, SUM(VALUE * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) micro, NULL cnt
                FROM   snap a
                JOIN   &flag.sysstat b
                USING  (dbid, instance_number)
                WHERE  dbid = &did --
                 AND   snap_id IN (mid, XID) --
                 AND   (stat_name LIKE 'redo%' or 
                        stat_name like '% log %' or 
                        stat_name like '%rdma on commit%' or 
                        stat_name in('user commits','user rollbacks') or
                        stat_name like 'commit%' or
                        stat_name like '%current block%flush%')
                 AND   VALUE > 0
                GROUP  BY stat_name!';
        IF dbms_db_version.version>11 THEN
            qry:= qry||q'!
                UNION ALL
                SELECT 'Cell' typ, metric_name, SUM(metric_value * DECODE(snap_id, mid, -1, 1))/decode('&div','1',1,SUM(secs)) micro, NULL cnt
                FROM   snap a
                JOIN   &flag.cell_global b
                USING  (dbid)
                WHERE  dbid = &did --
                 AND   INSTANCE_NUMBER=1
                 AND   snap_id IN (mid, xxid) --
                 AND   lower(METRIC_NAME) like '%log %'
                 AND   metric_value > 0
                GROUP  BY metric_name!';
        END IF;
    END IF;
    qry:=replace(replace(q'!
        WITH @FUNC@
        STATS AS(
            SELECT /*+inline no_merge*/ *
            FROM   (@QUERY@)
            MODEL DIMENSION BY (NAME)
            MEASURES(typ,round(micro,2) micro,round(cnt,2) cnt,to_number(NULL) avg_time,to_number(NULL) delta_time,to_number(NULL) delta_pct)
            RULES SEQUENTIAL ORDER(
                    cnt['redo size']=micro['redo writes'],
                    cnt['redo wastage']=micro['redo size'],
                    micro['redo write time (usec)']=NVL(micro['redo write time (usec)'],micro['redo write time']*1e4),
                    cnt['redo write time (usec)']=micro['redo writes'],
                    cnt[NAME IN('redo synch time (usec)','redo synch time overhead (usec)','redo synch long waits')]=micro['redo synch writes'],
                    cnt['redo log space wait time']=micro['redo log space requests'],
                    micro['redo log space wait time']=micro[cv()]*1e4,
                    micro['user transactions']=sum(micro)[name in('user commits','user rollbacks')],
                    cnt['commit cleanouts successfully completed']=micro['commit cleanouts'],
                    cnt[NAME LIKE 'redo write % time' OR NAME in('redo write worker delay (usec)','redo writes coalesced','cell pmem log writes','flashback log writes','Redo log write requests','user transactions')]=micro['redo writes'],
                    cnt[NAME LIKE 'redo synch fast sync % (usec)']=micro[REPLACE(CV(),'(usec)','count')],
                    cnt['avg_redo_synch_polls']=micro['redo synch poll writes'],
                    cnt['redo writes adaptive all']=micro['redo writes'],
                    cnt['redo writes adaptive worker']=micro['redo writes adaptive all'],
                    micro['avg_redo_synch_polls']=micro['redo synch polls'],
                    cnt['expect_redo_synch_time']=micro['redo writes'],
                    micro['expect_redo_synch_time']=2*(nvl(micro['redo write broadcast ack time'],0)+nvl(micro['redo write time (usec)'],0)),
                    cnt['synch_write_post_wait_ratio']=micro['redo synch writes'],
                    micro['synch_write_post_wait_ratio']=micro['redo synch writes']-nvl(micro['redo synch poll writes'],0),
                    cnt['synch_write_ratio']=micro['redo writes'],
                    micro['synch_write_ratio']=micro['redo synch writes'],
                    micro['redo synch PMEM prep time']=SUM(micro)[NAME LIKE 'redo synch fast sync % (usec)'],
                    cnt['redo synch PMEM prep time']=SUM(micro)[NAME LIKE 'redo synch fast sync % count'],
                    micro['redo write broadcasts']=sum(micro)[name like 'redo write broadcast% count' or name='broadcast rdma on commit (actual)'],
                    cnt['redo write broadcasts']=micro['redo writes'],
                    cnt['flashback log write bytes']=micro['flashback log writes'],
                    cnt['gc current block flush time']=micro['gc current blocks flushed'],
                    micro[name in('gc current block flush time')]=micro[cv()]*1e4,
                    cnt[name in('PMEM log write requests','Redo log write I/O latency','Redo log write request latency')]=micro['Redo log write requests'],
                    cnt[name like 'Flash log%writ%']=micro['Flash log redo writes serviced'],
                    micro['Flash log redo write bytes']=SUM(micro)[name like 'Flash log redo bytes%'],
                    typ['Flash log redo write bytes']='Cell',
                    cnt['Flash log redo write bytes']=micro['redo size'],
                    avg_time[ANY]=round(micro[CV()]/nullif(cnt[CV()],0),2),
                    delta_time[NAME IN('redo write worker delay (usec)','redo write broadcast ack time','redo synch time overhead (usec)')]=avg_time[CV()],
                    delta_time['redo write gather time']=avg_time['redo write gather time']-nvl(avg_time['redo write worker delay (usec)'],0),
                    delta_time['redo write schedule time']=avg_time['redo write schedule time']-avg_time['redo write gather time'],
                    delta_time['redo write issue time']=avg_time['redo write issue time']-avg_time['redo write schedule time'],
                    delta_time['redo write finish time']=avg_time['redo write finish time']-nvl(avg_time['redo write issue time'],avg_time['redo write schedule time']),
                    delta_time['redo write time (usec)']=avg_time['redo write time (usec)']-avg_time['redo write finish time'],
                    delta_time['redo write total time']=round(avg_time['redo write total time']-avg_time['expect_redo_synch_time']/2,2),
                    delta_time['redo synch time (usec)']=round((micro['redo synch time (usec)']-avg_time['expect_redo_synch_time']/2*LEAST(micro['redo synch writes'],micro['redo writes']))/micro['redo synch writes'],2),
                    micro['redo total time']=SUM(delta_time*cnt)[ANY],
                    delta_pct[ANY]=round(delta_time[CV()]*cnt[CV()]/micro['redo total time'],5),
                    delta_pct[SUBSTR(NAME,1,3) IN('log','gcs','rem') OR NAME IN('redo allocation','redo copy','redo writing','lgwr LWN SCN','Redo log write request latency','Redo log write I/O latency')]=round(micro[CV()]/micro['redo total time'],5),
                    delta_pct[SUBSTR(NAME,1,3) IN('LGW')]=round(micro[CV()]/micro['log file parallel write'],5),
                    cnt['redo write broadcast ack time']=sum(micro)[name in('redo write broadcast ack count','broadcast rdma on commit (actual)')],
                    cnt['redo synch time overhead (usec)']=sum(micro)[name like 'redo synch time overhead count%'],
                    cnt['redo write worker delay (usec)']=micro['redo write worker delay count'],
                    avg_time[name in ('redo write worker delay (usec)','redo write broadcast ack time','redo synch time overhead (usec)')]=round(micro[CV()]/nullif(cnt[CV()],0),2)
            )
        )
        SELECT NVL(typ,'Stat') TYPE,
               decode(typ,'Event',DECODE(SUBSTR(NAME,1,3),'LGW','  '),
                          'Latch','',
                          'Cell','',
                          nvl2(delta_pct,'  ',''))||NAME NAME,
               micro "Count or us",cnt,avg_time value,delta_time delta,delta_pct pct,
               DECODE(NAME,
                     'log file parallel write','_use_single_log_writer/_max_outstanding_log_writes/_high_priority_processes/_adaptive_scalable_log_writer_enable_worker_aging/threshold',
                     'LGWR any worker group','All LGWR slave groups busy doing write',
                     'LGWR all worker groups','LGWR waiting for all groups to finish action (e.g., close log for log switch)',
                     'LGWR intra group IO completion','Uneven slave write I/O time within slave group',
                     'LGWR worker group ordering','Uneven redo write time(queuing) across slave groups',
                     'LGWR intra group sync','Non-master slaves waiting on master to update on-disk SCN before posting FGs',
                     'LGWR wait for redo copy','copy change vectors INTO public redo strand and applying change to buffers',
                     'redo write gather time','gather the redo from the strands and wait for FGs to finish copying redo, and preprocessing I/O',
                     'redo write schedule time','setup I/O contexts',
                     'redo write issue time','submit async I/O requests',
                     'redo write finish time','I/O time (log file parallel write)',
                     'redo write time (usec)','I/O postprocessing (e.g., check I/O completion status)',
                     'redo write broadcast ack time','broadcast on commit(including rdma) for RAC',
                     'redo write total time','post FGs',
                     'redo log space wait time','Time on waiting for space in the log buffer',
                     'redo synch time (usec)','FGs spending waiting for LGWR to write the redo for commit',
                     'redo synch time overhead (usec)','Time between LGWR updates the on-disk SCN and FG detects that the on-disk SCN >= commit SCN. The value reveals inefficiencies in (post/wait or polling)',
                     'avg_redo_synch_polls','_adaptive_log_file_sync_poll_aggressiveness,should be closed to 1',
                     'expect_redo_synch_time','_adaptive_log_file_sync_use_polling_threshold,expected redo sync time',
                     'synch_write_post_wait_ratio','_adaptive_log_file_sync_use_postwait_threshold,large ratio means oustanding post/wait',
                     'synch_write_ratio','_adaptive_log_file_sync_use_postwait_threshold,large value means outstanding redo write queuing',
                     'redo synch PMEM prep time','_fg_fast_sync_spin_usecs/_fg_fast_sync_sleep_target_pct',
                     'redo size','ratio = redo size/writes',
                     'redo synch long waits','incr if "actual synch time" > expect_redo_synch_time * _adaptive_log_file_sync_use_polling_threshold%',
                     'redo wastage','ratio = redo wastage/size',
                     'redo writes adaptive all','ratio = redo adaptives/writes',
                     'redo writes adaptive worker','ratio = redo adaptive worker/all',
                     'redo writes coalesced','ratio = _redo_write_coalesce_all/slave_threshold(default 1MB on Exadata), coalescing the redo writes when less than the threshold in an in-memory buffer to reduce I/O',
                     'cell pmem log writes','ratio = ratio = pmem writes / redo writes, parameter: _smart_log_threshold_usec',
                     'commit cleanouts successfully completed','ratio = completed/cleanouts,number of blocks attempted to update the ITL entry and set commit SCN at commit time',
                     'redo write broadcasts','ratio = (redo write broadcast+broadcast rdma on commit)*/redo writes',
                     'redo allocation','The latch to request public redo strands(_log_parallelism_max)',
                     'redo write worker delay (usec)','time between when LGWR asks the worker to start doing the write and when the worker actually starts running'
               ) memo
        FROM   STATS s
        WHERE  (cnt IS NOT NULL AND micro IS NOT NULL)
        ORDER BY DECODE(typ,'Latch',10,'Cell',11,
                        'Event',DECODE(NAME,'log file parallel write',1,'log file sync',8,decode(substr(name,1,4),'LGWR',2,3)),9),
                 NVL2(delta_pct,0,2-SIGN(INSTR(s.NAME,'_'))),
                 DECODE(trim(NAME),
                             'redo write worker delay (usec)',0,
                             'redo write gather time',1,
                             'redo write schedule time',2,
                             'redo write issue time',3,
                             'redo write finish time',4,
                             'redo write time (usec)',5,
                             'redo write broadcast ack time',6,
                             'redo write total time',7,
                             'redo synch time overhead (usec)',8,
                             'redo synch time (usec)',9,
                             99),
                 NVL2(avg_time,1,2),
                 NAME!','@QUERY@',qry),'@FUNC@',func);
    OPEN :cur FOR qry;
END;
/
print cur
