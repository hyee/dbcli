/*[[
    show lun info. Usage: @@NAME [<cell>] [-cli]
    -cli: show the info of EXA$LUN instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$LUN={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
col lunsize for kmg
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c FOR
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
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER  BY 1, 2, 3;
    $ELSE
        OPEN c FOR
            SELECT * 
            FROM EXA$LUN
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2,3;
    $END
    :c := c;
END;
/
print c;