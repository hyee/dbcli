SET PAGES 999 ARRAYSIZE 50
select * from(
    SELECT CAST(extractvalue(xmltype(a.confval),'/cli-output/context/@cell') AS VARCHAR2(20)) cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/physicaldisk' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(20) path 'name',
                    "deviceId" NUMBER(5) path 'deviceId',
                    "deviceName" VARCHAR2(15) path 'deviceName',
                    "diskType" VARCHAR2(10) path 'diskType',
                    "enclosureDeviceId" NUMBER(5) path 'enclosureDeviceId',
                    "SizeGB" NUMBER(8) path 'round(physicalSize div 1073741824)',
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
ORDER  BY 1, 2, 3;
