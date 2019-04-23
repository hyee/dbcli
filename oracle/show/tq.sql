/*[[Show v$pq_tqstat.]]*/
col bytes format kmg
col waits,num_rows,timeouts for k0
set feed off printsize 1024
select * from v$pq_sesstat;

SELECT t.*, '|' "|",
       round(ratio_to_report(num_rows) over(PARTITION BY dfo_number, tq_id, server_type) * 100,2) AS "Bytes%",
       rpad('#', round(num_rows * 20 / nullif(MAX(num_rows) over(PARTITION BY dfo_number, tq_id, server_type), 0)), '#') AS graph,
       round(bytes / nullif(num_rows, 0)) AS "Bytes/row"
FROM   v$pq_tqstat t
ORDER  BY dfo_number, tq_id, server_type DESC, instance, process;
