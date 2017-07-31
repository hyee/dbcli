/*[[list cell IO stats
    --[[
        &cell: default={}, d={cell,}
    --]]
]]*/
col bytes format kmg
col f_bytes format kmg
col ios format tmb
col f_ios format tmb
col lios format tmb
col f_lios format tmb
col service format smhd2
col f_service format smhd2
col queues format smhd2
col f_queues format smhd2
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
GROUP  BY &cell src
order by 1,2,3
