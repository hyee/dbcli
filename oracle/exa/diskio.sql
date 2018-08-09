/*[[Show Disk IO stats. Usage: @@NAME [<cell_name>|<disk_name>|<disk_type>]

]]*/
col gid noprint
set feed off sep4k on
Pro S: Small   L: Large   R: Read   W: Write
pro ========================================
SELECT *
FROM   (SELECT /*+use_hash(b a) leading(b) no_expand*/ 
               grouping_id(cell, disk_type) gid,
               nvl(cell, '-ALL-') cell,
               to_char(MAX(end_time),'HH24:MI:SS') timestamp,
               nvl(disk_type, '-ALL-') disk_type,
               disk_name,
               NAME,
               round(CASE
                   WHEN NAME LIKE 'Avg%' THEN
                    AVG(VALUE)
                   ELSE
                    SUM(VALUE)
               END,2) VALUE
        FROM   (SELECT cell_hash,
                       end_time,
                       disk_name,
                       SUBSTR(disk_name, 1, 2) disk_type,
                       metric_name NAME,
                       metric_value VALUE,
                       MAX(end_time) OVER(PARTITION BY cell_name, disk_name) e
                FROM   v$cell_disk_history a
                WHERE  disk_name NOT LIKE '/%') a 
        JOIN   (SELECT cellhash cell_hash, extractvalue(xmltype(c.confval), '/cli-output/context/@cell') cell
               FROM   v$cell_config c
               WHERE  conftype = 'CELL') b
        USING  (cell_hash)
        WHERE  end_time = e
        AND    (:V1 IS NULL OR upper(:V1) in (upper(disk_name),upper(cell),upper(disk_type)))
        GROUP  BY NAME, GROUPING SETS((cell, disk_type, disk_name),(cell),(disk_type),()))
PIVOT(MAX(VALUE)
FOR    NAME IN('Utilization' AS "Util(%)", 'Reads per second' AS "R/s", 'Writes per second' AS "W/s",
               'Read Bytes per second' AS "R MB/s", 'Write Bytes per second' AS "W MB/s",
               'Average Wait Time' AS "Avg Wait us", 'Small reads/s' AS "S R/s",
               'Small writes/s' AS "S W/s", 'Large reads/s' AS "L R/s", 'Large writes/s' AS "L W/s",
               'Small read bytes/s' AS "S R MB/s", 'Small write bytes/s' AS "S W MB/s",
               'Large read bytes/s' AS "L R MB/s", 'Large write bytes/s' AS "L W MB/s",
               'Average Small read latency' AS "Avg S R us", 'Average Small write latency' AS "Avg S W us",
               'Average Large read latency' AS "Avg L R us", 'Average Large write latency' AS "Avg R W us"))
ORDER  BY 1, cell, disk_name;
