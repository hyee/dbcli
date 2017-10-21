/*[[Show cache info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb,ALLOC_REQUESTS format tmb
col block_size,kmg,availables,used format kmg
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
    WHERE lower(cell) like lower('%'||:V1||'%') 
    GROUP  BY NAME &cell
    ORDER BY NAME,2]],
    '|',{[[ /*grid={topic='Cache'}*/
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
        WHERE lower(cell) like lower('%'||:V1||'%') 
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
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY NAME &cell
        ORDER BY NAME,2]],
        '-',[[ /*grid={topic='Cache Block Stats'}*/
        SELECT siz block_size &cell,SUM(availables) availables,SUM(used) used,SUM(NetworkRead) NetworkRead,SUM(alloc_requests) alloc_requests,
               SUM(alloc_failures) alloc_failures,SUM(alloc_r_failures) alloc_r_failures,SUM(alloc_w_failures) alloc_w_failures
        FROM(
            SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="cache"]/blocksize_stat' passing xmltype(a.statistics_value) columns --
                            siz int path '@size', --
                            availables NUMBER path 'stat[@name="total_available_buffers"]*@size', --
                            used NUMBER path 'stat[@name="num_buffers_in_use"]*@size', --
                            NetworkRead NUMBER path 'stat[@name="NetworkRead"]', --
                            alloc_requests NUMBER path 'stat[@name="total_alloc_requests"]',
                            alloc_failures NUMBER path 'stat[@name="alloc_failures"]', --
                            alloc_r_failures NUMBER path 'stat[@name="block_write_alloc_failures"]', --
                            alloc_w_failures NUMBER path 'stat[@name="block_read_alloc_failures"]'--
                            ) b
            WHERE  statistics_type = 'CELL')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY ROLLUP((siz &cell))
        ORDER BY siz nulls first,2]],
        '-',{[[ /*grid={topic='Parameters'}*/
            SELECT NAME &cell,MIN(VALUE) MIN_VALUE,MAX(VALUE) MAX_VALUE
            FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                            FROM   v$cell_config c
                            WHERE  c.CELLNAME = a.CELL_NAME
                            AND    rownum < 2) cell,
                           b.*
                    FROM   v$cell_state a,
                           xmltable('//stats[@type="hardware dependent parameters"]/stat' passing xmltype(a.statistics_value) columns --
                                    NAME VARCHAR2(60) path '@name', --
                                    VALUE NUMBER path '.') b
                    WHERE  statistics_type = 'CELL')
            WHERE lower(cell) like lower('%'||:V1||'%') 
            GROUP BY NAME &cell
            ORDER BY NAME,2]],
            '+',[[ /*grid={topic='Cell IO'}*/
            SELECT NAME &cell,MIN(VALUE) MIN_VALUE,MAX(VALUE) MAX_VALUE
            FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                            FROM   v$cell_config c
                            WHERE  c.CELLNAME = a.CELL_NAME
                            AND    rownum < 2) cell,
                           b.*
                    FROM   v$cell_state a,
                           xmltable('//stats[@type="cell_io"]/stat' passing xmltype(a.statistics_value) columns --
                                    NAME VARCHAR2(60) path '@name', --
                                    VALUE NUMBER path '.') b
                    WHERE  statistics_type = 'CELL')
            WHERE lower(cell) like lower('%'||:V1||'%') 
            GROUP BY NAME &cell
            ORDER BY NAME,2]]
    }}
}