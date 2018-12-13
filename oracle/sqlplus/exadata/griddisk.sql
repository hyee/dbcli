SET PAGES 999 ARRAYSIZE 50
select * from(
    SELECT cast(extractvalue(xmltype(a.confval),'/cli-output/context/@cell') as varchar2(20)) cell, b.*
    FROM   v$cell_config a,
           XMLTABLE('/cli-output/griddisk' PASSING xmltype(a.confval) COLUMNS --
                    "cellDisk" VARCHAR2(25) path 'cellDisk',
                    "name" VARCHAR2(50) path 'name',
                    "diskType" VARCHAR2(10) path 'diskType',
                    "offsetGB" NUMBER(8) path 'round(offset div 1073741824)',
                    "sizeGB" NUMBER(8) path 'round(size div 1073741824)',
                    "status" VARCHAR2(15) path 'status',
                    "errorCount" NUMBER(8) path 'errorCount',
                    "asmDiskGroupName" VARCHAR2(30) path 'asmDiskGroupName',
                    "asmDiskName" VARCHAR2(50) path 'asmDiskName',
                    "asmFailGroupName" VARCHAR2(30) path 'asmFailGroupName',
                    "availableTo" VARCHAR2(30) path 'availableTo',
                    "cachedBy" VARCHAR2(100) path 'cachedBy',
                    "cachingPolicy" VARCHAR2(10) path 'cachingPolicy',
                    "creationTime" VARCHAR2(25) path 'creationTime',
                    "id" VARCHAR2(60) path 'id') b
    WHERE  conftype = 'GRIDDISKS')
ORDER  BY 1, "cellDisk", "offsetGB";