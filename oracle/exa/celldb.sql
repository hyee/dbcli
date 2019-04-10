/*[[list cell IO stats. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={cell,}
        @dist: 19={distinct} default={}
        @trunc:  12.2={on overflow truncate} default={}
    --]]
]]*/
col bytes,f_bytes format kmg
col ios,f_ios,lios,f_lios format tmb
col service,f_service,queues,f_queues,Avg|Time,Avg|Queue,Avg|Service format usmhd2
COL CELLSRV|INPUT,CELLSRV|OUTPUT,CELLSRV|PASSTHRU,OFFLOAD|INPUT,OFFLOAD|OUTPUT,OFFLOAD|PASSTHRU,CPU|PASSTHRU,STORAGE_IDX|SAVED format kmg

set feed off sep4k on

WITH b AS
 (SELECT /*+materialize*/DISTINCT cell_name, b.*
  FROM   v$cell_state a,
         xmltable('//stats[@type="offloadgroupdes"]' passing xmltype(a.statistics_value) columns --
                  oflgrp_name VARCHAR2(50) path 'stat[@name="offload_group"]', --
                  ocl_group_id VARCHAR2(50) path 'stat[@name="ocl_group_id"]') b
  WHERE  statistics_type = 'OFLGRPDES'),
c AS
 (SELECT /*+materialize*/DISTINCT cellname cell_name, b.*
  FROM   v$cell_config_info a,
         XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                  oflgrp_name VARCHAR2(300) path 'name',
                  PACKAGE VARCHAR2(300) path 'package') b
  WHERE  conftype = 'OFFLOAD'),
d AS
 (SELECT /*+materialize*/
         db,
         SUM(cellsrv_input) cellsrv_input,
         SUM(cellsrv_output) cellsrv_output,
         SUM(cellsrv_passthru) cellsrv_passthru,
         SUM(ofl_input) ofl_input,
         SUM(ofl_output) ofl_output,
         SUM(ofl_passthru) ofl_passthru,
         SUM(cpu_passthru) cpu_passthru,
         SUM(storage_idx_saved) storage_idx_saved
  FROM   v$cell_state a,
         xmltable('/stats' passing xmltype(a.statistics_value) columns --
                  db VARCHAR2(50) path 'stat[@name="client_name"]',
                  cellsrv_input NUMBER path '//stat[@name="cellsrv_total_input_bytes"]', --
                  cellsrv_output NUMBER path '//stat[@name="cellsrv_total_output_bytes"]', --
                  cellsrv_passthru NUMBER path '//stat[@name="cellsrv_passthru_output_bytes"]', --
                  ofl_input NUMBER path '//stat[@name="celloflsrv_total_input_bytes"]', --
                  ofl_output NUMBER path '//stat[@name="celloflsrv_total_output_bytes"]', --
                  ofl_passthru NUMBER path '//stat[@name="celloflsrv_passthru_output_bytes"]', --
                  cpu_passthru NUMBER path '//stat[@name="cpu_passthru_output_bytes"]', --
                  storage_idx_saved NUMBER path '//stat[@name="storage_idx_saved_bytes"]') b
  WHERE  statistics_type = 'CLIENTDES'
  GROUP  BY db)
SELECT db,
       MAX(ofl_input) "OFFLOAD|INPUT",
       MAX(ofl_output) "OFFLOAD|OUTPUT",
       MAX(ofl_passthru) "OFFLOAD|PASSTHRU",
       MAX(cpu_passthru) "CPU|PASSTHRU",
       MAX(storage_idx_saved) "STORAGE_IDX|SAVED",
       MAX(cellsrv_input) "CELLSRV|INPUT",
       MAX(cellsrv_output) "CELLSRV|OUTPUT",
       MAX(cellsrv_passthru) "CELLSRV|PASSTHRU" ,
       regexp_replace(listagg(&dist PACKAGE, ',' &trunc) within GROUP(ORDER BY PACKAGE), '([^,]+)(,\1)+', '\1') PACKAGE,
       MAX(cells) cells,
       --regexp_replace(listagg(&dist dbid, ',' &trunc) within GROUP(ORDER BY 0+dbid), '([^,]{5,})(,\1)+', '\1') dbid,
       regexp_replace(listagg(&dist root, ',' &trunc) within GROUP(ORDER BY root), '([^,]+)(,\1)+', '\1') root_id,
       regexp_replace(listagg(&dist ocl_group_id, ',' &trunc) within GROUP(ORDER BY ocl_group_id), '([^,]+)(,\1)+', '\1') ocl_group_id,
       regexp_replace(listagg(&dist oflgrp_name, ',' &trunc) within GROUP(ORDER BY oflgrp_name), '([^,]+)(,\1)+', '\1') oflgrp_name,
       regexp_replace(listagg(&dist oflgrp_disabled, ',' &trunc) within GROUP(ORDER BY oflgrp_disabled), '([^,]+)(,\1)+', '\1') oflgrp_disabled
FROM   (SELECT /*+ordered use_hash(a b c d) no_merge*/
        DISTINCT db,
                 COUNT(DISTINCT nvl2(PACKAGE, cell_name, NULL)) over(PARTITION BY db) cells,
                 dbid,
                 root,
                 ocl_group_id,
                 nvl(a.ofl_name, oflgrp_name) oflgrp_name,
                 PACKAGE,
                 oflgrp_disabled,
                 cellsrv_input,
                 cellsrv_output,
                 cellsrv_passthru,
                 ofl_input,
                 ofl_output,
                 ofl_passthru,
                 cpu_passthru,
                 storage_idx_saved
        FROM   (SELECT DISTINCT cell_name, b.*, decode(instr(grp_name, ' '), 0, grp_name) ofl_name
                FROM   v$cell_state a,
                       xmltable('//stats[@type="databasedes"]' passing xmltype(a.statistics_value) columns --
                                db VARCHAR2(128) path 'stat[@name="db name"]',
                                dbid INT path 'stat[@name="db id"][1]',
                                root INT path 'stat[@name="root id"]',
                                grp_name VARCHAR2(50) path 'stat[@name="offload_group_name"]', --
                                ocl_group_id INT path 'stat[@name="ocl_group_id"]',
                                oflgrp_name_len INT path 'stat[@name="offload_group_name_len"]',
                                oflgrp_disabled INT path 'stat[@name="group_oflgrp_open_disabled"]') b
                WHERE  statistics_type = 'DBDES') a --
        LEFT   JOIN b USING  (cell_name, ocl_group_id) --
        LEFT   JOIN c USING  (cell_name, oflgrp_name)
        LEFT   JOIN d USING  (db))
GROUP  BY db
ORDER  BY upper(db);


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

SELECT  min(begin_time) begin_time,
        max(END_TIME) END_TIME,
        METRIC_NAME,
        round(CASE
                    WHEN TRIM(METRIC_TYPE) IN ('%', 'us') THEN
                    AVG(NULLIF(METRIC_VALUE, 0))
                    ELSE
                    SUM(METRIC_VALUE/div/c)
                END,
                2) VALUE,
        regexp_replace(METRIC_TYPE, 'bytes?', 'MB') unit,
        count(distinct cell_hash) cells,
        round(median(METRIC_VALUE/div),2) CELL_MED,
        round(min(METRIC_VALUE/div),2) CELL_MIN,
        round(max(METRIC_VALUE/div),2) CELL_MAX,
        count(1) snaps
FROM   (select a.*,
                case when METRIC_TYPE LIKE '%byte%' then 1024*1024 else 1 end div,
                count(distinct begin_time) over(partition by cell_hash,metric_name) c
        from v$cell_global_history a
        where METRIC_VALUE>0
        and   END_TIME >= SYSDATE - 1/24)
GROUP  BY metric_name, metric_type
ORDER  BY metric_type, VALUE DESC;