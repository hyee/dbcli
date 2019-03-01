/*[[list cell IO stats. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={cell,}
    --]]
]]*/
col bytes,f_bytes format kmg
col ios,f_ios,lios,f_lios format tmb
col service,f_service,queues,f_queues,Avg|Time,Avg|Queue,Avg|Service format usmhd2
set feed off
SELECT db,
       regexp_replace(listagg(dbid, ',') within GROUP(ORDER BY dbid), '([^,]+)(,\1)+', '\1') dbid,
       regexp_replace(listagg(root, ',') within GROUP(ORDER BY root), '([^,]+)(,\1)+', '\1') root_id,
       regexp_replace(listagg(ocl_group_id, ',') within GROUP(ORDER BY ocl_group_id), '([^,]+)(,\1)+', '\1') ocl_group_id,
       regexp_replace(listagg(oflgrp_name, ',') within GROUP(ORDER BY oflgrp_name), '([^,]+)(,\1)+', '\1') oflgrp_name,
       regexp_replace(listagg(PACKAGE, ',') within GROUP(ORDER BY PACKAGE), '([^,]+)(,\1)+', '\1') PACKAGE,
       regexp_replace(listagg(oflgrp_disabled, ',') within GROUP(ORDER BY oflgrp_disabled), '([^,]+)(,\1)+', '\1') oflgrp_disabled
FROM   (
    SELECT /*+ordered use_hash(a b c) no_merge(a) no_merge(b) no_merge(c)*/
            DISTINCT db,dbid, root, ocl_group_id, nvl(a.ofl_name, oflgrp_name) oflgrp_name, PACKAGE, oflgrp_disabled
    FROM   (SELECT DISTINCT cell_name, b.*, decode(instr(grp_name, ' '), 0, grp_name) ofl_name
            FROM   v$cell_state a,
                    xmltable('//stats[@type="databasedes"]' passing xmltype(a.statistics_value) columns --
                            db VARCHAR2(128) path 'stat[@name="db name"]',
                            dbid INT path 'stat[@name="db id"]',
                            root INT path 'stat[@name="root id"]',
                            grp_name VARCHAR2(50) path 'stat[@name="offload_group_name"]', --
                            ocl_group_id INT path 'stat[@name="ocl_group_id"]',
                            oflgrp_name_len INT path 'stat[@name="offload_group_name_len"]',
                            oflgrp_disabled INT path 'stat[@name="group_oflgrp_open_disabled"]') b
            WHERE  statistics_type = 'DBDES') a --
    LEFT JOIN (SELECT DISTINCT cell_name, b.*
                FROM   v$cell_state a,
                       xmltable('//stats[@type="offloadgroupdes"]' passing xmltype(a.statistics_value) columns --
                                oflgrp_name VARCHAR2(50) path 'stat[@name="offload_group"]', --
                                ocl_group_id VARCHAR2(50) path 'stat[@name="ocl_group_id"]') b
                WHERE  statistics_type = 'OFLGRPDES') b --
    USING  (cell_name, ocl_group_id) --
    LEFT JOIN (SELECT DISTINCT cellname cell_name, b.*
                FROM   v$cell_config_info a,
                       XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                                oflgrp_name VARCHAR2(300) path 'name',
                                PACKAGE VARCHAR2(300) path 'package') b
                WHERE  conftype = 'OFFLOAD') c --
    USING  (cell_name, oflgrp_name))
GROUP  BY db
ORDER BY upper(db);

SELECT a.*,
       round((queues+f_queues+service+f_service)/nullif(ios+f_ios,0),2) "Avg|Time",
       round((queues+f_queues)/nullif(ios+f_ios,0),2) "Avg|Queue",
       round((service+f_service)/nullif(ios+f_ios,0),2) "Avg|Service"
FROM (
        SELECT &cell src,
        count(distinct cell) cells,
        SUM(DECODE(metric_name, 'Per Db Bytes of IO', metric_value)) bytes,
        SUM(DECODE(metric_name, 'Per Db Bytes of IO for Flash', metric_value)) f_bytes,
        SUM(DECODE(metric_name, 'Per Db Number of IOs', metric_value)) ios,
        SUM(DECODE(metric_name, 'Per Db Number of IOs for Flash', metric_value)) f_ios,
        SUM(DECODE(metric_name, 'Per Db Number of large IOs', metric_value)) lios,
        SUM(DECODE(metric_name, 'Per Db Number of large IOs for Flash', metric_value)) f_lios,
        SUM(DECODE(metric_name, 'Per Db large IO queue time', metric_value)) queues,
        SUM(DECODE(metric_name, 'Per Db large IO queue time for Flash', metric_value)) f_queues,
        SUM(DECODE(metric_name, 'Per Db small IO service time', metric_value)) service,
        SUM(DECODE(metric_name, 'Per Db small IO service time for Flash', metric_value)) f_service
        FROM   (SELECT (select extractvalue(xmltype(a.confval),'/cli-output/context/@cell') from v$cell_config a where a.CELLNAME=b.CELL_NAME and rownum<2) cell,
                src_Dbname src, COUNT(1) cells, metric_name, SUM(metric_value) metric_value, metric_type
                FROM   V$CELL_DB b
                GROUP  BY cell_name,src_Dbname, metric_name, metric_type
                ORDER  BY 1, 3)
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP  BY &cell src) A
order by 1,2,3;

SELECT a.*,
       round((queues+f_queues+service+f_service)/nullif(ios+f_ios,0),2) "Avg|Time",
       round((queues+f_queues)/nullif(ios+f_ios,0),2) "Avg|Queue",
       round((service+f_service)/nullif(ios+f_ios,0),2) "Avg|Service"
FROM (
    SELECT cell,
        COUNT(DISTINCT src) dbs,
        SUM(DECODE(metric_name, 'Per Db Bytes of IO', metric_value)) bytes,
        SUM(DECODE(metric_name, 'Per Db Bytes of IO for Flash', metric_value)) f_bytes,
        SUM(DECODE(metric_name, 'Per Db Number of IOs', metric_value)) ios,
        SUM(DECODE(metric_name, 'Per Db Number of IOs for Flash', metric_value)) f_ios,
        SUM(DECODE(metric_name, 'Per Db Number of large IOs', metric_value)) lios,
        SUM(DECODE(metric_name, 'Per Db Number of large IOs for Flash', metric_value)) f_lios,
        SUM(DECODE(metric_name, 'Per Db large IO queue time', metric_value)) queues,
        SUM(DECODE(metric_name, 'Per Db large IO queue time for Flash', metric_value)) f_queues,
        SUM(DECODE(metric_name, 'Per Db small IO service time', metric_value)) service,
        SUM(DECODE(metric_name, 'Per Db small IO service time for Flash', metric_value)) f_service
    FROM   (SELECT (select extractvalue(xmltype(a.confval),'/cli-output/context/@cell') from v$cell_config a where a.CELLNAME=b.CELL_NAME and rownum<2) cell,
                src_Dbname src, COUNT(1) cells, metric_name, SUM(metric_value) metric_value, metric_type
            FROM   V$CELL_DB b
            GROUP  BY cell_name,src_Dbname, metric_name, metric_type
            ORDER  BY 1, 3)
    WHERE lower(cell) like lower('%'||:V1||'%') 
    GROUP  BY cell) A
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
ORDER  BY 1;


