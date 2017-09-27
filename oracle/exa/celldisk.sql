/*[[cellcli list celldisk. Usage: @@NAME [<cell>]]]*/
set printsize 3000
col size format kmg
col freeSpace format kmg
select * from(
    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(300) path 'name',
                    "size" INT path 'size',
                    "freeSpace" INT path 'freeSpace',
                    "creationTime" VARCHAR2(300) path 'creationTime',
                    "deviceName" VARCHAR2(300) path 'deviceName',
                    "devicePartition" VARCHAR2(300) path 'devicePartition',
                    "diskType" VARCHAR2(300) path 'diskType',
                    "lun" VARCHAR2(300) path 'lun',
                    "errorCount" VARCHAR2(300) path 'errorCount',
                    "id" VARCHAR2(300) path 'id',
                    "interleaving" VARCHAR2(300) path 'interleaving',
                    "physicalDisk" VARCHAR2(300) path 'physicalDisk',
                    "raidLevel" VARCHAR2(300) path 'raidLevel',
                    "status" VARCHAR2(300) path 'status') b
    WHERE  conftype = 'CELLDISKS')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER BY 1,2,3