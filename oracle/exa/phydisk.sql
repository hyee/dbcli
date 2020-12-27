/*[[cellcli list physicaldisk. Usage: @@NAME [<cell>] [-cli]
    -cli: show the info of EXA$PHYSICALDISK instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$PHYSICALDISK={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col physicalSize for kmg
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
                select * from(
                    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
                    FROM   v$cell_config a,
                           XMLTABLE('/cli-output/physicaldisk' PASSING xmltype(a.confval) COLUMNS --
                                    "name" VARCHAR2(20) path 'name',
                                    "deviceName" VARCHAR2(15) path 'deviceName',
                                    "diskType" VARCHAR2(10) path 'diskType',
                                    "physicalSize" INT path 'physicalSize',
                                    "errCount" NUMBER(8) path 'errOtherCount',
                                    "status" VARCHAR2(15) path 'status',
                                    "luns" VARCHAR2(10) path 'luns',
                                    "physicalFirmware" VARCHAR2(15) path 'physicalFirmware',
                                    "physicalInsertTime" VARCHAR2(25) path 'physicalInsertTime',
                                    "deviceId" NUMBER(5) path 'deviceId',
                                    "enclosureDeviceId" NUMBER(5) path 'enclosureDeviceId',
                                    "makeModel" VARCHAR2(40) path 'makeModel',
                                    "physicalInterface" VARCHAR2(10) path 'physicalInterface',
                                    "physicalSerial" VARCHAR2(15) path 'physicalSerial',
                                    "slotNumber" VARCHAR2(25) path 'slotNumber') b
                    WHERE  conftype = 'PHYSICALDISKS')
                WHERE lower(cell) like lower('%'||V1||'%'))
            SELECT r.*,0 grp1,0 grp2 FROM R
            UNION ALL
            SELECT nvl(cell,'Total Cells: '||count(distinct cell)) cell,'--TOTAL--',
                   'Devices: '||count(distinct "deviceName"),
                   "diskType",
                   sum("physicalSize"),
                   sum("errCount"),max("status"),
                   'Luns:'||count(distinct "luns"),'Firmwares:'||count(distinct "physicalFirmware"),
                   null,null,null,null,null,null,null,
                   grouping_id(cell) grp1,2 grp2
            FROM   r
            GROUP  BY "diskType",rollup(cell)
            ORDER  BY grp1,1,grp2, 2, 4;
    $ELSE
        OPEN c FOR
            WITH R AS(
                SELECT CELLNODE,NAME,"deviceName","diskType","physicalSize","status","luns","physicalFirmware","makeModel","physicalInsertTime","physicalSerial","slotNumber"
                FROM   EXA$PHYSICALDISK
                WHERE lower(cellnode) like lower('%'||V1||'%'))
            SELECT r.*,0 grp1,0 grp2 FROM R
            UNION ALL
            SELECT nvl(CELLNODE,'Total Cells: '||count(distinct CELLNODE)) cell,'--TOTAL--',
                   'Devices: '||count(distinct "deviceName"),
                   "diskType",
                   sum("physicalSize"),
                   max("status"),
                   'Luns:'||count(distinct "luns"),'Firmwares:'||count(distinct "physicalFirmware"),
                   null,null,null,null,
                   grouping_id(CELLNODE) grp1,2 grp2
            FROM   r
            GROUP  BY "diskType",rollup(CELLNODE)
            ORDER  BY grp1,1,grp2, 2, 4;
    $END
    :c := c;
END;
/
print c;