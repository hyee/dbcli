/*[[Show database IO info]]*/
set feed off
SELECT inst_id,event, total_Waits,round(1e-3*time_Waited_micro/total_Waits,2) avg_milli_secs 
from gv$system_event WHERE  event LIKE 'db file%' or  event LIKE 'log file%' or event LIKE '%direct path%';

SELECT a.inst_id,
       round(MAX(a.VALUE) * 1e6 / max(time_Waited_micro) / 1024 / 1024,2) "Write Speed(MB/s)",
       round(MIN(a.VALUE) * 1e6 / max(time_Waited_micro),2) "Write IOPS",
       Round(MAX(a.value)/MIN(a.value)/1024,2) "Write KB/IO",
       Round(MAX(a.value)/(select total_Waits from gv$system_event c where a.inst_id=c.inst_id and c.event='db file parallel write')/1024,2) "Write KB/Batch"        
FROM   gv$sysstat a, gv$system_event b
WHERE  NAME IN('physical write bytes','physical write IO requests')
AND    event = 'db file parallel write'
and    a.inst_id=b.inst_id
group by a.inst_id;
/*
SELECT round(MAX(a.VALUE) * 1e6 / MAX(time_Waited_micro) / 1024 / 1024, 2) "Read Speed(MB/s)",
       round(MIN(a.VALUE) * 1e6 / MAX(time_Waited_micro), 2) "Read IOPS"
FROM   v$sysstat a,
       (SELECT SUM(time_Waited_micro) time_Waited_micro
        FROM   v$system_event
        WHERE  event LIKE 'db file%read')
WHERE  NAME IN ('physical read total bytes', 'physical read IO requests');*/
