/*[[Show TiDB cluster hardware, versions and loads]]*/
ENV FEED OFF
COL "CPU|Busy,CPU|User,CPU|Sys,MEM|Use,Swap|Use" for pct0
COL "Mem|Total,Mem|Used,Swap|Total,Swap|Used,Disk|MBPS,Disk|Read,Disk|Writ,Net|MBPS,MeM|Total,Disk|Total,Disk|Used,Disk|free" for KMG2
COL "Disk|IOPS,Disk|Reads,Disk|Writs,Net|Pcks,Net|Errs,Net|Drops,Net|PckPS,Net|ErrPS" for TMB2
COL STATUS_ADDRESS,GIT_HASH NOPRINT
COL "CPU|Freq" JUSTIFY RIGHT

PRINT Cluser Info:
PRINT ============
WITH mp AS(
    SELECT *
    FROM   (SELECT instance,
                   type,
                   h.value mp,
                   c.value data_dir,
                   h.device_name,
                   row_number() OVER(PARTITION BY instance, type ORDER BY h.value DESC) r
            FROM   INFORMATION_SCHEMA.CLUSTER_HARDWARE H
            JOIN   INFORMATION_SCHEMA.CLUSTER_CONFIG C
            USING  (instance, type)
            WHERE  h.device_type = 'disk'
            AND    c.key LIKE '%data-dir'
            AND    instr(c.value, h.value) = 1) mp
    WHERE  r = 1)
SELECT *
FROM (
    SELECT Type,Instance,
           SUM(CASE WHEN n='cpu-cpu-physical-cores' THEN value END) `CPU|Cores`,
           SUM(CASE WHEN n='cpu-cpu-logical-cores' THEN value END) `CPU|Threads`,
           MAX(CASE WHEN n='cpu-cpu-frequency' THEN value END) `CPU|Freq`,
           SUM(CASE WHEN n='memory-capacity' THEN value END) `MeM|Total`,
           SUM(CASE WHEN n='disk-total' AND mp IS NOT NULL THEN value END) `Disk|Total`,
           SUM(CASE WHEN n='disk-used'  AND mp IS NOT NULL THEN value END) `Disk|Used`,
           SUM(CASE WHEN n='disk-free'  AND mp IS NOT NULL THEN value END) `Disk|free`,
           IFNULL(MAX(CASE WHEN n='disk-fstype' AND mp IS NOT NULL THEN value END),'') `Disk|FS`,
           IFNULL(MAX(data_dir),'') `Data-Dir`,
           '|' `|`
    FROM   (SELECT *,
                  lower(concat(DEVICE_TYPE,'-',NAME)) n,
                  lower(device_name) dn
           FROM   INFORMATION_SCHEMA.CLUSTER_HARDWARE H
           LEFT   JOIN MP USING (instance,type,device_name)) C
    GROUP BY Type,Instance) A
JOIN INFORMATION_SCHEMA.CLUSTER_INFO B
USING (Type,Instance)
ORDER BY 1,2;

COL MEMORY_TOTAL,MEMORY_LIMIT,MEMORY_CURRENT,MEMORY_MAX_USED FOR KMG2
PRINT Memory Usage:
PRINT =============
select * from information_schema.cluster_memory_usage;

PRINT Cluser Load:
PRINT ============
WITH mp AS(
    SELECT *
    FROM   (SELECT instance,
                   type,
                   h.value mp,
                   c.value data_dir,
                   h.device_name,
                   row_number() OVER(PARTITION BY instance, type ORDER BY h.value DESC) r
            FROM   INFORMATION_SCHEMA.CLUSTER_HARDWARE H
            JOIN   INFORMATION_SCHEMA.CLUSTER_CONFIG C
            USING  (instance, type)
            WHERE  h.device_type = 'disk'
            AND    c.key LIKE '%data-dir'
            AND    instr(c.value, h.value) = 1) mp
    WHERE  r = 1)
SELECT Type,Instance,
       '|' `|`,
       SUM(CASE WHEN n='cpu-load1' THEN value END) `Load|1min`,
       SUM(CASE WHEN n='cpu-load5' THEN value END) `Load|5min`,
       SUM(CASE WHEN n='cpu-load1' THEN value END) `Load|15m`,
       '|' `|`,
       1-SUM(CASE WHEN n='cpu-idle' THEN value END) `CPU|Busy`,
       SUM(CASE WHEN n='cpu-user' THEN value END) `CPU|User`,
       SUM(CASE WHEN n='cpu-system' THEN value END) `CPU|Sys`,
       '|' `|`,
       SUM(CASE WHEN dn='virtual' and n='memory-total' THEN value END) `MeM|Total`,
       SUM(CASE WHEN dn='virtual' and n='memory-used' THEN value END) `MeM|Used`,
       SUM(CASE WHEN dn='virtual' and n='memory-used-percent' THEN value END) `MeM|Use`,
       '|' `|`,
       SUM(CASE WHEN dn='swap' and n='memory-total' THEN value END) `Swap|Total`,
       SUM(CASE WHEN dn='swap' and n='memory-used' THEN value END) `Swap|Used`,
       SUM(CASE WHEN dn='swap' and n='memory-used-percent' THEN value END) `Swap|Use`,
       '|' `|`,
       COUNT(DISTINCT CASE WHEN n in('net-read_count/s','io-read_io/s') THEN dn END) `Disk|Used`,
       SUM(CASE WHEN n in('net-read_count/s','net-write_count/s','io-read_io/s','io-write_io/s') THEN value END) `Disk|IOPS`,
       SUM(CASE WHEN n in('net-read_bytes/s','net-write_bytes/s') THEN value END) `Disk|MBPS`,
       SUM(CASE WHEN n in('net-read_count/s','io-read_io/s')  THEN value END) `Disk|Reads`,
       SUM(CASE WHEN n='net-read_bytes/s'  THEN value END) `Disk|Read`,
       SUM(CASE WHEN n in('net-write_count/s','io-write_io/s') THEN value END) `Disk|Writs`,
       SUM(CASE WHEN n='net-write_bytes/s' THEN value END) `Disk|Writ`,
       '|' `|`,
       SUM(CASE WHEN n in('net-rx-bytes/s','net-tx-bytes/s') THEN value END) `Net|MBPS`,
       SUM(CASE WHEN n in('net-rx-packets/s','net-tx-packets/s') THEN value END) `Net|PckPS`,
       SUM(CASE WHEN n in('net-rx-errors/s','net-tx-errors/s') THEN value END) `Net|ErrPS`,
       SUM(CASE WHEN n in('net-errin','net-errout') THEN value END) `Net|Errs`,
       SUM(CASE WHEN n in('net-dropin','net-dropout') THEN value END) `Net|Drops`
FROM  (SELECT *,
              lower(concat(DEVICE_TYPE,'-',NAME)) n,
              lower(device_name) dn
       FROM   INFORMATION_SCHEMA.CLUSTER_LOAD) C
GROUP BY type,instance
ORDER BY 1,3 desc,2