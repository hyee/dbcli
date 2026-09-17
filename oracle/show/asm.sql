/*[[
   Show ASM disk groups, disks, attributes and operations.
   Sample Output:
   ==============
    GROUP_NUMBER NAME    SECTOR_SIZE LOGICAL_SECTOR_SIZE BLOCK_SIZE ALLOCATION_UNIT_SIZE STATE     TYPE
    ------------ ------- ----------- ------------------- ---------- -------------------- --------- ------
               1 DATAC2          512                 512       4096              4194304 CONNECTED NORMAL
               2 DBFS_C2         512                 512       4096              4194304 MOUNTED   HIGH
               3 RECOC2          512                 512       4096              4194304 MOUNTED   HIGH
               4 FLASH           512                 512       4096              4194304 MOUNTED   NORMAL


    GROUP_NUMBER NAME    ONLINES OFFLINES NORMALS ABNORMALS ERRORS    READS BYTES_READ AVG_R_TIME  WRITES
    ------------ ------- ------- -------- ------- --------- ------ -------- ---------- ---------- -------
               1 DATAC2       82        0      82         0     22 982.22 M   41.53 TB      130us 48.01 M
               2 DBFS_C2      69        0      69         0      0  29.35 M  114.97 GB        1ms  6.97 K
               3 RECOC2       82        0      82         0     13   9.07 M   57.25 GB        1ms 12.54 M
               4 FLASH       112        0     112         0      0  26.29 M  119.83 GB      135us 85.30 K


    NAME                       READ_ONLY DISKGROUP#1   DISKGROUP#2   DISKGROUP#3   DISKGROUP#4
    -------------------------- --------- ------------- ------------- ------------- -------------
    access_control.enabled     N         FALSE         FALSE         FALSE         FALSE
    access_control.umask       N         066           066           066           066
    appliance._partnering_type Y         EXADATA FIXED EXADATA FIXED EXADATA FIXED EXADATA FIXED
    appliance.mode             N         TRUE          TRUE          TRUE          TRUE
    ate_conversion_done        Y         true          true          true
    au_size                    Y         4194304       4194304       4194304       4194304
    cell.smart_scan_capable    N         TRUE          TRUE          TRUE          TRUE
    cell.sparse_dg             N         allnonsparse  allnonsparse  allnonsparse  allnonsparse
    compatible.advm            N         18.0.0.0.0    18.0.0.0      18.0.0.0.0    12.1.0.2.0
    compatible.asm             N         18.0.0.0.0    18.0.0.0.0    18.0.0.0.0    12.1.0.2.0
    compatible.rdbms           N         11.2.0.4.0    11.2.0.4      11.2.0.4.0    12.1.0.2.0
    content.check              N         FALSE         FALSE         FALSE         FALSE
    content.type               N         data          system        recovery      data
    content_hardcheck.enabled  N         FALSE         FALSE         FALSE
    disk_repair_time           N         12.0h         12.0h         12.0h         12.0h
    failgroup_repair_time      N         24.0h         24.0h         24.0h         24.0h
    idp.boundary               N         auto          auto          auto          auto
    idp.type                   N         dynamic       dynamic       dynamic       dynamic
    logical_sector_size        N         512           512           512           512
    phys_meta_replicated       Y         true          true          true          true
    preferred_read.enabled     N         FALSE         FALSE         FALSE
    scrub_async_limit          N         1             1             1
    scrub_metadata.enabled     N         TRUE          TRUE          TRUE
    sector_size                N         512           512           512           512
    thin_provisioned           N         FALSE         FALSE         FALSE         FALSE
    vam_migration_done         Y         true          true          true

   --[[
       @fg: 11={,listagg(failgroup,',') within group(order by failgroup) failgroup}
       @OP: 12={PASS} DEFAULT={OPERATION}
       @LS: 12.1={logical_sector_size "LOGCAL|SECTOR",} default={}
   ]]--
]]*/
set feed off verify on
col reads,writes for tmb
col BYTES_READ,BYTES_WRITTEN,TOTAL|SIZE,free|SIZE,hot|used,cold|used,mirror|free,usable|file for kmg
col AVG_R_TIME,AVG_W_TIME,AVG_TIME for usmhd0
col PROG(%) for pct

PRO V$ASM_DISKGROUP:
PRO ================
SELECT group_number group#,
       name,
       type,
       state,
       voting_files voting,
       sector_size "SECTOR|SIZE",
       &LS
       block_size "BLOCK|SIZE",
       allocation_unit_size "AU|SIZE",
       total_mb*1024*1024 "TOTAL|SIZE",
       hot_used_mb*1024*1024 "HOT|USED",
       cold_used_mb*1024*1024 "COLD|USED",
       free_mb*1024*1024 "FREE|SIZE",
       required_mirror_free_mb*1024*1024 "MIRROR|FREE",
       usable_file_mb*1024*1024 "USABLE|FILE",
       offline_disks "OFFLINE|DISKS",
       compatibility compatibil,
       database_compatibility db_compatibil
FROM   v$asm_diskgroup ORDER BY 1;

PRO V$ASM_DISK:
PRO ===========
SELECT /*+no_merge(a) no_merge(b) use_hash(a b)*/
       group_number group#,
       name,
       sum(onlines) onlines,
       sum(offlines) offlines,
       sum(normals) normals,
       sum(abnormals) abnormals,
       sum(errors) errors,
       sum(reads) reads,
       sum(bytes_read) bytes_read,
       round(1e4 * sum(read_time) / nullif(sum(reads), 0)) avg_r_time,
       sum(writes) writes,
       sum(bytes_written) bytes_written,
       round(1e4 * sum(write_time) / nullif(sum(writes), 0)) avg_w_time,
       round(1e4 * sum(read_write_time) / nullif(sum(writes + reads), 0)) avg_time &fg
FROM   (SELECT group_number, name FROM v$asm_diskgroup) a
NATURAL RIGHT JOIN   (SELECT group_number,
                             failgroup,
                             count(decode(mode_status, 'ONLINE', 1)) onlines,
                             count(decode(mode_status, 'OFFLINE', 1)) offlines,
                             count(decode(state, 'NORMAL', 1)) normals,
                             sum(decode(state, 'NORMAL', 0, 1)) abnormals,
                             sum(read_errs + write_errs) errors,
                             sum(reads) reads,
                             sum(bytes_read) bytes_read,
                             sum(read_time) read_time,
                             sum(writes) writes,
                             sum(bytes_written) bytes_written,
                             sum(write_time) write_time,
                             sum(read_time + write_time) read_write_time
                      FROM   v$asm_disk
                      GROUP  BY group_number, failgroup) b
GROUP  BY group_number, name
ORDER  BY 1;

var x refcursor "V$ASM_ATTRIBUTE";
DECLARE
    c SYS_REFCURSOR;
    grps VARCHAR2(4000);
BEGIN
    SELECT listagg(''''||name||''' AS "'||name||'"',',') WITHIN GROUP(ORDER BY group_number) INTO grps FROM v$asm_diskgroup;
    OPEN c FOR '
        SELECT *
        FROM   (SELECT /*+outline_leaf*/ a.NAME, a.READ_ONLY,a.VALUE, b.name grp
               FROM   V$ASM_ATTRIBUTE a JOIN v$asm_diskgroup b USING(GROUP_NUMBER)
               WHERE  a.NAME NOT LIKE ''template%'')
        PIVOT (MAX(VALUE) FOR grp IN('||grps||'))
        ORDER  BY name';
    :x := c;
END;
/

PRO V$ASM_OPERATION:
PRO ================
SELECT /*+outline_leaf*/
        a.inst_id inst,
        b.name,
        a.&OP,
        a.state,
        a.power,
        a.actual,
        a.sofar,
        a.est_work,
        a.sofar/nullif(a.est_work,0) "PROG(%)",
        a.est_minutes,
        a.error_code
FROM   gv$asm_operation a
JOIN   v$asm_diskgroup b USING(group_number)
ORDER  BY 2,1;