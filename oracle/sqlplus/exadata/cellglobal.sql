col metric_name for a40
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
GROUP  BY metric_name, METRIC_TYPE
ORDER  BY 1;