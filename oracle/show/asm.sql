/*[[
   Show asm disk groups.
   Sample Output:
   =============
    GROUP_NUMBER  NAME   SECTOR_SIZE LOGICAL_SECTOR_SIZE BLOCK_SIZE ALLOCATION_UNIT_SIZE   STATE    TYPE
    ------------ ------- ----------- ------------------- ---------- -------------------- --------- ------
               1 DATAC2          512                 512       4096              4194304 CONNECTED NORMAL
               2 DBFS_C2         512                 512       4096              4194304 MOUNTED   HIGH
               3 RECOC2          512                 512       4096              4194304 MOUNTED   HIGH
               4 FLASH           512                 512       4096              4194304 MOUNTED   NORMAL


    GROUP_NUMBER  NAME   ONLINES OFFLINES NORMALS ABNORMALS ERRORS  READS   BYTES_READ AVG_R_TIME  WRITES
    ------------ ------- ------- -------- ------- --------- ------ -------- ---------- ---------- -------
               1 DATAC2       82        0      82         0     22 982.22 M   41.53 TB      130us 48.01 M
               2 DBFS_C2      69        0      69         0      0  29.35 M  114.97 GB        1ms  6.97 K
               3 RECOC2       82        0      82         0     13   9.07 M   57.25 GB        1ms 12.54 M
               4 FLASH       112        0     112         0      0  26.29 M  119.83 GB      135us 85.30 K


               NAME            READ_ONLY  DISKGROUP#1   DISKGROUP#2   DISKGROUP#3   DISKGROUP#4
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
   ]]--
]]*/
set feed off verify on
col reads,writes for tmb
col BYTES_READ,BYTES_WRITTEN for kmg
col AVG_R_TIME,AVG_W_TIME,AVG_TIME for usmhd0

select * from v$asm_diskgroup order by 1;
SELECT /*+no_merge(a) no_merge(b) use_hash(a b)*/
       GROUP_NUMBER,
       NAME,
       SUM(ONLINES) ONLINES,
       SUM(OFFLINES) OFFLINES,
       SUM(NORMALS) NORMALS,
       SUM(ABNORMALS) ABNORMALS,
       SUM(ERRORS) ERRORS,
       SUM(READS) READS,
       SUM(BYTES_READ) BYTES_READ,
       SUM(AVG_R_TIME) AVG_R_TIME,
       SUM(WRITES) WRITES,
       SUM(BYTES_WRITTEN) BYTES_WRITTEN,
       SUM(AVG_W_TIME) AVG_W_TIME,
       SUM(AVG_TIME) AVG_TIME &fg
FROM   (SELECT group_number, NAME FROM v$asm_diskgroup) a 
NATURAL RIGHT JOIN   (SELECT GROUP_NUMBER,
                     failgroup,
               COUNT(decode(MODE_STATUS, 'ONLINE', 1)) ONLINES,
               COUNT(decode(MODE_STATUS, 'OFFLINE', 1)) OFFLINES,
               COUNT(decode(STATE, 'NORMAL', 1)) NORMALS,
               SUM(decode(STATE, 'NORMAL', 0, 1)) ABNORMALS,
               SUM(READ_ERRS + WRITE_ERRS) errors,
               SUM(READS) READS,
               SUM(BYTES_READ) BYTES_READ,
               round(1e4 * SUM(READ_TIME) / nullif(SUM(READS), 0)) avg_r_time,
               SUM(WRITES) WRITES,
               SUM(BYTES_WRITTEN) BYTES_WRITTEN,
               round(1e4 * SUM(WRITE_TIME) / nullif(SUM(WRITES), 0)) avg_w_time,
               round(1e4 * SUM(READ_TIME+WRITE_TIME) / nullif(SUM(WRITES+READS), 0)) avg_time
        FROM   v$asm_disk
        GROUP  BY GROUP_NUMBER, failgroup) b
GROUP  BY GROUP_NUMBER, NAME
ORDER  BY 1;

var x refcursor;
declare
   c sys_refcursor;
   grps VARCHAR2(4000);
BEGIN
   
   select LISTAGG('''#'||GROUP_NUMBER||''' AS DISKGROUP#'||GROUP_NUMBER||'',',') within group(order by GROUP_NUMBER) into grps from v$asm_diskgroup;
   OPEN C for '
        SELECT *
        FROM  (SELECT NAME, READ_ONLY,VALUE, ''#'' || group_number grp FROM V$ASM_ATTRIBUTE WHERE NAME NOT LIKE ''template%'')
        PIVOT (MAX(VALUE) FOR grp IN('||grps||'))
        ORDER BY name';
   
   :x := c;
END;
/