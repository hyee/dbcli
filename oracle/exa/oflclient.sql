/*[[Show offload clients. Usage: @@NAME [<cell>]|[-d]
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
grid {[[ /*grid={topic='Offload Clients'}*/
    SELECT nvl(client_name,'+-TOTAL-+') client_name &cell,
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
                    b.*
            FROM   v$cell_state a,
                   xmltable('/' passing xmltype(a.statistics_value) columns --
                            client_name VARCHAR2(50) path '//stat[@name="client_name"]', --
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
    WHERE lower(cell) like lower('%'||:V1||'%')
    GROUP  BY ROLLUP(client_name &cell)
    ORDER BY client_name,2]]
}