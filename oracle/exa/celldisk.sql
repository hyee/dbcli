/*[[cellcli list celldisk. Usage: @@NAME [<cell>][-cli]
    -cli: Show the info of EXA$CELLDISK instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$CELLDISK={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col size,freeSpace for kmg
col cell,cellnode break skip -
col grp1,grp2 noprint
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c FOR
            WITH R AS(
                SELECT * FROM(
                    SELECT cast(extractvalue(xmltype(a.confval),'/cli-output/context/@cell') as varchar2(20)) cell, b.*
                    FROM   v$cell_config a,
                           XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                                    "diskType" VARCHAR2(10) path 'diskType',
                                    "name" VARCHAR2(30) path 'name',
                                    "size" INT path 'size',
                                    "freeSpace" INT path 'freeSpace',
                                    "errorCount" number(8) path 'errorCount',
                                    "status" VARCHAR2(15) path 'status',
                                    "deviceName" VARCHAR2(15) path 'deviceName',
                                    "devicePartition" VARCHAR2(18) path 'devicePartition',
                                    "physicalDisk" VARCHAR2(20) path 'physicalDisk',
                                    "creationTime" VARCHAR2(25) path 'creationTime',
                                    "lun" VARCHAR2(10) path 'lun',
                                    "id" VARCHAR2(60) path 'id',
                                    "interleaving" VARCHAR2(10) path 'interleaving',
                                    "raidLevel" VARCHAR2(10) path 'raidLevel',
                                    "comment" VARCHAR2(100) path 'comment') b
                    WHERE  conftype = 'CELLDISKS')
                WHERE lower(cell) like lower('%'||V1||'%'))
            SELECT r.*,0 grp1,0 grp2 FROM R
            UNION ALL
            SELECT nvl(cell,'Total Cells: '||count(distinct cell)) cell,
                   "diskType",'Total Cell Disks: '||count(1),
                   sum("size"),sum("freeSpace"),
                   sum("errorCount"),max("status"),
                   'Devices: '||count(distinct "deviceName"),null,
                   'PhyDisks: '||count(distinct "physicalDisk"),
                   null,null,null,null,
                   null,null,
                   grouping_id(cell) grp1,2 grp2
            FROM   r
            GROUP  BY "diskType",rollup(cell)
            ORDER  BY grp1,1,grp2, 2, 3;
    $ELSE
        OPEN c FOR
            WITH r AS(
                SELECT CELLNODE,"diskType",NAME,"size","freeSpace","errorCount","status","deviceName","devicePartition","physicalDisk","creationTime","id","comment"
                FROM   EXA$CELLDISK
                WHERE lower(cellnode) like lower('%'||V1||'%'))
            SELECT r.*,0 grp1,0 grp2 FROM R
            UNION ALL
            SELECT nvl(CELLNODE,'Total Cells: '||count(distinct CELLNODE)) cell,
                   "diskType",'Total Cell Disks: '||count(1),
                   sum("size"),sum("freeSpace"),
                   sum("errorCount"),max("status"),
                   'Devices: '||count(distinct "deviceName"),null,
                   'PhyDisks: '||count(distinct "physicalDisk"),
                   null,null,null,
                   grouping_id(CELLNODE) grp1,2 grp2
            FROM   r
            GROUP  BY "diskType",rollup(CELLNODE)
            ORDER  BY grp1,1,grp2, 2, 3;
    $END
    :c := c;
END;
/
print c;