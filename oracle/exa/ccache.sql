SELECT NAME &cell,SUM(VALUE) VALUE
FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                FROM   v$cell_config c
                WHERE  c.CELLNAME = a.CELL_NAME
                AND    rownum < 2) cell,
               b.*
        FROM   v$cell_state a,
               xmltable('//stats[@type="columnarcache"]/stat' passing xmltype(a.statistics_value) columns --
                        NAME VARCHAR2(50) path '@name',
                        VALUE NUMBER path '.') b
        WHERE  b.value <> 0
        AND    statistics_type = 'CELL')
GROUP  BY NAME &cell