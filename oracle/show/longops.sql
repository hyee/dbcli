/*[[Show information in gv$session_longops]]*/
SELECT inst_id,
       SID,
       sql_id,
       opname,
       target,
       Round(ELAPSED_SECONDS / 60, 2) "Costed(Min)",
       round((TIME_REMAINING) / 60,2) "Remain(Min)",
       to_char(100*sofar/totalwork,'fm990.99')||'%' progress,
       message
FROM   gv$session_longops
WHERE  sofar < totalwork
