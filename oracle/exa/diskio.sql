/*[[Show Disk IO stats. Usage: @@NAME [<cell_name>|<disk_name>|<disk_type>]

]]*/
col gid noprint
col "S R B/s,S W B/s,L R B/s,L W B/s,R B/s,W B/s,MBPS" for kmg
col "Avg Wait,Avg S R,Avg S W,Avg L R,Avg L W,Avg R W" for usmhd1
set feed off sep4k on
Pro S: Small   L: Large   R: Read   W: Write   B: Bytes
pro ====================================================
SELECT decode(gid,0,'  ','')||CELL CELL_NAME,cnt,TIMESTAMP,DISK_TYPE,DISK_NAME,'|' "|",
       "Util(%)",
       ("S R/s"+"L R/s"+"S W/s"+"L W/s") IOPS,
       ("S R B/s"+"L R B/s"+"S W B/s"+"L W B/s") MBPS,
       "Avg Wait", '|' "|",
       "Avg S R","Avg S W","Avg L R","Avg R W",'|' "|",
       "R/s","W/s","S R/s","S W/s","L R/s","L W/s",'|' "|",
       ("S R B/s"+"L R B/s") "R B/s",("S W B/s"+"L W B/s") "W B/s","S R B/s","S W B/s","L R B/s","L W B/s"
FROM   (SELECT /*+use_hash(b a) leading(b) no_expand*/ 
               grouping_id(cell, disk_type) gid,
               nvl(cell, '-ALL-') cell,
               count(1) cnt,
               to_char(MAX(end_time),'HH24:MI:SS') timestamp,
               nvl(disk_type, '-ALL-') disk_type,
               cast(disk_name as varchar2(30)) disk_name,
               NAME,
               round(CASE
                   WHEN NAME LIKE 'Avg%' or name like '%Average%' or name like 'Util%' THEN
                    AVG(VALUE)
                   ELSE
                    SUM(VALUE)
               END,1) VALUE
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
               --'Read Bytes per second' AS "R B/s", 'Write Bytes per second' AS "W B/s",
               'Average Wait Time' AS "Avg Wait", 'Small reads/s' AS "S R/s",
               'Small writes/s' AS "S W/s", 'Large reads/s' AS "L R/s", 'Large writes/s' AS "L W/s",
               'Small read bytes/s' AS "S R B/s", 'Small write bytes/s' AS "S W B/s",
               'Large read bytes/s' AS "L R B/s", 'Large write bytes/s' AS "L W B/s",
               'Average Small read latency' AS "Avg S R", 'Average Small write latency' AS "Avg S W",
               'Average Large read latency' AS "Avg L R", 'Average Large write latency' AS "Avg R W"))
ORDER  BY cell, disk_type,disk_name;
