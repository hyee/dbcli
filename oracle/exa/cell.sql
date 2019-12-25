/*[[
    Summary Exadata storage info. Usage: @@NAME [-cli]
    -cli: Show the info of EXA$* instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$CELLCONFIG={2} default={3}
      &OPT: DEFAULT={1} cli={2}
      &TABLE: DEFAULT={XMLTABLE('/ROWSET/ROW' PASSING DATA COLUMNS OBJECTNAME VARCHAR2(100) PATH 'OBJECTNAME',CELLNODE VARCHAR2(30) PATH 'CELLNODE',DISKTYPE VARCHAR2(20) PATH 'DISKTYPE',NAME VARCHAR2(300) PATH 'NAME',VALUE VARCHAR2(300) PATH 'VALUE')}
    --]]
]]*/
set printsize 3000 feed off verify off
col ramCacheMaxSize,ramCacheSize for kmg
SELECT b.*
FROM   v$cell_config a,
       XMLTABLE('/cli-output/cell' PASSING xmltype(a.confval) COLUMNS
                cell VARCHAR2(20) path 'name',
                "status" VARCHAR2(15) path 'status',
                "bbuStatus" VARCHAR2(15) path 'bbuStatus',
                "temperatureStatus" VARCHAR2(15) path 'temperatureStatus',
                "usbStatus" VARCHAR2(15) path 'usbStatus',
                "fanStatus" VARCHAR2(15) path 'fanStatus',
                "locatorLEDStatus" VARCHAR2(8) path 'locatorLEDStatus',
                "powerStatus" VARCHAR2(15) path 'powerStatus',
                "releaseImageStatus" VARCHAR2(15) path 'releaseImageStatus',
                "cpuCount" VARCHAR2(8) path 'cpuCount',
                "memoryGB" VARCHAR2(8) path 'memoryGB',
                "flashCacheMode" VARCHAR2(12) path 'flashCacheMode',
                "pmemCacheMode" VARCHAR2(12) path 'pmemCacheMode',
                "ramCacheMode" VARCHAR2(4) path 'ramCacheMode',
                "ramCacheMaxSize" NUMBER(15) path 'ramCacheMaxSize',
                "ramCacheSize" NUMBER(15) path 'ramCacheSize',
                "temperatureReading" NUMBER(3) path 'temperatureReading',
                "diagHistoryDays" NUMBER(5) path 'diagHistoryDays',
                "upTime" VARCHAR2(15) path 'upTime',
                "fanCount" VARCHAR2(5) path 'fanCount',
                "flashCacheCompress" VARCHAR2(300) path 'flashCacheCompress',
                "accessLevelPerm" VARCHAR2(20) path 'accessLevelPerm',
                "id" VARCHAR2(15) path 'id',
                "cellVersion" VARCHAR2(40) path 'cellVersion',
                "interconnectCount" number(2) path 'interconnectCount',
                "interconnect1" VARCHAR2(10) path 'interconnect1',
                "interconnect2" VARCHAR2(10) path 'interconnect2',
                "iormBoost" VARCHAR2(10) path 'iormBoost',
                "ipaddress1" VARCHAR2(20) path 'ipaddress1',
                "ipaddress2" VARCHAR2(20) path 'ipaddress2',
                "kernelVersion" VARCHAR2(30) path 'kernelVersion',
                "makeModel" VARCHAR2(60) path 'makeModel',
                "metricHistoryDays" NUMBER(5) path 'metricHistoryDays',
                "notificationMethod" VARCHAR2(10) path 'notificationMethod',
                "notificationPolicy" VARCHAR2(25) path 'notificationPolicy',
                "smtpPort" NUMBER(5) path 'smtpPort',
                "smtpServer" VARCHAR2(30) path 'smtpServer',
                "smtpToAddr" VARCHAR2(100) path 'smtpToAddr',
                "smtpUseSSL" VARCHAR2(5) path 'smtpUseSSL',
                "offloadGroupEvents" VARCHAR2(20) path 'offloadGroupEvents',
                "powerCount" VARCHAR2(9) path 'powerCount',
                "releaseVersion" VARCHAR2(25) path 'releaseVersion',
                "rpmVersion" VARCHAR2(50) path 'rpmVersion',
                "releaseTrackingBug" number(15) path 'releaseTrackingBug',
                "rollbackVersion" VARCHAR2(30) path 'rollbackVersion'
                ) b
WHERE  conftype = 'CELL'
ORDER BY 1;

var c1 REFCURSOR;
var c2 REFCURSOR;
var c3 REFCURSOR;

DECLARE
    c1   SYS_REFCURSOR;
    c2   SYS_REFCURSOR;
    c3   SYS_REFCURSOR;
    data XMLTYPE;
BEGIN
    $IF &check_access_vw=3 $THEN
        raise_application_error(-20001,'Cannot access v$cell_config, aborted.');
    $END

    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c1 FOR
            SELECT CAST(NVL(CELL,'--TOTAL--') AS VARCHAR2(20)) cell,
                   SUM(decode("flashCacheStatus",'normal',"FlashCache")) "FlashCache",
                   SUM(decode("flashCacheStatus",'normal',"FlashLog")) "FlashLog",
                   SUM(numPmem*regexp_substr(pmemType,'(\d+[\d\.]*)[GT]',1,1,'i',1))||max(regexp_substr(pmemType,'(\d+[\d\.]*)([GT])',1,1,'i',2)) "PMEM",
                   SUM("CellDisks") "CellDisks",
                   SUM("GridDisks") "GridDisks",
                   SUM("HardDisks") "HardDisks",
                   SUM("FlashDisks") "FlashDisks",
                   ROUND(sum(nvl("maxHDIOPS"*"HardDisks",0)+nvl("maxFDIOPS"*"FlashDisks",0))/3) ESTIOPS,
                   sum(nvl("maxHDMBPS"*"HardDisks",0)+nvl("maxFDMBPS"*"FlashDisks",0))*0.7 ESTMBPS,
                   '|' "|",
                   max("maxHDIOPS") "HDMaxIOPS",
                   max("maxFDIOPS") "FDMaxIOPS",
                   max("maxHDMBPS") "HDMaxMBPS",
                   max("maxFDMBPS") "FDMaxMBPS",
                   max("dwhHDQL") "HDdwhQL",
                   max("dwhFDQL") "FDdwhQL",
                   max("oltpHDQL") "HDoltpQL",
                   max("oltpFDQL") "FDoltpQL",
                   CAST(MAX("hardDiskType") AS VARCHAR2(10)) "hardDiskType",
                   CAST(MAX("flashDiskType") AS VARCHAR2(10)) "flashDiskType"
            FROM   (SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell, b.*
                    FROM   v$cell_config_info a,
                           XMLTABLE('/cli-output/not-set' PASSING xmltype(a.confval) COLUMNS --
                                    "FlashCache" INT path 'effectiveFlashCacheSize', "FlashLog" INT path 'effectiveFlashLogSize',
                                    "GridDisks" INT path 'numGridDisks', "CellDisks" INT path 'numCellDisks', "HardDisks" INT path 'numHardDisks',
                                    "FlashDisks" INT path 'numFlashDisks', "maxHDIOPS" INT path 'maxPDIOPS', "maxFDIOPS" INT path 'maxFDIOPS',
                                    "maxHDMBPS" INT path 'maxPDMBPS', "maxFDMBPS" INT path 'maxFDMBPS', "dwhHDQL" INT path 'dwhPDQL', "dwhFDQL" INT path 'dwhFDQL',
                                    "oltpHDQL" INT path 'oltpPDQL', "oltpFDQL" INT path 'oltpFDQL', "hardDiskType" VARCHAR2(300) path 'hardDiskType',
                                    "flashDiskType" VARCHAR2(300) path 'flashDiskType', "flashCacheStatus" VARCHAR2(300) path 'flashCacheStatus',
                                    "cellPkg" VARCHAR2(300) path 'cellPkg',
                                    numPmem int path 'numPmem',pmemType varchar2(100) path 'pmemType',pmemCacheStatus varchar2(100) path 'pmemCacheStatus') b
                    WHERE  conftype = 'AWRXML')
            GROUP  BY ROLLUP(CELL);

        OPEN c2 FOR
            WITH gstats0 as(
                SELECT nvl(cell_hash,0) cellhash,
                       case when metric_name like '%allocated - large writes%' then 'Large Writes' else metric_name end n, 
                       sum(metric_value) v
                FROM   v$cell_global
                group by case when metric_name like '%allocated - large writes%' then 'Large Writes' else metric_name end,rollup(cell_hash)),
            gstats as(
                select * from gstats0
                union all
                select cellhash,'SCAN',
                       sum(decode(n,
                           'Flash cache bytes allocated',v,
                           'Flash cache bytes allocated for OLTP data',-v,
                           'Large Writes',-v,
                           'Flash cache bytes used - columnar',-v,
                           'Flash cache bytes used - columnar keep',v,0
                       ))
                from  gstats0 
                group by cellhash
            )
            SELECT * FROM (
                SELECT  NVL((SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                                FROM   v$cell_config c
                                WHERE  c.CELLNAME = a.CELLNAME
                                AND    rownum < 2),'--TOTAL--') cell,
                        nvl(cellhash,0) cellhash,
                        SUM(DECODE(disktype, 'HardDisk', 1,0)) HD,
                        SUM(DECODE(disktype, 'FlashDisk', 1,0))  FD,
                        SUM(DECODE(disktype, 'PMEM', 1,0))  PMEM,
                        SUM(DECODE(disktype, 'HardDisk', siz)) HD_SIZE,
                        SUM(DECODE(disktype, 'FlashDisk', siz)) FD_SIZE,
                        SUM(DECODE(disktype, 'PMEM', siz))  PMEM_SIZE,
                        SUM(siz) total_size,
                        SUM(freeSpace) unalloc,
                        '|' "|"
                FROM   (SELECT  CELLNAME,CELLHASH,
                                b.*
                        FROM   v$cell_config a,
                        XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                                    NAME VARCHAR2(300) path 'name',
                                    diskType VARCHAR2(300) path 'diskType',
                                    siz INT path 'size',
                                    freeSpace INT path 'freeSpace') b
                        WHERE  conftype = 'CELLDISKS') a
                GROUP  BY rollup((cellname,CELLHASH)))
            RIGHT JOIN (
                select cellhash,
                       round(sum(decode(n,'RAM cache read requests hit',v))/nullif(sum(decode(n,'RAM cache read requests hit',v,'RAM cache read misses',v)),0),4) "RAM|HIT",
                       round(sum(decode(n,'PMEM cache read requests hit',v))/nullif(sum(decode(n,'PMEM cache read requests hit',v,'PMEM cache read misses',v)),0),4) "PMEM|HIT",
                       round(sum(decode(n,'Flash cache read requests hit',v))/nullif(sum(decode(n,'Flash cache read requests hit',v,'Flash cache misses and partial hits',v)),0),4) "FC|HIT",
                       round(sum(decode(n,'Flash cache read requests - columnar',v))/nullif(sum(decode(n,'Flash cache columnar read requests eligible',v)),0),4) "FCC|HIT",
                       '|' "|"
                from gstats
                group by cellhash) USING(cellhash)
            RIGHT JOIN (
                SELECT * FROM gstats PIVOT (
                    MAX(v) FOR n IN(
                        'Flash cache bytes allocated' AS "Alloc|FCache",
                        'Flash cache bytes allocated for OLTP data' AS "Alloc|OLTP",
                        'SCAN' AS "Alloc|Scan",
                        'Flash cache bytes allocated for unflushed data' AS "OLTP|Dirty",
                        'Large Writes' AS "Large|Writes",
                        'Flash cache bytes used' AS "FCache|Used",
                        'Flash cache bytes used for OLTP data' AS "Used|OLTP",
                        'Flash cache bytes used - columnar' AS "Used|FCC",
                        'Flash cache bytes used - keep objects' AS "FCache|Keep",
                        'Flash cache bytes allocated for OLTP keep objects' AS  "Keep|OLTP",
                        --'Flash cache bytes used - columnar keep' AS "Keep|FCC",
                        '|' as "|",
                        'PMEM cache bytes allocated' as "Alloc|PMEM",
                        'PMEM cache bytes used for OLTP data' as "PMEM|OLTP",
                        'RAM cache bytes allocated' as "Alloc|RAM",
                        'RAM cache bytes allocated for OLTP data' as "RAM|OLTP"))) b 
            USING(cellhash);

        OPEN c3 FOR
            WITH grid AS(
                SELECT * FROM (
                  SELECT a.*,
                         row_number() over(partition by name,diskgroup,grp order by 1) r,
                         round(fc*max(decode(grp,'CELLDISKS',siz)) over(partition by extractvalue(c.COLUMN_VALUE,'.'))/count(1) over(partition by grp,extractvalue(c.COLUMN_VALUE,'.'))) fcsize
                  FROM(
                      SELECT conftype grp,
                             DISKGROUP,
                             nvl(cachedBy,name) cachedBy,
                             count(distinct diskType) over() dtypes,
                             sum(nvl2(cachedBy,1,0)) over (partition by nvl(cachedBy,name)) caching,
                             nvl(cellDisk,name) name,
                             decode(diskType,'',0, 'HardDisk', 1, 0) hd,
                             decode(diskType,'',0, 'FlashDisk', 1, 0) fd,
                             decode(diskType,'',0, 'PMEM', 1, 0) pm,
                             errors errors,
                             decode(status,'active',0,nvl2(trim(asmDiskName),1,0)) offlines,
                             siz siz,
                             freeSpace freeSpace,
                             decode(trim(asmDiskName),'',siz,0) usize,
                             nvl2(cachedBy,1,0) fc
                      FROM   v$cell_config a,
                             XMLTABLE('/cli-output/*[size]' PASSING xmltype(a.confval) COLUMNS --
                                      cellDisk VARCHAR2(300) path 'cellDisk', 
                                      name VARCHAR2(300) path 'name', 
                                      diskType VARCHAR2(300) path 'diskType',
                                      errors VARCHAR2(300) path 'errorCount',
                                      siz INT path 'size',
                                      status varchar2(30) path 'status',
                                      DISKGROUP VARCHAR2(300) path 'asmDiskGroupName', 
                                      asmDiskName VARCHAR2(300) path 'asmDiskName',
                                      cachedBy VARCHAR2(300) path 'cachedBy',
                                      freeSpace INT path 'freeSpace') b
                      WHERE  conftype IN ('GRIDDISKS','CELLDISKS')) a,
                             XMLTABLE((('"'||replace(regexp_replace(a.cachedBy,'[" ]'),',','","')||'"'))) c)
                  WHERE r=1),
            storage as(
                select  nvl(G.DISKGROUP,'(Free)') DISKGROUP,
                        MAX(c.dtypes) dtypes,
                        sum(nvl(g.hd,sign(c.hd))) hd,
                        sum(nvl(g.fd,sign(c.fd))) fd,
                        sum(nvl(g.pm,sign(c.pm))) pm,
                        sum(nvl(g.offlines,1)) offlines,
                        sum(nvl(g.errors,0)) errors,
                        sum(nvl(g.siz,c.siz)) gsize,
                        sum(c.siz-c.freeSpace-nvl(g.siz,0)) csize, 
                        sum(c.freeSpace+nvl(g.usize,0)) usize,
                        sum(g.fcsize) fc
                from   (select * from grid a where grp='CELLDISKS' and (caching=0 or dtypes=1)) c 
                left   join (select * from grid where grp='GRIDDISKS') g 
                using  (name)
                group  by g.diskgroup)
            SELECT  /*+no_merge(c) no_merge(a) use_hash(c a)*/
                    DISTINCT a.*, listagg(decode(mod(r,8),0,chr(10),'')||tbs,',') WITHIN GROUP(ORDER BY tbs) OVER(PARTITION BY DISKGROUP) tablespaces
            FROM   (SELECT  /*+no_merge(c) no_merge(b) use_hash(c b a)*/
                            nvl(diskgroup,'--TOTAL--') diskgroup,
                            a.type type,
                            a.DATABASE_COMPATIBILITY "DB_COMP",
                            SUM(b.errors) errs,
                            SUM(hd)  "Hard|Disks",
                            SUM(fd) "Flash|Disks",
                            SUM(pm) "PMEM|Disks",
                            SUM(greatest(nvl(a.OFFLINE_DISKS,0),b.offlines)) "Offline|Disks",
                            decode(dtypes,1,decode(sum(fc),0,'N','Y'),''||SUM(fc)) "Flash|Cache",
                            SUM(gsize) "Disk|Size",
                            SUM(a.TOTAL_MB) * 1024 * 1024 "Disk Group|Total Size",
                            SUM(a.FREE_MB) * 1024 * 1024 "Disk Group|Free Size",
                            sum(a.USABLE_FILE_MB) * 1024 * 1024 "Usable|Size"
                            --,regexp_replace(listagg(b.FAILGROUP, '/') WITHIN GROUP(ORDER BY b.failgroup), '([^/]+)(/\1)+', '\1') failgroups
                    FROM    storage b,
                            v$asm_diskgroup a
                    WHERE  a.name(+) = b.DISKGROUP
                    GROUP  BY dtypes,rollup((DISKGROUP,type,DATABASE_COMPATIBILITY))) a,
            (SELECT c.*,row_number() over(PARTITION by dg order by tbs) r
             FROM
                (SELECT DISTINCT tbs, regexp_substr(FILE_NAME, '[^\+\\\/]+') dg
                        FROM   (SELECT /*+leading(b) use_hash(a)*/ 
                                      B.NAME tbs,A.NAME file_name
                                FROM  (SELECT ts#, name  FROM v$datafile UNION ALL select ts#,name from v$tempfile) A
                                JOIN  v$tablespace B USING(ts#)
                                UNION ALL
                                SELECT '(Redo)' tbs, MEMBER
                                FROM   v$logfile
                                UNION ALL
                                SELECT '(FlashBack)', NAME
                                FROM   V$FLASHBACK_DATABASE_LOGFILE
                                WHERE  ROWNUM <= 30
                                UNION ALL
                                SELECT '(ArchivedLog)', NAME
                                FROM   V$ARCHIVED_LOG
                                WHERE  ROWNUM <= 30)) c) c
                WHERE  a.DISKGROUP = c.dg(+)
            ORDER  BY 1;
    $ELSE
        data := DBMS_XMLGEN.GETXMLTYPE(q'[
            SELECT /*+no_expand opt_param('parallel_force_local' 'true')*/ 
                   CELLNODE,OBJECTTYPE||'.'||FIELDNAME NAME,
                   NAME OBJECTNAME,
                   MAX(decode(fieldname,'diskType',VALUE)) OVER(PARTITION BY CELLNODE,OBJECTTYPE,name) disktype,
                   VALUE 
            FROM   exa$cellconfig 
            WHERE  OBJECTTYPE IN('CELLDISK','PHYSICALDISK','GRIDDISK','FLASHCACHE','FLASHLOG')
            AND    (regexp_like(value,'^\d+$') OR FIELDNAME in('asmDiskGroupName','asmDiskName','deviceName','diskType','status','makeModel','cachedBy','cellDisk'))]');

        OPEN c1 FOR
            SELECT NVL(CELLNODE,'--TOTAL--') CELL,
                   SUM(decode(name,'FLASHCACHE.size',value)) "FlashCache",
                   SUM(decode(name,'FLASHLOG.size',value)) "FlashLog",
                   SUM(decode(name,'PHYSICALDISK.physicalSize',decode(disktype,'FlashDisk',0,value+0))) HD_SIZE,
                   SUM(decode(name||'.'||disktype,'PHYSICALDISK.physicalSize.FlashDisk',value)) FD_SIZE,
                   COUNT(decode(name,'CELLDISK.size',1)) "Cell|Disks",
                   COUNT(decode(name||'.'||VALUE,'CELLDISK.status.normal',1)) "CellDisks|Online",
                   SUM(decode(name,'CELLDISK.size',value)) "CellDisk|Size",
                   SUM(decode(name,'CELLDISK.freeSpace',value)) "CellDisk|UnAlloc",
                   SUM(decode(name,'CELLDISK.errorCount',value)) "CellDisk|Errors",
                   COUNT(decode(name,'GRIDDISK.size',1)) "Grid|Disks",
                   COUNT(decode(name||'.'||VALUE,'GRIDDISK.status.active',1)) "GridDisks|Online",
                   SUM(decode(name,'GRIDDISK.size',value)) "GridDisk|Size",
                   SUM(decode(name,'GRIDDISK.errorCount',value)) "GridDisk|Errors",
                   COUNT(decode(name||'.'||VALUE,'PHYSICALDISK.status.normal',1)) "Disks|Online",
                   COUNT(decode(name,'PHYSICALDISK.diskType',decode(value,'FlashDisk',null,1))) "Hard|Disks",
                   COUNT(decode(name||'.'||VALUE,'PHYSICALDISK.diskType.FlashDisk',1)) "Flash|Disks",
                   MAX(decode(name||'.'||VALUE,'PHYSICALDISK.makeModel.FlashDisk',value)) "FlashDisk|Model",
                   MAX(decode(name,'PHYSICALDISK.makeModel',decode(disktype,'FlashDisk','',value))) "HardDisk|Model"
            FROM  &table
            GROUP BY ROLLUP(CELLNODE)
            ORDER BY 1;

        OPEN c2 FOR
            WITH phydisk AS (
                SELECT cellnode,deviceName,decode(diskType,'FlashDisk',1,0) FD 
                FROM (
                    SELECT cellnode,objectname,REGEXP_SUBSTR(NAME,'[^\.]+$') n,value 
                    FROM   &table 
                    WHERE  REGEXP_LIKE(name,'CELLDISK\.(deviceName|diskType)'))
                PIVOT (max(value) for n in('deviceName' deviceName,'diskType' diskType)))
            SELECT /*+orderd use_hash(b) swap_join_inuts(b) opt_param('parallel_force_local' 'true')*/
                   nvl(a.CELLNODE,'--TOTAL--') CELL,
                   Round(AVG(decode(NAME||'.'||FD,'I/O utilization per disk.1',nvl(value,0))),3) "Flash|Util",
                   Round(AVG(decode(NAME||'.'||FD,'I/O utilization per disk.0',nvl(value,0))),3) "Hard|Util",
                   SUM(DECODE(NAME,'Number of flash cache IO errors',value,'Number of disk IO errors',value)) "IO|Errs",
                   '|' "|",
                   SUM(DECODE(NAME,'Cachesize(KB)',value*1024)) "FCache|Used",
                   SUM(DECODE(NAME,'OLTPsize(KB)',value*1024)) "Used|OLTP",
                   SUM(DECODE(NAME,'Keepsize(KB)',value*1024)) "FCache|Keep",
                   SUM(DECODE(NAME,'Columnar Cache used size (KB)',value*1024)) "Used|FCC",
                   SUM(DECODE(NAME,'Columnar Cache keep Size (KB)',value*1024)) "Keep|FCC",
                   ROUND(SUM(DECODE(NAME,'Number of SCAN bytes read from Columnar Cache',value))/NULLIF(SUM(DECODE(NAME,'Number of SCAN bytes read from Columnar Cache',value,'Number of SCAN bytes read from cache(KB)',value)),0),4) "FCC%|Scan",
                   ROUND(SUM(DECODE(NAME,'Read on flashcache hit(KB)',value))/NULLIF(SUM(DECODE(NAME,'Read on flashcache hit(KB)',value,'Total IO size for read miss(KB)',value)),0),4) "FCache|Hit",
                   ROUND(SUM(DECODE(NAME,'Number of read hits',value))/NULLIF(SUM(DECODE(NAME,'Number of read hits',value,'Number of read misses',value)),0),4) "Read|Hit",
                   ROUND(SUM(DECODE(NAME,'Number of SCAN bytes read from cache(KB)',value))/NULLIF(SUM(DECODE(NAME,'Number of scan bytes attempted to read from cache(KB)',value)),0),4) "Scan|Hit",
                   ROUND(SUM(DECODE(NAME,'Number of scans read from Columnar Cache',value))/NULLIF(SUM(DECODE(NAME,'Number of reads attempted in  Columnar Cache',value)),0),4) "FCC|Hit",
                   ROUND(SUM(DECODE(NAME,'Number of cache writes',value))/NULLIF(SUM(DECODE(NAME,'Number of cache writes',value,'Number of nocache writes',value)),0),4) "FCache|Write"，
                   '|' "|",
                   SUM(DECODE(NAME,'RamCache size (KB)',value*1024)) "RAM|Used",
                   ROUND(SUM(DECODE(NAME,'RamCache read hits',value))/NULLIF(SUM(DECODE(NAME,'RamCache read hits',value,'RamCache read misses',value)),0),4) "RAM|Read",
                   ROUND(SUM(DECODE(NAME,'RamCache scan hits (KB)',value))/NULLIF(SUM(DECODE(NAME,'RamCache scan attempted (KB)',value)),0),4) "RAM|Scan",
                   '|' "|",
                   SUM(DECODE(NAME,'PmemCache size (KB)',value*1024)) "PMEM|Used",
                   SUM(DECODE(NAME,'PmemCache OLTP size (KB)',value*1024)) "PMEM|Keep",
                   ROUND(SUM(DECODE(NAME,'PmemCache read hits',value))/NULLIF(SUM(DECODE(NAME,'PmemCache read hits',value,'PmemCache read misses',value)),0),4) "PMEM|Read",
                   '|' "|",
                   SUM(DECODE(NAME,'Total smart IO being cached in flash (KB)',value*1024)) "SmartIO|Cached",
                   ROUND(SUM(DECODE(NAME,'Total smart IO read from flash (KB)',value))/NULLIF(SUM(DECODE(NAME,'Total smart IO read from flash (KB)',value,'Total smart IO read from hard disk (KB)',value)),0),4)  "SmartIO|Flash",
                   ROUND(1-SUM(DECODE(NAME,'Total smart IO filtered size (KB)',value))/NULLIF(SUM(DECODE(NAME,'Total smart IO in IO (KB)',value)),0),4)  "SmartIO|Filter",
                   ROUND(SUM(DECODE(NAME,'Size of IO avoided due to storage index (KB)',value))/NULLIF(SUM(DECODE(NAME,'Total smart IO in IO (KB)',value)),0),4)  "SmartIO|SiSaved",
                   ROUND(SUM(DECODE(NAME,'Number of bytes saved by hits from Columnar Cache(KB)',value))/NULLIF(SUM(DECODE(NAME,'Total smart IO in IO (KB)',value)),0),4)  "SmartIO|CCSaved",
                   ROUND(SUM(DECODE(NAME,'Total output size (KB)',value))/NULLIF(SUM(DECODE(NAME,'Total input IO size (KB)',value)),0),4)  "Offload|Out/In"
            FROM   EXA$CELLSRVSTAT A, phydisk B
            WHERE  A.CELLNODE=B.CELLNODE(+)
            AND    A.ITEM=B.deviceName(+)
            GROUP  BY ROLLUP(A.CELLNODE)
            ORDER  BY 1;

        OPEN c3 FOR
            WITH grid AS(
                SELECT /*+MATERIALIZE*/ a.*,round(fc*max(decode(grp,'CELLDISK',siz)) over(partition by cachedBy)/count(1) over(partition by grp,cachedBy)) fcsize
                FROM(
                    SELECT grp,
                           nvl(cachedBy,objectname) cachedBy,
                           count(distinct diskType) over() dtypes,
                           sum(nvl2(cachedBy,1,0))  over (partition by nvl(cachedBy,objectname)) caching,
                           nvl(cellDisk,objectname) name,
                           DISKGROUP,
                           decode(diskType,'',0, 'FlashDisk', 0, 1) hd,
                           decode(diskType,'',0, 'FlashDisk', 1, 0) fd,
                           errors errors,
                           decode(status,'active',0,nvl2(trim(asmDiskName),1,0)) offlines,
                           siz siz,
                           freeSpace freeSpace,
                           decode(trim(asmDiskName),'',siz,0) usize,
                           nvl2(cachedBy,1,0) fc
                    FROM  (SELECT cellnode,objectname,disktype,value,REGEXP_SUBSTR(NAME,'^[^\.]+') grp,REGEXP_SUBSTR(NAME,'[^\.]+$') n
                           FROM   &table
                           WHERE  name like 'GRIDDISK.%' or name like 'CELLDISK.%') 
                    PIVOT(MAX(VALUE) FOR n in('size' SIZ,'errorCount' errors,'cellDisk' cellDisk,'asmDiskName' asmDiskName,'asmDiskGroupName' DISKGROUP,'status' STATUS,'cachedBy' cachedBy,'freeSpace' freeSpace))) a),
            storage as(
                select  nvl(G.DISKGROUP,'(Free)') DISKGROUP,
                        MAX(c.dtypes) dtypes,
                        sum(nvl(g.hd,sign(c.hd))) hd,
                        sum(nvl(g.fd,sign(c.fd))) fd,
                        sum(nvl(g.offlines,1)) offlines,
                        sum(nvl(g.errors,0)) errors,
                        sum(nvl(g.siz,c.siz)) gsize,
                        sum(c.siz-c.freeSpace-nvl(g.siz,0)) csize, 
                        sum(c.freeSpace+nvl(g.usize,0)) usize,
                        sum(g.fcsize) fc
                from   (select * from grid a where grp='CELLDISK' and (caching=0 or dtypes=1)) c 
                left   join (select * from grid where grp='GRIDDISK') g 
                using  (name)
                group  by g.diskgroup)
            SELECT  /*+no_merge(c) no_merge(a) use_hash(c a)*/
                    DISTINCT a.*, listagg(decode(mod(r,8),0,chr(10),'')||tbs,',') WITHIN GROUP(ORDER BY tbs) OVER(PARTITION BY DISKGROUP) tablespaces
            FROM   (SELECT  /*+no_merge(c) no_merge(b) use_hash(c b a)*/
                            nvl(diskgroup,'--TOTAL--') diskgroup,
                            a.type type,
                            a.DATABASE_COMPATIBILITY "DB_COMP",
                            SUM(b.errors) errs,
                            SUM(hd)  "Hard|Disks",
                            SUM(fd) "Flash|Disks",
                            SUM(greatest(nvl(a.OFFLINE_DISKS,0),b.offlines)) "Offline|Disks",
                            decode(dtypes,1,decode(sum(fc),0,'N','Y'),''||SUM(fc)) "Flash|Cache",
                            SUM(gsize) "Disk|Size",
                            SUM(a.TOTAL_MB) * 1024 * 1024 "Disk Group|Total Size",
                            SUM(a.FREE_MB) * 1024 * 1024 "Disk Group|Free Size",
                            sum(a.USABLE_FILE_MB) * 1024 * 1024 "Usable|Size"
                            --,regexp_replace(listagg(b.FAILGROUP, '/') WITHIN GROUP(ORDER BY b.failgroup), '([^/]+)(/\1)+', '\1') failgroups
                    FROM    storage b,
                            v$asm_diskgroup a
                    WHERE  a.name(+) = b.DISKGROUP
                    GROUP  BY dtypes,rollup((DISKGROUP,type,DATABASE_COMPATIBILITY))) a,
            (SELECT c.*,row_number() over(PARTITION by dg order by tbs) r
             FROM
                (SELECT DISTINCT tbs, regexp_substr(FILE_NAME, '[^\+\\\/]+') dg
                        FROM   (SELECT /*+leading(b) use_hash(a)*/ 
                                      B.NAME tbs,A.NAME file_name
                                FROM  (SELECT ts#, name  FROM v$datafile UNION ALL select ts#,name from v$tempfile) A
                                JOIN  v$tablespace B USING(ts#)
                                UNION ALL
                                SELECT '(Redo)' tbs, MEMBER
                                FROM   v$logfile
                                UNION ALL
                                SELECT '(FlashBack)', NAME
                                FROM   V$FLASHBACK_DATABASE_LOGFILE
                                WHERE  ROWNUM <= 30
                                UNION ALL
                                SELECT '(ArchivedLog)', NAME
                                FROM   V$ARCHIVED_LOG
                                WHERE  ROWNUM <= 30)) c) c
                WHERE  a.DISKGROUP = c.dg(+)
            ORDER  BY 1;
    $END
    :c1 := c1;
    :c2 := c2;
    :c3 := c3;
END;
/
col "Disk Group|Total Size,total_size,Disk Group|Free Size,cached|size,Grid|Size,Disk|Size,Usable|Size,CellDisk|Size,Keep|FCC,CellDisk|UnAlloc,GridDisk|Size,HD_SIZE,FD_SIZE,PMEM_SIZE,flash_cache,flash_log,flash|cache" format kmg
col SmartIO|Cached,unalloc,flashcache,flashlog,Alloc|PMEM,PMEM|OLTP,Alloc|RAM,RAM|OLTP,Alloc|FCache,RAM|Used,PMEM|Keep,PMEM|Used,Alloc|OLTP,ALLOC|SCAN,Large|Writes,OLTP|Dirty,FCache|Used,Used|OLTP,Used|FCC,FCache|Keep,Keep|OLTP,Keep|FCC format kmg
col "FCC%|Scan,Read|Hit,RAM|Hit,PMEM|Hit,FC|Hit,FCC|Hit,Scan|Hit,FCache|Hit,FCache|Write,RAM|Read,RAM|Scan,PMEM|Read,SmartIO|Flash,SmartIO|Filter,SmartIO|SiSaved,SmartIO|CCSaved,Offload|Out/In" for pct
grid {'c1','-','c2','-','c3'}
