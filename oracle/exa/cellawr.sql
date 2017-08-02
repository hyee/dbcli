col effFlashCacheSize format kmg
col effFlashLogSize format kmg

SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell, b.*
FROM   v$cell_config_info a,
       XMLTABLE('/cli-output/not-set' PASSING xmltype(a.confval) COLUMNS --
                "effFlashCacheSize" INT path 'effectiveFlashCacheSize',
                "effFlashLogSize" INT path 'effectiveFlashLogSize',
                "numGridDisks" INT path 'numGridDisks',
                "numCellDisks" INT path 'numCellDisks',
                "numHardDisks" INT path 'numHardDisks',
                "numFlashDisks" INT path 'numFlashDisks',
                "maxPDIOPS" INT path 'maxPDIOPS',
                "maxFDIOPS" INT path 'maxFDIOPS',
                "maxPDMBPS" INT path 'maxPDMBPS',
                "maxFDMBPS" INT path 'maxFDMBPS',
                "dwhPDQL" INT path 'dwhPDQL',
                "dwhFDQL" INT path 'dwhFDQL',
                "oltpPDQL" INT path 'oltpPDQL',
                "oltpFDQL" INT path 'oltpFDQL',
                "hardDiskType" VARCHAR2(300) path 'hardDiskType',
                "flashDiskType" VARCHAR2(300) path 'flashDiskType',
                "flashCacheStatus" VARCHAR2(300) path 'flashCacheStatus',
                "cellPkg" VARCHAR2(300) path 'cellPkg') b
WHERE  conftype = 'AWRXML'
order by 1
