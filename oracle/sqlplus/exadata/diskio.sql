Pro S: Small   L: Large   R: Read   W: Write   B: Bytes
pro ====================================================
col "Avg Wait us" heading "Avg Wait|(us)" jus center
col "Avg S R us" heading "Avg S R|(us)" jus center
col "Avg S W us" heading "Avg S W|(us)" jus center
col "Avg L R us" heading "Avg L R|(us)" jus center
col "Avg R W us" heading "Avg R W|(us)" jus center
col gid noprint
set pages 9999

SELECT *
FROM   (SELECT /*+use_hash(b a) leading(b) no_expand*/ 
               grouping_id(cell, disk_type) gid,
               nvl(cell, '-ALL-') cell,
               to_char(MAX(end_time),'HH24:MI:SS') timestamp,
               nvl(disk_type, '-ALL-') disk_type,
               cast(disk_name as varchar2(30)) disk_name,
               NAME,
               cast(round(CASE
                   WHEN NAME LIKE 'Avg%' or name like '%Average%' THEN
                    AVG(VALUE)
                   ELSE
                    SUM(VALUE)
               END) as number(10)) VALUE
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
        GROUP  BY NAME, GROUPING SETS((cell, disk_type, disk_name),(cell),(disk_type),()))
PIVOT(MAX(VALUE)
FOR    NAME IN('Utilization' AS "Util(%)", 'Reads per second' AS "R/s", 'Writes per second' AS "W/s",
               'Read Bytes per second' AS "R B/s", 'Write Bytes per second' AS "W B/s",
               'Average Wait Time' AS "Avg Wait us", 'Small reads/s' AS "S R/s",
               'Small writes/s' AS "S W/s", 'Large reads/s' AS "L R/s", 'Large writes/s' AS "L W/s",
               'Small read bytes/s' AS "S R B/s", 'Small write bytes/s' AS "S W B/s",
               'Large read bytes/s' AS "L R B/s", 'Large write bytes/s' AS "L W B/s",
               'Average Small read latency' AS "Avg S R us", 'Average Small write latency' AS "Avg S W us",
               'Average Large read latency' AS "Avg L R us", 'Average Large write latency' AS "Avg R W us"))
ORDER  BY 1, cell, disk_name;