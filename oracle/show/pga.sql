/*[[Show PGA stats]]*/
set feed off
col PGA_TARGET_FOR_ESTIMATE,BYTES_PROCESSED,ESTD_EXTRA_BYTES_RW for kmg
col ESTD_TIME for smhd2
col PGA_TARGET_FACTOR for pct2
col avg_value,min_value,max_value for k2
pro PGA Advice:
pro ===========
SELECT pga_target_for_estimate,
       pga_target_factor,
       max(bytes_processed) bytes_processed,
       max(estd_extra_bytes_rw) estd_extra_bytes_rw,
       max(estd_pga_cache_hit_percentage) estd_pga_cache_hit_percentage,
       max(estd_overalloc_count) estd_overalloc_count
FROM   gv$pga_target_advice
GROUP  BY pga_target_for_estimate,pga_target_factor
ORDER  BY 1,2;

pro PGA Stats:
pro ==========
SELECT name,
       avg(decode(unit,'bytes', round(value/1024/1024,2),value)) avg_value,
       decode(unit,'bytes','MB',unit) unit,
       '|' "|",
       min(decode(unit,'bytes', round(value/1024/1024,2),value)) min_value,
       min(inst_id) KEEP(dense_rank FIRST ORDER BY value) min_inst,
       '|' "|",
       max(decode(unit,'bytes', round(value/1024/1024,2),value)) max_value,
       min(inst_id) KEEP(dense_rank LAST ORDER BY value) max_inst
FROM   gv$pgastat
GROUP  BY name,unit
ORDER  BY upper(name);


pro PGA Parameters:
pro ===============
ora param pga workarea smm area_size


pro PGA_AGGREGATE_LIMIT Calculation:
pro ================================
WITH max_pga AS
 (SELECT round(value / 1024 / 1024, 1) max_pga FROM v$pgastat WHERE name = 'maximum PGA allocated'),
mga_curr AS
 (SELECT round(value / 1024 / 1024, 1) mga_curr FROM v$pgastat WHERE name = 'MGA allocated (under PGA)'),
max_util AS
 (SELECT max_utilization AS max_util FROM v$resource_limit WHERE resource_name = 'processes'),
parms AS
 (SELECT name,value FROM v$parameter WHERE name IN('processes','pga_aggregate_target'))
SELECT a.max_pga "Max PGA (MB)",
       b.mga_curr "Current MGA (MB)",
       c.max_util "Max # of processes",
       round(((a.max_pga - b.mga_curr) + (c.max_util * 5)) * 1.1, 1) "PGA_AGGREGATE_LIMIT (MB)|stats",
       greatest(2 * 1024,
                nvl((SELECT value FROM parms WHERE name = 'pga_aggregate_target') / 1024 / 1024, 0) * 2,
                nvl((SELECT value FROM parms WHERE name = 'processes'), 0) * 3) "PGA_AGGREGATE_LIMIT (MB)|parms"
FROM   max_pga a
LEFT   JOIN mga_curr b ON 1 = 1
LEFT   JOIN max_util c ON 1 = 1;