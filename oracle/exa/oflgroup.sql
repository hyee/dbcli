/*[[Show offload predicate io and storage index info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb format tmb
col kmg format kmg
grid {[[ /*grid={topic='Predicate I/O'}*/
    SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="predicateio"]/stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name',
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'OFLGROUP')
    WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
    GROUP BY NAME &cell
    ORDER BY NAME,2]],
    '|',[[ /*grid={topic='Storage Index Stats'}*/
    SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="storidx_global_stats"]//stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name',
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'OFLGROUP')
    WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
    GROUP BY NAME &cell
    ORDER BY NAME,2]]
}