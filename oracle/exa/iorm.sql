/*[[cellcli list iormplan. Usage: @@NAME [<cell>]  [-cli]
    -cli: show the info of EXA$DATABASE instead of fetching info from V$CELL_CONFIG
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_config={1} EXA$DATABASE={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/
set printsize 3000 feed off verify off
var c refcursor
DECLARE
    c SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c FOR
            select * from(
                SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell,
                       REPLACE(nvl2(b.catPlan, b.catPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<') catPlan,
                       REPLACE(nvl2(b.dbPlan, b.dbPlan.getstringval(), NULL), '/><', '/>' || CHR(10) || '<') dbPlan,
                       b.objective,
                       b.status
                FROM   v$cell_config a,
                       XMLTABLE('/cli-output/iormplan' PASSING xmltype(a.confval) COLUMNS --
                                catPlan XMLTYPE path 'catPlan/node()',
                                dbPlan XMLTYPE path 'dbPlan/node()',
                                objective VARCHAR2(300) path 'objective',
                                status VARCHAR2(300) path 'status') b
                WHERE  conftype = 'IORM')
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER BY 1,2,3
    $ELSE
        OPEN c FOR
            SELECT * 
            FROM  EXA$DATABASE
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2,3;
    $END
    :c := c;
END;
/
print c;