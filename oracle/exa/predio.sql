/*[[Show offload predicate io and storage index info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb format tmb
col kmg format kmg
col 1,2,4,8,32,64,128,256,512,1024,2048,4096,8192,16384 format tmb

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
            WHERE  statistics_type = 'PREDIO')
    WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
    GROUP BY NAME &cell
    ORDER BY NAME,2]],
    '|',{[[ /*grid={topic='Storage Index Stats'}*/
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
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        AND   VALUE>0
        GROUP BY NAME &cell
        ORDER BY NAME,2]],
        '-',[[ /*grid={topic='Storage Index Get Job Stats'}*/
        SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       b.*
                FROM   v$cell_state a,
                       xmltable('//SIGetJob_stats//stat' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                VALUE NUMBER path '.') b
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY NAME &cell
        ORDER BY NAME,2]],
        '-',[[ /*grid={topic='CPU ResourceManager Stats'}*/
        SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       b.*
                FROM   v$cell_state a,
                       xmltable('//CPUResourceManager_stats//stat' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                VALUE NUMBER path '.') b
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
        GROUP BY NAME &cell
        ORDER BY NAME,2]],
        '-',[[ /*grid={topic='Predicate IMC Pop Job Stats'}*/
        SELECT NAME &cell,SUM(VALUE) KMG,SUM(VALUE) TMB
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       b.*
                FROM   v$cell_state a,
                       xmltable('//PredicateIMCPopJob_stats//stat' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                VALUE NUMBER path '.') b
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%')  AND VALUE>0
        GROUP BY NAME &cell
        ORDER BY NAME,2]],},
    '-',[[/*grid={topic='Offload Predicate Histograms'}*/
    SELECT * FROM(
        SELECT name &cell,bucket#,SUM(value) value
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   c.name,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//histogram[@group="Predicate Histograms"]' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name', VALUE XMLTYPE PATH 'node()') c,
                   xmltable('//bucket' passing c.value columns --
                            BUCKET# VARCHAR2(50) path '@limit', VALUE NUMBER path '.') b
            WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY name &cell,bucket#)
    PIVOT(SUM(VALUE) FOR BUCKET# IN(1, 2, 4, 8, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384))
    ORDER  BY NAME
    ]]
}