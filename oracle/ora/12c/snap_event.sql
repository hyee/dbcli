/*[[
    Show delta event histogram relative to target event. Usage: @@NAME {<0|secs> [0|inst_id]} [-lgwr|-io|-gc|-w"<event|wait_class>"|-f"<filter>"] [-c|-n]
  
    Parameters:
        secs : the interval to sample the stats in order to calc the delta values. When 0 then calc all stats instead of delta stats
        -lgwr: show only the events relative to LGWR
        -io  : show only the events belong to User/System I/O
        -gc  : show only the events belong to Cluster waits
        -w   : show only the events belong to specific event/wait class
        -c   : the percentages of the histogram is based on wait count, instead of wait time
        -n   : the value of the histogram is the number of waits, instead of percentage

    Sample Output:
    ==============
    Sampling stats for 10 seconds, the values of histogram are the percentages of [wait_count*log(2,slot_time*2)]:
    =============================================================================================================
                     EVENT                  Time/s  Waits/s AVG_TIME| <1us  <2us  <4us  <8us <16us <32us <64us <128us <256us <512us  <1ms  <2ms <4ms <8ms <32ms
     ------------------------------------- -------- ------- --------+----- ----- ----- ----- ----- ----- ----- ------ ------ ------ ----- ----- ---- ---- -----
     - Wait Class: All                     228.28ms 1,766.5 422.67us| 0.31  0.67  5.09 29.11 20.30  9.03  5.87   5.44   7.46   7.05  4.87  3.27 0.62 0.18  0.69
     - Wait Class: Other                   213.07ms 1,622.6 242.94us| 0.04  0.43  5.50 31.81 21.72  9.35  4.30   4.94   6.36   5.32  5.03  3.55 0.68 0.20  0.76
     - Wait Class: System I/O                6.78ms   39.20 265.81us| 0.35  5.17  0.64  0.56  3.72  6.59  1.49         36.65  42.86  1.95
     - Wait Class: Concurrency               4.07ms   80.09 500.76us| 6.65  3.17  1.21  3.66  8.21  6.30 43.88  15.93   0.24   5.65  4.13  0.97
     - Wait Class: User I/O                  2.37ms    9.00 370.29us|                   0.52 13.73  4.71  0.92          1.18  73.20  5.75
     - Wait Class: Cluster                   1.78ms   10.10 197.44us|                                     1.57  24.19  59.46  12.32  2.46
     - Wait Class: Network                 200.80us    5.30  39.35us| 0.32  0.65  9.71  1.29  1.62 15.53 47.57  23.30
     - Wait Class: Application               8.60us    0.20  43.00us|            27.27                          72.73
     RMA: IPC0 completion sync              82.41ms    4.20  20.10ms|                   0.64                                                              99.36
     latch free                             48.44ms   40.70   1.39ms|                                                          1.05 33.11 60.63 5.20
     enq: IV -  contention                  26.46ms   39.90 663.24us|                               0.15        10.10  35.89  13.88 23.32  4.54 7.87 4.24
     enq: PS - contention                   15.67ms   41.30 392.60us|                   0.10        0.15  0.17   1.37  25.46  50.23 22.53
     PX Deq: Join ACK                        9.15ms   59.40 156.16us|       0.87  2.66  0.87  0.22  1.30 19.39  20.94  31.54  15.79  6.43
     PX Deq: reap credit                     8.86ms 1,054.0   8.41us|       0.28  7.53 42.10 33.67 13.85  2.44   0.12
     PX Deq: Slave Session Stats             5.44ms   42.40 128.23us| 0.27  4.36  3.48  3.27  1.87  1.84  6.20  16.91  41.10  18.05  2.62
     oracle thread bootstrap                 4.22ms    0.20  21.11ms|                                                                                       100
     ...
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
                        'log switch/archive',
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
               max(SUM(total_waits * r)/sec) over(partition by inst,wait_class,event) "Waits/s",
               max(ROUND(SUM(micro * r) / NULLIF(SUM(total_waits * r), 0), 2)) over(partition by inst,wait_class,event) avg_time,
               '|' "|",
               nullif(round(&calc, 2), 0) pct
        FROM   (SELECT /*+no_merge*/ 
                       greatest(&V1,1) sec,
                       DECODE(ROWNUM, 1, decode(&v1,0,1,-1), decode(&v1,0,0,1)) r, 
                       SYSDATE + numtodsinterval(&v1, 'second') mr 
                FROM XMLTABLE('1 to 2')) dummy,
               LATERAL (SELECT /*+no_merge*/ do_sleep(dummy.r, dummy.mr) stime FROM dual where dummy.r!=0) timer,
               LATERAL (SELECT * FROM TABLE(GV$(CURSOR(
                            SELECT /*+ordered use_hash(a b)*/
                                    decode(lower(nvl('&v2','a')),'a',0,userenv('instance'))  inst,
                                    event, 
                                    a.total_waits,
                                    a.time_waited_micro micro,
                                    b.wait_time_micro slot_time,
                                    b.wait_count svalue,
                                    a.wait_class
                            FROM   v$system_event a
                            JOIN   v$event_histogram_micro b
                            USING  (event)
                            WHERE  timer.stime IS NOT NULL
                            AND    userenv('instance')=nvl(:instance+0,userenv('instance'))
                            AND    lower(nvl('&v2','a')) in('a','0',to_char(userenv('instance')))
                            AND    a.wait_class!='Idle'
                            AND    (&filter))))) stat
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