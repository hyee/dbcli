/*[[Show offload predicate io and storage index info. Usage: @@NAME [<cell>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb,CNT format tmb
col kmg format kmg
col "1 KB,2 KB,4 KB,8 KB,32 KB,64 KB,128 KB,256 KB,512 KB,1 MB,2 MB,4 MB,8 MB,16 MB" format tmb

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
        '|',[[ /*grid={topic='Storage Index Get Job Stats'}*/
        SELECT NAME &cell,SUM(VALUE) CNT
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
        '-',{[[/*grid={topic='OCL RH Stats'}*/
        SELECT NAME &cell,SUM(VALUE) CNT
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       b.*
                FROM   v$cell_state a,
                       xmltable('//ocl_rh_stats/stat' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                VALUE NUMBER path '.') b
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY NAME &cell
        ORDER BY NAME,2   
        ]],'|',[[/*grid={topic='Copy From Remote Stats'}*/
        SELECT NAME &cell,SUM(VALUE) CNT
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       b.*
                FROM   v$cell_state a,
                       xmltable('//*[local-name()="copyFromRemote_stats" or local-name()="copySIFromRemote_stats"]/stat' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                VALUE NUMBER path '.') b
                WHERE  statistics_type = 'PREDIO')
        WHERE lower(cell) like lower('%'||:V1||'%') 
        GROUP BY NAME &cell
        ORDER BY NAME,2   
        ]]},
        '-',{[[ /*grid={topic='Predicate IMC Pop Job Stats'}*/
        SELECT NAME &cell,SUM(VALUE) CNT
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
        ORDER BY NAME,2]],
        '|',[[ /*grid={topic='CPU ResourceManager Stats'}*/
        SELECT NAME &cell,SUM(VALUE) CNT
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
        },
        '-',[[ /*grid={topic='Predicate No-opt Reasons'}*/
        SELECT /*+no_expand*/ type,category,NAME &cell,SUM(VALUE) CNT
        FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                        FROM   v$cell_config c
                        WHERE  c.CELLNAME = a.CELL_NAME
                        AND    rownum < 2) cell,
                       statistics_type||decode(statistics_type,
                            'CLIENTDES','-'||extractvalue(xmltype(a.statistics_value),'//stat[@name="client_name"][1]'),
                            'OFLGROUP','-'||extractvalue(xmltype(a.statistics_value),'//stat[@name="offload_group"][1]')) type,
                       replace(b.name,'Smart ') category,
                       c.name,
                       nvl(c.value,extractvalue(b.stats,'text()')+0) value
                FROM   v$cell_state a,
                       xmltable('//stats[@type="ofl_nonopt_reasons"]/noopt_reasons' passing xmltype(a.statistics_value) columns --
                                NAME VARCHAR2(50) path '@name',
                                stats XMLTYPE path 'node()') b,
                       xmltable('stat' passing b.stats columns --
                                NAME VARCHAR2(300) path '@name',
                                VALUE NUMBER path '.')(+) c
                WHERE  statistics_type IN('PREDIO','CLIENTDES','OFLGROUP'))
        WHERE lower(cell) like lower('%'||:V1||'%') AND (value>0 or type='PREDIO')
        GROUP BY type,category,NAME &cell
        ORDER BY NAME,type,CNT DESC]],
    },'-',[[/*grid={topic='Offload Predicate Bucket Histograms'}*/
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
    PIVOT(SUM(VALUE) FOR BUCKET# IN(1 "1 KB",2 "2 KB",4 "4 KB",8 "8 KB",32 "32 KB",64 "64 KB",128 "128 KB",256 "256 KB",512 "512 KB", 1024 "1 MB", 2048 "2 MB", 4096 "4 MB", 8192 "8 MB", 16384 "16 MB"))
    ORDER  BY NAME
    ]]
}