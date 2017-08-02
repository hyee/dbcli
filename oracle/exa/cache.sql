/*[[Show cache info. Usage @@NAME [-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb format tmb
col kmg format kmg
grid {[[ /*grid={topic='Flash Cache'}*/
    SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="columnarcache"]/stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name',
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'CELL')
    GROUP  BY NAME &cell
    ORDER BY NAME,2]],
    '|',[[ /*grid={topic='Cache'}*/
    SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="cache"]/stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name', 
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'CELL')
    GROUP  BY NAME &cell
    ORDER BY NAME,2]],
    '|',[[ /*grid={topic='Mem cache'}*/
    SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="MemCache"]/stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name', 
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'CELL')
    GROUP  BY NAME &cell
    ORDER BY NAME,2]]
}