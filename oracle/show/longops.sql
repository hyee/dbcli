/*[[Show the unfinished long operations in gv$session_longops.]]*/
set feed off
SELECT inst_id,
       sid,
       sql_id,
       opname,
       nvl(target,target_desc) target,
       round(elapsed_seconds / 60, 2) "Costed(Min)",
       round((time_remaining) / 60,2) "Remain(Min)",
       to_char(100*sofar/totalwork,'fm990.99')||'%' progress,
       message
FROM   gv$session_longops
WHERE  sofar < totalwork;