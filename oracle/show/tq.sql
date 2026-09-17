/*[[Show parallel query statistics (v$pq_sesstat and v$pq_tqstat).]]*/
col bytes format kmg
col open_time,latency for smhd0
col waits,num_rows,timeouts for k0
set feed off printsize 1024
SELECT * FROM v$pq_sesstat;

SELECT dfo_number dfo#, tq_id tq#, server_type, num_rows "#ROWS", bytes,
       open_time,
       avg_latency*50 latency,
       waits,
       timeouts,
       process,
       instance,
       '|' "|",
       round(ratio_to_report(num_rows) over(PARTITION BY dfo_number, tq_id, server_type) * 100,2) AS "Bytes%",
       rpad('#', round(num_rows * 20 / nullif(max(num_rows) over(PARTITION BY dfo_number, tq_id, server_type), 0)), '#') AS graph,
       round(bytes / nullif(num_rows, 0)) AS "Bytes/row"
FROM   v$pq_tqstat t
ORDER  BY 1, 2, server_type DESC, instance, process;
