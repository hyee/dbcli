/*[[Show v$pq_tqstat.]]*/
col bytes format kmg
col open_time,latency for smhd0
col waits,num_rows,timeouts for k0
set feed off printsize 1024
select * from v$pq_sesstat;

SELECT DFO_NUMBER DFO#, TQ_ID TQ#,SERVER_TYPE, NUM_ROWS "#ROWS", BYTES, 
       OPEN_TIME, 
       AVG_LATENCY*50 LATENCY, 
       WAITS,
       TIMEOUTS,
       PROCESS,
       INSTANCE, 
       '|' "|",
       round(ratio_to_report(num_rows) over(PARTITION BY dfo_number, tq_id, server_type) * 100,2) AS "Bytes%",
       rpad('#', round(num_rows * 20 / nullif(MAX(num_rows) over(PARTITION BY dfo_number, tq_id, server_type), 0)), '#') AS graph,
       round(bytes / nullif(num_rows, 0)) AS "Bytes/row"
FROM   v$pq_tqstat t
ORDER  BY 1, 2, server_type DESC, instance, process;
