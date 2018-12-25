SET PAGES 999 ARRAYSIZE 50
select * from(
    SELECT cast(extractvalue(xmltype(a.confval),'/cli-output/context/@cell') as varchar2(20)) cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/lun' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(10) path 'name',
                    "deviceName" VARCHAR2(15) path 'deviceName',
                    "diskType" VARCHAR2(10) path 'diskType',
                    "id" VARCHAR2(10) path 'id',
                    "isSystemLun" VARCHAR2(7) path 'isSystemLun',
                    "lunSize" NUMBER(8) path 'round(lunSize div 1073741824)',
                    "lunUID" VARCHAR2(10) path 'lunUID',
                    "physicalDrives" VARCHAR2(20) path 'physicalDrives',
                    "raidLevel" VARCHAR(10) path 'raidLevel', 
                    "lunWriteCacheMode" VARCHAR2(70) path 'lunWriteCacheMode',
                    "status" VARCHAR2(15) path 'status') b
    WHERE  conftype = 'LUNS')
ORDER  BY 1, 2, 3;