/*[[Show database IO info]]*/
set feed off
SELECT inst_id,event, total_Waits,round(1e-3*time_Waited_micro/total_Waits,2) avg_milli_secs
from gv$system_event WHERE  event LIKE 'db file%' or  event LIKE 'log file%' or event LIKE '%direct path%';
col value format kmg
select * from gv$sysmetric where METRIC_NAME like 'Physical%Total%';
/*
SELECT round(MAX(a.VALUE) * 1e6 / MAX(time_Waited_micro) / 1024 / 1024, 2) "Read Speed(MB/s)",
       round(MIN(a.VALUE) * 1e6 / MAX(time_Waited_micro), 2) "Read IOPS"
FROM   v$sysstat a,
       (SELECT SUM(time_Waited_micro) time_Waited_micro
        FROM   v$system_event
        WHERE  event LIKE 'db file%read')
WHERE  NAME IN ('physical read total bytes', 'physical read IO requests');*/
