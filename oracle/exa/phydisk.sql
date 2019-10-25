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
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c FOR
            select * from(
                SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
                FROM   v$cell_config a,
                       XMLTABLE('/cli-output/physicaldisk' PASSING xmltype(a.confval) COLUMNS --
                                "name" VARCHAR2(20) path 'name',
                                "deviceId" NUMBER(5) path 'deviceId',
                                "deviceName" VARCHAR2(15) path 'deviceName',
                                "diskType" VARCHAR2(10) path 'diskType',
                                "enclosureDeviceId" NUMBER(5) path 'enclosureDeviceId',
                                "physicalSize" VARCHAR2(300) path 'physicalSize',
                                "errOtherCount" NUMBER(8) path 'errOtherCount',
                                "luns" VARCHAR2(10) path 'luns',
                                "makeModel" VARCHAR2(40) path 'makeModel',
                                "physicalFirmware" VARCHAR2(15) path 'physicalFirmware',
                                "physicalInsertTime" VARCHAR2(25) path 'physicalInsertTime',
                                "physicalInterface" VARCHAR2(10) path 'physicalInterface',
                                "physicalSerial" VARCHAR2(15) path 'physicalSerial',
                                "slotNumber" VARCHAR2(25) path 'slotNumber',
                                "status" VARCHAR2(15) path 'status') b
                WHERE  conftype = 'PHYSICALDISKS')
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER  BY 1, 2, 3;
    $ELSE
        OPEN c FOR
            SELECT CELLNODE,NAME,"status","physicalSize","deviceName","diskType","luns","makeModel","physicalFirmware","physicalInsertTime","physicalSerial","slotNumber"
            FROM   EXA$PHYSICALDISK
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2,3;
    $END
    :c := c;
END;
/
print c;