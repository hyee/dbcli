/*[[Show offload clients. Usage: @@NAME [<cell>|<client>]|[-d]
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/

col cell_input format kmg
col cell_output format kmg
col cell_passthru_output format kmg
col ofl_input format kmg
col ofl_output format kmg
col ofl_passthru_output format kmg
col cpu_passthru_output format kmg
col storage_idx_saved format kmg
col mesgs,replies format tmb
grid {[[ /*grid={topic='Offload Clients'}*/
    SELECT nvl(ofl_client,'+-TOTAL-+') ofl_client &cell,
           SUM(total_input) cell_input,
           SUM(total_output) cell_output,
           SUM(passthru_output) cell_passthru_output,
           SUM(ofl_total_input) ofl_input,
           SUM(ofl_total_output) ofl_output,
           SUM(ofl_passthru_output) ofl_passthru_output,
           SUM(cpu_passthru_output) cpu_passthru_output,
           SUM(storage_idx_saved) storage_idx_saved
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                    b.*,
                    '['||ofl_source||'] '||client_name ofl_client
            FROM   v$cell_state a,
                   xmltable('/' passing xmltype(a.statistics_value) columns --
                            client_name VARCHAR2(50) path '//stat[@name="client_name"]', --
                            ofl_source VARCHAR2(50) path '//stat[@name="offload_version_source"]', --
                            total_input NUMBER path '//stat[@name="cellsrv_total_input_bytes"]',--
                            total_output NUMBER path '//stat[@name="cellsrv_total_output_bytes"]',--
                            passthru_output NUMBER path '//stat[@name="cellsrv_passthru_output_bytes"]',--
                            ofl_total_input NUMBER path '//stat[@name="celloflsrv_total_input_bytes"]',--
                            ofl_total_output NUMBER path '//stat[@name="celloflsrv_total_output_bytes"]',--
                            ofl_passthru_output NUMBER path '//stat[@name="celloflsrv_passthru_output_bytes"]',--
                            cpu_passthru_output NUMBER path '//stat[@name="cpu_passthru_output_bytes"]',--
                            storage_idx_saved NUMBER path '//stat[@name="storage_idx_saved_bytes"]'
                            ) b
            WHERE  statistics_type = 'CLIENTDES')
    WHERE lower(cell) like lower('%'||:V1||'%')  or lower(client_name) like lower('%'||:V1||'%') 
    GROUP  BY ROLLUP(ofl_client &cell)
    HAVING SUM(total_input)>0 or SUM(ofl_total_input)>0
    ORDER BY ofl_client,2
    ]],'-',[[/*grid={topic='Offload Client Messages'}*/
    SELECT mesg_type,
           SUM(mesgs) mesgs,
           SUM(replies) replies,
           SUM(alloc_failures) alloc_failures,
           SUM(send_failures) send_failures,
           SUM(oal_error_replies) oal_error_replies,
           SUM(ocl_error_replies) ocl_error_replies
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   b.*,
                   EXTRACTVALUE(xmltype(a.statistics_value), '/stats/stat[@name="client_name"][1]') client_name
            FROM   v$cell_state a,
                   xmltable('//stats[@type="oal_msg"]' passing xmltype(a.statistics_value) columns --
                            mesg_type VARCHAR2(50) path 'stat[@name="mesg_type"]',
                            mesgs NUMBER path 'stat[@name="num_mesgs"]',
                            replies NUMBER path 'stat[@name="num_replies"]',
                            alloc_failures NUMBER path 'stat[@name="num_alloc_failures"]',
                            send_failures NUMBER path 'stat[@name="num_send_failures"]',
                            oal_error_replies NUMBER path 'stat[@name="num_oal_error_replies"]',
                            ocl_error_replies NUMBER path 'stat[@name="num_ocl_error_replies"]') b
            WHERE  statistics_type = 'CLIENTDES')
    WHERE lower(cell) like lower('%'||:V1||'%') or lower(client_name) like lower('%'||:V1||'%') 
    GROUP  BY mesg_type
    ]]
}