/*[[
  Show delta event histogram relative to target event. Usage: @@NAME <0|sample secs> [-lgwr|-io|-gc|-w"<event|wait_class>"|-f"filter"] [-c]
  
  Parameters:
    sample secs: the interval to sample the stats in order to calc the delta values. When 0 then calc all stats instead of delta stats
    -lgwr: the events relative to LGWR
    -io  : the events belong to User/System I/O
    -gc  : the events belong to Cluster waits
    -w   : the events belong to specific event/wait class
    -c   : the percentages of the histogram is based on wait count, instead of wait time
	--[[
		@ver: 12.1={}
		@CHECK_ACCESS_SL: SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
		&v1: default={10}
    &u : default={*slot_time*0.75} c={}
    &filter: {
        all={1=1}
        lgwr={event IN ('log file sync',
                       'log file parallel write',
                       'LGWR any worker group',
                       'LGWR all worker groups',
                       'LGWR wait for redo copy',
                       'LGWR worker group ordering',
                       'latch: redo allocation',
                       'latch: redo writing',
                       'ASM IO for non-blocking poll',
                       'gcs log flush sync',
                       'log file switch completion',
                       'log file switch (checkpoint incomplete)',
                       'log file switch (private strand flush incomplete)')},
        io={wait_class in('System I/O','User I/O')},
        gc={wait_class='Cluster' or event like 'gc%'},
        w={lower('&0') in (lower(event),lower(wait_class))},
        f={}
    }
	--]]
]]*/

col Time/s,avg_time for usmhd2
col Waits/s for k1
pro Sampling stats for &V1 seconds, the values of histogram are the percentages of [wait_count&u]:
pro ========================================================================================================
WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
    BEGIN
        IF ID in(-1,0) THEN RETURN SYSTIMESTAMP;END IF;
        &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
        RETURN SYSTIMESTAMP;
    END;
SELECT *
FROM   (SELECT /*+ordered use_nl(timer stat) no_merge(stat) no_expand*/
               event,
               CASE
                   WHEN slot_time <= 512 THEN
                    '<' || slot_time || 'us'
                   WHEN slot_time <= 524288 THEN
                    '<' || round(slot_time / 1024) || 'ms'
                   WHEN slot_time <= 33554432 THEN
                    '<' || round(slot_time / 1024/1024) || 's'
                   WHEN slot_time <= 67108864 THEN
                    '<' || round(slot_time / 1024/1024/64) || 'm'
                   ELSE
                    '>=1m'
               END unit,
               max(SUM(TIME_WAITED_MICRO * r)/sec) over(partition by event) "Time/s",
               max(ROUND(SUM(TIME_WAITED_MICRO * r) / NULLIF(SUM(total_waits * r), 0), 2)) over(partition by event) avg_time,
               '|' "|",
               max(SUM(total_waits * r)/sec) over(partition by event) "Waits/s",
               nullif(round(ratio_to_report(SUM(svalue * r  &u)) OVER(PARTITION BY event) * 100, 2), 0) pct
        FROM   (SELECT /*+no_merge*/ 
                       greatest(&V1,1) sec,
                       DECODE(ROWNUM, 1, decode(&v1,0,1,-1), decode(&v1,0,0,1)) r, 
                       SYSDATE + numtodsinterval(&v1, 'second') mr 
                FROM XMLTABLE('1 to 2')) dummy,
               LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual where dummy.r!=0) timer,
               LATERAL (SELECT /*+ordered use_hash(a b)*/ 
                               event, 
                               a.total_waits,
                               a.time_waited_micro,
                               b.wait_time_micro slot_time,
                               b.wait_count svalue
                        FROM   gv$system_event a
                        JOIN   gv$event_histogram_micro b
                        USING  (inst_id, event)
                        WHERE  timer.stime IS NOT NULL
                        AND    (&filter)) stat
        GROUP  BY event,sec,
                  CASE
                      WHEN slot_time <= 512 THEN
                       '<' || slot_time || 'us'
                      WHEN slot_time <= 524288 THEN
                       '<' || round(slot_time / 1024) || 'ms'
                      WHEN slot_time <= 33554432 THEN
                       '<' || round(slot_time / 1024/1024) || 's'
                      WHEN slot_time <= 67108864 THEN
                       '<' || round(slot_time / 1024/1024/64) || 'm'
                      ELSE
                       '>=1m'
                  END
        HAVING (:filter!='1=1' OR SUM(total_waits * r)>0))
 PIVOT(MAX(pct)
        FOR    unit IN('<1us' "<1us",
                      '<2us' "<2us",
                      '<4us' "<4us",
                      '<8us' "<8us",
                      '<16us' "<16us",
                      '<32us' "<32us",
                      '<64us' "<64us",
                      '<128us' "<128us",
                      '<256us' "<256us",
                      '<512us' "<512us",
                      '<1ms' "<1ms",
                      '<2ms' "<2ms",
                      '<4ms' "<4ms",
                      '<8ms' "<8ms",
                      '<16ms' "<16ms",
                      '<33ms' "<33ms",
                      '<66ms' "<66ms",
                      '<131ms' "<131ms",
                      '<262ms' "<262ms",
                      '<524ms' "<524ms",
                      '<1s' "<1s",
                      '<2s' "<2s",
                      '<4s' "<4s",
                      '<8s' "<8s",
                      '<17s' "<17s",
                      '<34s' "<34s",
                      '<1m' "<1m",
                      '>=1m' ">=1m"))
ORDER BY "Time/s" DESC,DECODE(event,'log file sync',' ',lower(event))