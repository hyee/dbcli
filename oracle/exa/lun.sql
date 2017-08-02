/*[[cellcli list lun. Usage: @@NAME [<cell>]]]*/
set printsize 3000
select * from(
    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/lun' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(300) path 'name',
                    "deviceName" VARCHAR2(300) path 'deviceName',
                    "diskType" VARCHAR2(300) path 'diskType',
                    "id" VARCHAR2(300) path 'id',
                    "isSystemLun" VARCHAR2(300) path 'isSystemLun',
                    "lunSize" VARCHAR2(300) path 'lunSize',
                    "lunUID" VARCHAR2(300) path 'lunUID',
                    "physicalDrives" VARCHAR2(300) path 'physicalDrives',
                    "raidLevel" VARCHAR2(300) path 'raidLevel',
                    "lunWriteCacheMode" VARCHAR2(300) path 'lunWriteCacheMode',
                    "status" VARCHAR2(300) path 'status') b
    WHERE  conftype = 'LUNS')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER  BY 1, 2, 3;
