/*[[Show phase stats]]*/
col elapsed,avg_ela for usmhd2
col total_count,traverse_count,miss_count for tmb
col pct for pct2

SELECT NAME,
       SUM(elapsed) elapsed,
       ratio_to_report(sum(elapsed)) over() pct,
       round(SUM(elapsed) / nullif(SUM(total_count), 0),2) avg_ela,
       round(SUM(total_count)) total_count,
       SUM(traverse_count) traverse_count,
       SUM(miss_count) miss_count
FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                FROM   v$cell_config c
                WHERE  c.CELLNAME = a.CELL_NAME
                AND    rownum < 2) cell,
               b.*,
               elapsed / nullif(av, 0) total_count
        FROM   v$cell_state a,
               xmltable('//phase_stat' passing xmltype(a.statistics_value) columns --
                        NAME VARCHAR2(50) path '@name',
                        elapsed NUMBER path 'stat[@name="elapsed"]',
                        av NUMBER path 'stat[@name="avg"]',
                        traverse_count NUMBER path 'stat[@name="phase_traverse_count"]',
                        miss_count NUMBER path 'stat[@name="phase_miss_count"]') b
        WHERE  statistics_type = 'PHASESTAT')
GROUP  BY NAME
having sum(elapsed)>0
order by 2 desc;