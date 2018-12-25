/*[[cellcli list celldisk. Usage: @@NAME [<cell>]]]*/
set printsize 3000
col size format kmg
col freeSpace format kmg
select * from(
    SELECT cast(extractvalue(xmltype(a.confval),'/cli-output/context/@cell') as varchar2(20)) cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('//celldisk' PASSING xmltype(a.confval) COLUMNS --
                    "name" VARCHAR2(30) path 'name',
                    "Size" INT path 'size',
                    "freeSpace" INT path 'freeSpace',
                    "creationTime" VARCHAR2(25) path 'creationTime',
                    "deviceName" VARCHAR2(15) path 'deviceName',
                    "devicePartition" VARCHAR2(18) path 'devicePartition',
                    "diskType" VARCHAR2(10) path 'diskType',
                    "lun" VARCHAR2(10) path 'lun',
                    "errorCount" number(8) path 'errorCount',
                    "id" VARCHAR2(60) path 'id',
                    "interleaving" VARCHAR2(10) path 'interleaving',
                    "physicalDisk" VARCHAR2(20) path 'physicalDisk',
                    "raidLevel" VARCHAR2(10) path 'raidLevel',
                    "status" VARCHAR2(15) path 'status') b
    WHERE  conftype = 'CELLDISKS')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER BY 1,2,3