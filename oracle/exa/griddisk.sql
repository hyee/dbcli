/*[[cellcli list griddisk. Usage: @@NAME [<cell>|<diskgroup>|<celldisk>] [-cli]
    -cli: Show the info of EXA$GRIDDISK instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$GRIDDISK={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col size,offset for kmg
var c refcursor
col grp1,grp2 noprint
col cell,cellnode break skip -
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN C FOR
            WITH r AS(
                SELECT * FROM(
                    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
                    FROM   v$cell_config a,
                           XMLTABLE('/cli-output/griddisk' PASSING xmltype(a.confval) COLUMNS --
                                    "cellDisk" VARCHAR2(300) path 'cellDisk',
                                    "name" VARCHAR2(300) path 'name',
                                    "healthFactor" VARCHAR2(30) path 'healthFactor',
                                    "diskType" VARCHAR2(300) path 'diskType',
                                    "offset" INT path 'offset',
                                    "size" INT path 'size',
                                    "status" VARCHAR2(300) path 'status',
                                    "errorCount" INT path 'errorCount',
                                    "asmDiskGroupName" VARCHAR2(300) path 'asmDiskGroupName',
                                    "asmDiskName" VARCHAR2(300) path 'asmDiskName',
                                    "asmFailGroupName" VARCHAR2(300) path 'asmFailGroupName',
                                    "availableTo" VARCHAR2(300) path 'availableTo',
                                    "cachedBy" VARCHAR2(300) path 'cachedBy',
                                    "cachingPolicy" VARCHAR2(300) path 'cachingPolicy',
                                    "creationTime" VARCHAR2(300) path 'creationTime',
                                    "id" VARCHAR2(300) path 'id',
                                    "comment" VARCHAR2(100) path 'comment') b
                    WHERE  conftype = 'GRIDDISKS')
                WHERE nvl(lower(v1),' ') in(' ',lower(cell),lower("asmDiskGroupName"),lower("cellDisk")))
            SELECT r.*,0 grp1,0 grp2 FROM r
            UNION ALL
            SELECT nvl(cell,'Total Cells: '||count(distinct cell)) cell,
                   'Total Cell Disks: '||count(distinct "cellDisk"),'Grid Disks: '||count(1),"diskType",null,
                   sum("size"),max("status"),
                   sum("errorCount"),
                   'ASM Disk Groups: '||count(distinct "asmDiskGroupName"),
                   'ASM Disks: '||count(distinct "asmDiskName"),
                   null,null,null,null,null,null,null,
                   grouping_id(cell) grp1, 1 grp2
            FROM   r
            GROUP  BY "diskType",rollup(cell)
            ORDER  BY grp1,1,grp2, 2, 4;
    $ELSE
        OPEN c FOR
            WITH r AS(
                SELECT CELLNODE,"cellDisk",NAME,"diskType","size","status","errorCount",
                       "asmDiskGroupName","asmDiskName","asmFailGroupName","availableTo",
                       "cachedBy","cachingPolicy","creationTime","id","comment"
                FROM   EXA$GRIDDISK
                WHERE nvl(lower(v1),' ') in(' ',lower(cellnode),lower("asmDiskGroupName"),lower("cellDisk")))
            SELECT r.*,0 grp1,0 grp2 FROM r
            UNION ALL
            SELECT nvl(CELLNODE,'Total Cells: '||count(distinct CELLNODE)),
                   'Cell Disks: '||count(distinct "cellDisk"),'Grid Disks: '||count(1),"diskType",
                   sum("size"),max("status"),
                   sum("errorCount"),
                   'ASM Disk Groups: '||count(distinct "asmDiskGroupName"),
                   'ASM Disks: '||count(distinct "asmDiskName"),null,null,null,null,null,null,null,
                   grouping_id(CELLNODE) grp1, 1 grp2
            FROM   r
            GROUP  BY "diskType",rollup(CELLNODE)
            ORDER BY grp1,1,grp2,2,3;
    $END
    :c := c;
END;
/
print c;