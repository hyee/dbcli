/*[[cellcli list griddisk. Usage: @@NAME [<cell>]]]*/
set printsize 3000
col size format kmg
col offset format kmg
select * from(
    SELECT extractvalue(xmltype(a.confval),'/cli-output/context/@cell') cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/griddisk' PASSING xmltype(a.confval) COLUMNS --
                    "cellDisk" VARCHAR2(300) path 'cellDisk',
                    "name" VARCHAR2(300) path 'name',
                    "diskType" VARCHAR2(300) path 'diskType',
                    "offset" INT path 'offset',
                    "size" INT path 'size',
                    "status" VARCHAR2(300) path 'status',
                    "errorCount" VARCHAR2(300) path 'errorCount',
                    "asmDiskGroupName" VARCHAR2(300) path 'asmDiskGroupName',
                    "asmDiskName" VARCHAR2(300) path 'asmDiskName',
                    "asmFailGroupName" VARCHAR2(300) path 'asmFailGroupName',
                    "availableTo" VARCHAR2(300) path 'availableTo',
                    "cachedBy" VARCHAR2(300) path 'cachedBy',
                    "cachingPolicy" VARCHAR2(300) path 'cachingPolicy',
                    "creationTime" VARCHAR2(300) path 'creationTime',
                    "id" VARCHAR2(300) path 'id') b
    WHERE  conftype = 'GRIDDISKS')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER  BY 1, "cellDisk", "offset";
