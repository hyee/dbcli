/*[[Show PGA stats]]*/
set feed off
col PGA_TARGET_FOR_ESTIMATE,BYTES_PROCESSED,ESTD_EXTRA_BYTES_RW for kmg
col ESTD_TIME for smhd2
col PGA_TARGET_FACTOR for pct2
col avg_value,min_value,max_value for k2
pro PGA Advise:
pro ================
select PGA_TARGET_FOR_ESTIMATE,
       PGA_TARGET_FACTOR,
       max(BYTES_PROCESSED) BYTES_PROCESSED,
       max(ESTD_EXTRA_BYTES_RW) ESTD_EXTRA_BYTES_RW,
       max(ESTD_PGA_CACHE_HIT_PERCENTAGE) ESTD_PGA_CACHE_HIT_PERCENTAGE,
       max(ESTD_OVERALLOC_COUNT) ESTD_OVERALLOC_COUNT
from GV$PGA_TARGET_ADVICE
group by PGA_TARGET_FOR_ESTIMATE,PGA_TARGET_FACTOR
order by 1,2;

pro PGA Stats:
pro ================
select name,
       avg(decode(UNIT,'bytes', round(value/1024/1024,2),value)) avg_value,
       decode(UNIT,'bytes','MB',unit) unit,
       '|' "|",
       min(decode(UNIT,'bytes', round(value/1024/1024,2),value)) min_value,
       min(inst_id) keep(dense_rank first order by value) min_inst, 
       '|' "|",
       max(decode(UNIT,'bytes', round(value/1024/1024,2),value)) max_value,
       min(inst_id) keep(dense_rank last order by value) max_inst
from GV$PGASTAT 
group by name,unit
order by UPPER(NAME);


pro PGA Parameters:
pro ================
ora param pga workarea smm area_size


pro PGA_AGGREGATE_LIMIT Calculation:
pro ================================
WITH MAX_PGA AS
 (SELECT round(VALUE / 1024 / 1024, 1) max_pga FROM v$pgastat WHERE NAME = 'maximum PGA allocated'),
MGA_CURR AS
 (SELECT round(VALUE / 1024 / 1024, 1) mga_curr FROM v$pgastat WHERE NAME = 'MGA allocated (under PGA)'),
MAX_UTIL AS
 (SELECT max_utilization AS max_util FROM v$resource_limit WHERE resource_name = 'processes'),
PARMS AS
 (SELECT name,value from v$parameter where name in('processes','pga_aggregate_target'))
SELECT a.max_pga "Max PGA (MB)",
       b.mga_curr "Current MGA (MB)",
       c.max_util "Max # of processes",
       round(((a.max_pga - b.mga_curr) + (c.max_util * 5)) * 1.1, 1) "PGA_AGGREGATE_LIMIT (MB)|Based on current stats",
       ceil((select value from PARMS WHERE name='pga_aggregate_target')*2/1024/1024 
        + 5*(select value from parms WHERE name='processes')) "PGA_AGGREGATE_LIMIT (MB)|Based on parameters"
FROM   MAX_PGA a, MGA_CURR b, MAX_UTIL c
WHERE  1 = 1;