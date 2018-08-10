/*[[Show OS memory info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={cell,}
    --]]
]]*/
col osmem format kmg
col allocated format kmg
grid {[[ /*grid={topic='cellsrv_mem_stats'}*/
    SELECT &cell NVL(memtype,'--TOTAL--') memtype ,SUM(osmem) osmem,SUM(allocated) allocated
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*
            FROM   v$cell_state a,
                   xmltable('//cellsrv_memory_stats/cellsrv_memtype_stats' passing xmltype(a.statistics_value) columns --
                            memtype VARCHAR2(50) path 'stat[@name="memtype"]',--
                            osmem INT path 'stat[@name="cellsrv_osmem"]',
                            allocated INT path 'stat[@name="cellsrv_allocmem"]') b
            WHERE  statistics_type = 'CELL')
    WHERE lower(cell) like lower('%'||:V1||'%')
    GROUP  BY cube(&cell memtype )
    ORDER BY 1,2]],
    '|',[[ /*grid={topic='group_mem_stats'}*/
    SELECT nvl(PACKAGE,'--ALL--') package, &cell NVL(memtype, '--TOTAL--') memtype, SUM(osmem) osmem, SUM(allocated) allocated
    FROM   (SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell, cellname cell_name, b.*
            FROM   v$cell_config_info a,
                   XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                            groupName VARCHAR2(300) path 'name',
                            PACKAGE VARCHAR2(300) path 'package') b
            WHERE  conftype = 'OFFLOAD')
    JOIN   (SELECT a.cell_name, d.groupname, b.*
            FROM   v$cell_state a,
                   xmltable('//group_mem_stats[stat[@name="group_name"] ]' passing xmltype(a.statistics_value) columns --
                            groupName PATH 'stat[@name="group_name"][1]',
                            val XMLTYPE PATH 'node()') d,
                   xmltable('//group_memtype_stats' passing d.val columns --
                            memtype VARCHAR2(50) path 'stat[@name="memtype"]', --
                            osmem INT path 'stat[@name="group_osmem"]',
                            allocated INT path 'stat[@name="group_allocmem"]') b
            WHERE  statistics_type = 'CELL')
    USING  (cell_name, groupName)
    WHERE  lower(cell) LIKE lower('%' || :V1 || '%')
    GROUP  BY rollup(PACKAGE, &cell memtype)
    ORDER BY 1,2,3]],
}