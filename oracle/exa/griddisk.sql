/*[[cellcli list griddisk. Usage: @@NAME [<cell>|<diskgroup>|<celldisk>] [-cli]
    -cli: Show the info of EXA$GRIDDISK instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$GRIDDISK={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col size,offset for kmg
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN C FOR
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
            WHERE nvl(lower(v1),' ') in(' ',lower(cell),lower("asmDiskGroupName"),lower("cellDisk"))
            ORDER  BY 1, "cellDisk", "offset";
    $ELSE
        OPEN c FOR
            SELECT CELLNODE,NAME,"status","size","diskType","errorCount","asmDiskGroupName","asmDiskName","asmFailGroupName","availableTo","cachedBy","cachingPolicy","cellDisk","comment","creationTime","id"
            FROM   EXA$GRIDDISK
            WHERE nvl(lower(v1),' ') in(' ',lower(cellnode),lower("asmDiskGroupName"),lower("cellDisk"))
            ORDER BY 1,2,3;
    $END
    :c := c;
END;
/
print c;