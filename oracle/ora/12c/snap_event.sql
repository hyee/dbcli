/*[[Show delta event histogram relative to target event. Usage: @@NAME {<0|secs> [0|inst_id]} [-lgwr|-io|-gc|-w"<event|wait_class>"|-f"<filter>"] [-c|-n]
  
  Parameters:
    secs : the interval to sample the stats in order to calc the delta values. When 0 then calc all stats instead of delta stats
    -lgwr: show only the events relative to LGWR
    -io  : show only the events belong to User/System I/O
    -gc  : show only the events belong to Cluster waits
    -w   : show only the events belong to specific event/wait class
    -c   : the percentages of the histogram is based on wait count, instead of wait time
    -n   : the value of the histogram is the number of waits, instead of percentage
	--[[
    @ver: 12={}
		@CHECK_ACCESS_SL: SYS.DBMS_LOCK={SYS.DBMS_LOCK} DEFAULT={DBMS_SESSION}
		&v1: default={10}
    &u : t={*log(2,slot_time*2)} c={}
    &calc: default={ratio_to_report(SUM(svalue * r  &u)) OVER(PARTITION BY inst,wait_class,event) * 100} n={SUM(svalue * r  &u)}
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
set COLAUTOSIZE trim sep4k on
col Time/s,avg_time for usmhd2
col Waits/s for k1
col g noprint
pro Sampling stats for &V1 seconds, the values of histogram are the percentages of [wait_count&u]:
pro =============================================================================================================
WITH FUNCTION do_sleep(id NUMBER,target DATE) RETURN TIMESTAMP IS
    BEGIN
        IF ID in(-1,0) THEN RETURN SYSTIMESTAMP;END IF;
        &CHECK_ACCESS_SL..sleep(greatest(1,86400*(target-sysdate)));
        RETURN SYSTIMESTAMP;
    END;
SELECT *
FROM   (SELECT /*+ordered use_nl(timer stat) no_merge(stat) no_expand*/
               nullif(inst,0) inst,nvl(event,'- Wait Class: '||nvl(wait_class,'All')) event,
               grouping_id(wait_class,event) g,
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
               max(SUM(micro * r)/sec) over(partition by inst,wait_class,event) "Time/s",
               max(ROUND(SUM(micro * r) / NULLIF(SUM(total_waits * r), 0), 2)) over(partition by inst,wait_class,event) avg_time,
               '|' "|",
               max(SUM(total_waits * r)/sec) over(partition by inst,wait_class,event) "Waits/s",
               nullif(round(&calc, 2), 0) pct
        FROM   (SELECT /*+no_merge*/ 
                       greatest(&V1,1) sec,
                       DECODE(ROWNUM, 1, decode(&v1,0,1,-1), decode(&v1,0,0,1)) r, 
                       SYSDATE + numtodsinterval(&v1, 'second') mr 
                FROM XMLTABLE('1 to 2')) dummy,
               LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual where dummy.r!=0) timer,
               LATERAL (SELECT /*+ordered use_hash(a b)*/
                               decode(lower(nvl('&v2','a')),'a',0,inst_id)  inst,
                               event, 
                               a.total_waits,
                               a.time_waited_micro micro,
                               b.wait_time_micro slot_time,
                               b.wait_count svalue,
                               a.wait_class
                        FROM   gv$system_event a
                        JOIN   gv$event_histogram_micro b
                        USING  (inst_id, event)
                        WHERE  timer.stime IS NOT NULL
                        AND    lower(nvl('&v2','a')) in('a','0',to_char(inst_id))
                        AND    a.wait_class!='Idle'
                        AND    (&filter)) stat
        GROUP  BY inst,rollup(wait_class,event),sec,
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
                      '<32ms' "<32ms",
                      '<64ms' "<64ms",
                      '<128ms' "<128ms",
                      '<256ms' "<256ms",
                      '<512ms' "<512ms",
                      '<1s' "<1s",
                      '<2s' "<2s",
                      '<4s' "<4s",
                      '<8s' "<8s",
                      '<16s' "<16s",
                      '<32s' "<32s",
                      '<1m' "<1m",
                      '>=1m' ">1m"))
ORDER BY g desc,"Time/s" DESC,DECODE(event,'log file sync',' ',lower(event))