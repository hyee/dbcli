/*[[cellcli list celldisk. Usage: @@NAME [<cell>][-cli]
    -cli: Show the info of EXA$CELLDISK instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$CELLDISK={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col size,freeSpace for kmg
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c FOR
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
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER BY 1,2,3;
    $ELSE
        OPEN c FOR
            SELECT CELLNODE,NAME,"status","size","freeSpace","errorCount","diskType","creationTime","deviceName","devicePartition","id","physicalDisk","comment"
            FROM   EXA$CELLDISK
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2,3;
    $END
    :c := c;
END;
/
print c;