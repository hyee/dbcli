/* [[ standby status    Usage: standby_status
    --[[
    @CHECKVERSION: 11.1 = {1}
    ]]--
]]*/

SELECT y.thread thread,
y.aseq "Last Applied Sequence",
to_char(y.ft,'DD-MON-YYYY HH24:MI:SS') "Applied Sequence Time", 
(n.aseq -1) "Last Received Sequence",
to_char(n.ft,'DD-MON-YYYY HH24:MI:SS') "Current Sequence Time", 
((n.aseq -1)-y.aseq) "# of files to be applied",
round((n.ft-y.ft)*24*60) "Lag in Minutes"
FROM
(SELECT thread# thread,
        max(sequence#) aseq,
        applied ,
        max(next_time) ft
 FROM v$archived_log
 WHERE applied IN ('YES')
 GROUP BY applied,
          thread#)y,
(SELECT thread# thread,
        max(sequence#) aseq,
        max(FIRST_TIME) ft
 FROM v$log
 GROUP BY thread#)n
WHERE y.thread=n.thread 
order by thread
/