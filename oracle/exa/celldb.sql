/*[[list cell IO stats. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={cell,}
    --]]
]]*/
col bytes,f_bytes format kmg
col ios,f_ios,lios,f_lios format tmb
col service,f_service,queues,f_queues format smhd2
set feed off
SELECT &cell src,
       count(distinct cell) cells,
       SUM(DECODE(metric_name, 'Per Db Bytes of IO', metric_value)) bytes,
       SUM(DECODE(metric_name, 'Per Db Bytes of IO for Flash', metric_value)) f_bytes,
       SUM(DECODE(metric_name, 'Per Db Number of IOs', metric_value)) ios,
       SUM(DECODE(metric_name, 'Per Db Number of IOs for Flash', metric_value)) f_ios,
       SUM(DECODE(metric_name, 'Per Db Number of large IOs', metric_value)) lios,
       SUM(DECODE(metric_name, 'Per Db Number of large IOs for Flash', metric_value)) f_lios,
       SUM(DECODE(metric_name, 'Per Db large IO queue time', metric_value * 1e-6)) queues,
       SUM(DECODE(metric_name, 'Per Db large IO queue time for Flash', metric_value * 1e-6)) f_queues,
       SUM(DECODE(metric_name, 'Per Db small IO service time', metric_value * 1e-6)) service,
       SUM(DECODE(metric_name, 'Per Db small IO service time for Flash', metric_value * 1e-6)) f_service
FROM   (SELECT (select extractvalue(xmltype(a.confval),'/cli-output/context/@cell') from v$cell_config a where a.CELLNAME=b.CELL_NAME and rownum<2) cell,
               src_Dbname src, COUNT(1) cells, metric_name, SUM(metric_value) metric_value, metric_type
        FROM   V$CELL_DB b
        GROUP  BY cell_name,src_Dbname, metric_name, metric_type
        ORDER  BY 1, 3)
WHERE lower(cell) like lower('%'||:V1||'%') 
GROUP  BY &cell src
order by 1,2,3;

SELECT cell,
       SUM(DECODE(metric_name, 'Per Db Bytes of IO', metric_value)) bytes,
       SUM(DECODE(metric_name, 'Per Db Bytes of IO for Flash', metric_value)) f_bytes,
       SUM(DECODE(metric_name, 'Per Db Number of IOs', metric_value)) ios,
       SUM(DECODE(metric_name, 'Per Db Number of IOs for Flash', metric_value)) f_ios,
       SUM(DECODE(metric_name, 'Per Db Number of large IOs', metric_value)) lios,
       SUM(DECODE(metric_name, 'Per Db Number of large IOs for Flash', metric_value)) f_lios,
       SUM(DECODE(metric_name, 'Per Db large IO queue time', metric_value * 1e-6)) queues,
       SUM(DECODE(metric_name, 'Per Db large IO queue time for Flash', metric_value * 1e-6)) f_queues,
       SUM(DECODE(metric_name, 'Per Db small IO service time', metric_value * 1e-6)) service,
       SUM(DECODE(metric_name, 'Per Db small IO service time for Flash', metric_value * 1e-6)) f_service
FROM   (SELECT (select extractvalue(xmltype(a.confval),'/cli-output/context/@cell') from v$cell_config a where a.CELLNAME=b.CELL_NAME and rownum<2) cell,
               src_Dbname src, COUNT(1) cells, metric_name, SUM(metric_value) metric_value, metric_type
        FROM   V$CELL_DB b
        GROUP  BY cell_name,src_Dbname, metric_name, metric_type
        ORDER  BY 1, 3)
WHERE lower(cell) like lower('%'||:V1||'%') 
GROUP  BY cell
order by 1,2,3;

SELECT metric_name,
       MAX(end_time) last_time,
       COUNT(DISTINCT cell) cells,
       case when METRIC_TYPE like '%/s%' or metric_name like '% second' then SUM(metric_value) else round(AVG(metric_value), 2) end agg_value,
       MIN(metric_value) min_value,
       median(metric_value) med_value,
       MAX(metric_value) max_value,
       METRIC_TYPE
FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                FROM   v$cell_config c
                WHERE  c.CELLNAME = a.CELL_NAME
                AND    rownum < 2) cell,
               MAX(begin_time) OVER(PARTITION BY CELL_NAME,METRIC_NAME) max_time,
               begin_time,
               end_time,
               METRIC_NAME,
               METRIC_VALUE,
               METRIC_TYPE
        FROM   v$cell_global_history a)
WHERE  max_time = begin_time
AND    lower(cell) like lower('%'||:V1||'%') 
GROUP  BY metric_name, METRIC_TYPE
ORDER  BY 1