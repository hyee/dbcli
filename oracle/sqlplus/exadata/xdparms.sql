SELECT NAME,MIN(VALUE) MIN_VALUE,MAX(VALUE) MAX_VALUE
FROM   (SELECT (SELECT cast(extractvalue(xmltype(c.confval), '/cli-output/context/@cell') as varchar2(20))
                FROM   v$cell_config c
                WHERE  c.CELLNAME = a.CELL_NAME
                AND    rownum < 2) cell,
               b.*
        FROM   v$cell_state a,
               xmltable('//stats[@type="hardware dependent parameters"]/stat' passing xmltype(a.statistics_value) columns --
                        NAME VARCHAR2(50) path '@name', --
                        VALUE NUMBER path '.') b
        WHERE  statistics_type = 'CELL')
GROUP BY NAME
ORDER BY NAME,2;