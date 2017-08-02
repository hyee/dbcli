/*[[cellcli list physicaldisk. Usage: @@NAME [<cell>]]]*/
set printsize 3000
col physicalSize format kmg
select * from(
    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/physicaldisk' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(300) path 'name',
                    "deviceId" VARCHAR2(300) path 'deviceId',
                    "deviceName" VARCHAR2(300) path 'deviceName',
                    "diskType" VARCHAR2(300) path 'diskType',
                    "enclosureDeviceId" VARCHAR2(300) path 'enclosureDeviceId',
                    "physicalSize" VARCHAR2(300) path 'physicalSize',
                    "errOtherCount" VARCHAR2(300) path 'errOtherCount',
                    "luns" VARCHAR2(300) path 'luns',
                    "makeModel" VARCHAR2(300) path 'makeModel',
                    "physicalFirmware" VARCHAR2(300) path 'physicalFirmware',
                    "physicalInsertTime" VARCHAR2(300) path 'physicalInsertTime',
                    "physicalInterface" VARCHAR2(300) path 'physicalInterface',
                    "physicalSerial" VARCHAR2(300) path 'physicalSerial',
                    "slotNumber" VARCHAR2(300) path 'slotNumber',
                    "status" VARCHAR2(300) path 'status') b
    WHERE  conftype = 'PHYSICALDISKS')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER  BY 1, 2, 3
