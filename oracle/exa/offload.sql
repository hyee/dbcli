/*[[cellcli list offload. Usage: @@NAME [<cell>]]]*/
set printsize 3000
COL cellsrv_input,cellsrv_output,cellsrv_passthru,ofl_input,ofl_output,ofl_passthru,cpu_passthru,storage_idx_saved format kmg
col mesgs,replies,alloc_failures,send_failures,oal_errors,ocl_errors format tmb
grid {[[/*grid={topic='Offload Package'}*/
    select * from(
        SELECT extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell,
               b.*
        FROM   v$cell_config_info a,
               XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                        name VARCHAR2(300) path 'name',
                        package VARCHAR2(300) path 'package'
                        ) b
        WHERE  conftype = 'OFFLOAD')
    WHERE lower(cell) like lower('%'||:V1||'%')
    ORDER BY 1,2,3]],
    '|',[[/*grid={topic='Offload Messages'}*/
    SELECT nvl(mesg_type,'--TOTAL--') mesg_type,sum(mesgs) mesgs,sum(replies) replies,sum(alloc_failures) alloc_failures,sum(send_failures) send_failures,sum(oal_errors) oal_errors,sum(ocl_errors) ocl_errors
    FROM ( SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="offload_mesg_stats"]/stats' passing xmltype(a.statistics_value) columns --
                            mesg_type VARCHAR2(50) path 'stat[@name="mesg_type"]', --
                            mesgs NUMBER path 'stat[@name="num_mesgs"]', --
                            replies NUMBER path 'stat[@name="num_replies"]', --
                            alloc_failures NUMBER path 'stat[@name="num_alloc_failures"]', --
                            send_failures NUMBER path 'stat[@name="num_send_failures"]', --
                            oal_errors NUMBER path 'stat[@name="num_oal_error_replies"]', --
                            ocl_errors NUMBER path 'stat[@name="num_ocl_error_replies"]') b
            WHERE  statistics_type = 'OFLGRPDES') 
    WHERE lower(cell) like lower('%'||:V1||'%')
    GROUP BY rollup(mesg_type)
    ORDER BY 1,2]],
    '-',[[/*grid={topic='Throughput'}*/
    SELECT nvl(CELL,'--TOTAL--') cell,SUM(cellsrv_input) cellsrv_input,SUM(cellsrv_output) cellsrv_output,SUM(cellsrv_passthru) cellsrv_passthru,
           SUM(ofl_input) ofl_input,SUM(ofl_output) ofl_output,SUM(ofl_passthru) ofl_passthru,SUM(cpu_passthru) cpu_passthru,SUM(storage_idx_saved) storage_idx_saved
    FROM ( SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*
            FROM   v$cell_state a,
                   xmltable('/' passing xmltype(a.statistics_value) columns --
                            cellsrv_input NUMBER path '//stat[@name="cellsrv_total_input_bytes"]',--
                            cellsrv_output NUMBER path '//stat[@name="cellsrv_total_output_bytes"]',--
                            cellsrv_passthru NUMBER path '//stat[@name="cellsrv_passthru_output_bytes"]',--
                            ofl_input NUMBER path '//stat[@name="celloflsrv_total_input_bytes"]',--
                            ofl_output NUMBER path '//stat[@name="celloflsrv_total_output_bytes"]',--
                            ofl_passthru NUMBER path '//stat[@name="celloflsrv_passthru_output_bytes"]',--
                            cpu_passthru NUMBER path '//stat[@name="cpu_passthru_output_bytes"]',--
                            storage_idx_saved NUMBER path '//stat[@name="storage_idx_saved_bytes"]'
                            ) b
            WHERE  statistics_type = 'OFLGRPDES')
    WHERE lower(cell) like lower('%'||:V1||'%')
    GROUP BY rollup(CELL)
    ORDER BY 1,2]]
}