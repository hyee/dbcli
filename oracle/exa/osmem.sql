/*[[Show OS memory info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col osmem format kmg
col allocated format kmg
grid {[[ /*grid={topic='cellsrv_mem_stats'}*/
    SELECT NVL(memtype,'--TOTAL--') memtype &cell,SUM(osmem) osmem,SUM(allocated) allocated
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
    GROUP  BY ROLLUP((memtype &cell))
    ORDER BY memtype,2]],
    '|',[[ /*grid={topic='group_mem_stats'}*/
    SELECT NVL(memtype,'--TOTAL--') memtype &cell,SUM(osmem) osmem,SUM(allocated) allocated
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*
            FROM   v$cell_state a,
                   xmltable('//group_mem_stats/group_memtype_stats' passing xmltype(a.statistics_value) columns --
                            memtype VARCHAR2(50) path 'stat[@name="memtype"]',--
                            osmem INT path 'stat[@name="group_osmem"]',
                            allocated INT path 'stat[@name="group_allocmem"]') b
            WHERE  statistics_type = 'CELL')
    WHERE lower(cell) like lower('%'||:V1||'%')
    GROUP  BY ROLLUP((memtype &cell))
    ORDER BY memtype,2]],
}