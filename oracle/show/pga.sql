/*[[Show PGA stats]]*/
set feed off
col PGA_TARGET_FOR_ESTIMATE,BYTES_PROCESSED,ESTD_EXTRA_BYTES_RW for kmg
col ESTD_TIME for smhd2
col PGA_TARGET_FACTOR for pct2
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