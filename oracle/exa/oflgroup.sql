/*[[cellcli list offload. Usage: @@NAME [<cell>]]]*/
set printsize 3000
COL CELLSRV|INPUT,CELLSRV|OUTPUT,CELLSRV|PASSTHRU,OFFLOAD|INPUT,OFFLOAD|OUTPUT,OFFLOAD|PASSTHRU,CPU|PASSTHRU,STORAGE_IDX|SAVED format kmg
col mesgs,replies,alloc_failures,send_failures,oal_errors,ocl_errors,OPEN|ATTEMPTS,OPEN|FAILURES,DISKS|TOTAL,CC|PCODE,CC|GBY,DISKS|HWM,IM|HITS,IM|POPS,IM|BYPASS,HCC|HITS,IM_HITS|NONHCC format tmb
grid {[[/*grid={topic='Offload Package'}*/
    with threads as(
           SELECT /*+materialize no_expand*/ cell_name cellname, group_name oflgrp_name, process_id pid, 
                  COUNT(case when (TRIM(SQL_ID) IS NOT NULL OR lower(WAIT_STATE) LIKE 'working%') then 1 end) aas
           FROM   v$cell_ofl_thread_history
           GROUP  BY cell_name, group_name, process_id)
    SELECT /*+ordered use_hash(a b c)*/
           cell, oflgrp_name, pid, ocl_group_id, PACKAGE, aas
    FROM   (SELECT CELLNAME, extractvalue(xmltype(a.confval), '/cli-output/context/@cell') cell, b.*
            FROM   v$cell_config_info a,
                   XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                            oflgrp_name VARCHAR2(300) path 'name',
                            PACKAGE VARCHAR2(300) path 'package') b
            WHERE  conftype = 'OFFLOAD') a
    LEFT JOIN (SELECT a.cell_name cellname, b.*
                 FROM   v$cell_state a,
                        xmltable('//stats[@type="offloadgroupdes"]' passing xmltype(a.statistics_value) columns --
                                 oflgrp_name VARCHAR2(50) path 'stat[@name="offload_group"]', --
                                 ocl_group_id NUMBER path 'stat[@name="ocl_group_id"]') b
                 WHERE  statistics_type = 'OFLGRPDES') b
    USING  (cellname, oflgrp_name)
    LEFT JOIN   threads c
    USING  (cellname, oflgrp_name)
    WHERE  lower(cell) LIKE lower('%' || :V1 || '%')
    ORDER  BY 1, package]],
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
    WITH names as  (
       SELECT DISTINCT cellname cell_name, b.*
       FROM   v$cell_config_info a,
              XMLTABLE('/cli-output/offloadgroup' PASSING xmltype(a.confval) COLUMNS --
                     offload_group VARCHAR2(300) path 'name',
                     PACKAGE VARCHAR2(300) path 'package') b
       WHERE  conftype = 'OFFLOAD'),
    cc AS (
       SELECT cell_name,
              b.*
       FROM   v$cell_state a,
              xmltable('/' passing xmltype(a.statistics_value) columns --
                     offload_group  VARCHAR2(50) path '//stat[@name="offload_group"]',
                     imcap NUMBER path '//stat[@name="columnar_cache_im_capacity_hits"]',--
                     imquery NUMBER path '//stat[@name="columnar_cache_im_query_hits"]',--
                     imncap NUMBER path '//stat[@name="columnar_cache_im_capacity_hits_nonehcc"]',--
                     imnquery NUMBER path '//stat[@name="columnar_cache_im_query_hits_nonehcc"]',--
                     hcc NUMBER path '//stat[@name="columnar_cache_hcc_hits"]',--
                     disks NUMBER path '//stat[@name="total_offload_disks"]',
                     imvgby NUMBER path '//stat[@name="columnar_cache_im_hit_vgbyapplied"]',
                     imbypass NUMBER path '//stat[@name="total_times_cc2_not_used_due_to_config"]',
                     imddl NUMBER path '//stat[@name="total_times_cc2_not_used_due_to_ddl"]',
                     impcode NUMBER path '//stat[@name="columnar_cache_im_hit_pcodeapplied"]',
                     hccpcode NUMBER path '//stat[@name="columnar_cache_hcc_hit_pcodeapplied"]',
                     hccvgby NUMBER path '//stat[@name="columnar_cache_hcc_hit_vgbyapplied"]',
                     disk_hwm NUMBER path '//stat[@name="hwm_offload_disks"]'
                     ) b
       WHERE  statistics_type = 'OFLGROUP'    
    )
    SELECT /*+ordered use_hash(a b c) swap_join_inputs(b)*/
           nvl(offload_group,'--TOTAL--') offload_group,PACKAGE, 
           SUM(ofl_input) "OFFLOAD|INPUT",SUM(ofl_output) "OFFLOAD|OUTPUT",SUM(ofl_passthru) "OFFLOAD|PASSTHRU",
           SUM(cpu_passthru) "CPU|PASSTHRU",SUM(storage_idx_saved) "STORAGE_IDX|SAVED",
           '|' "|",
           sum(disks) "DISKS|TOTAL",
           sum(disk_hwm) "DISKS|HWM",
           sum(hcc)  "HCC|HITS",
           sum(imcap)+sum(imquery) "IM|HITS",
           sum(imncap)+sum(imnquery) "IM_HITS|NONHCC",
           SUM(imc_population) "IM|POPS",
           sum(imbypass)+sum(imddl) "IM|BYPASS",
           nvl(SUM(impcode),0)+nvl(sum(hccpcode),0) "CC|PCODE",
           nvl(SUM(imvgby),0)+nvl(sum(hccvgby),0) "CC|GBY",
           '|' "|",
           SUM(attempts) "OPEN|ATTEMPTS",SUM(failures) "OPEN|FAILURES"
           ,SUM(cellsrv_input) "CELLSRV|INPUT",SUM(cellsrv_output) "CELLSRV|OUTPUT",SUM(cellsrv_passthru) "CELLSRV|PASSTHRU"
    FROM ( SELECT   cell_name,
                    b.*
            FROM   v$cell_state a,
                   xmltable('/' passing xmltype(a.statistics_value) columns --
                            offload_group  VARCHAR2(50) path 'stat[@name="offload_group"]',
                            attempts NUMBER path '//stat[@name="num_oflgrp_open_attempts"]',--
                            failures NUMBER path '//stat[@name="num_oflgrp_open_failures"]',--
                            cellsrv_input NUMBER path '//stat[@name="cellsrv_total_input_bytes"]',--
                            cellsrv_output NUMBER path '//stat[@name="cellsrv_total_output_bytes"]',--
                            cellsrv_passthru NUMBER path '//stat[@name="cellsrv_passthru_output_bytes"]',--
                            ofl_input NUMBER path '//stat[@name="celloflsrv_total_input_bytes"]',--
                            ofl_output NUMBER path '//stat[@name="celloflsrv_total_output_bytes"]',--
                            ofl_passthru NUMBER path '//stat[@name="celloflsrv_passthru_output_bytes"]',--
                            cpu_passthru NUMBER path '//stat[@name="cpu_passthru_output_bytes"]',--
                            storage_idx_saved NUMBER path '//stat[@name="storage_idx_saved_bytes"]',--
                            imc_population NUMBER path '//stats[stat="imc_population"]/stat[@name="num_mesgs"]') b
            WHERE  statistics_type = 'OFLGRPDES') a
    JOIN  names b USING (cell_name,offload_group)
    JOIN cc USING (cell_name,offload_group)
    WHERE lower(cell_name) like lower('%'||:V1||'%')
    GROUP BY rollup((offload_group,PACKAGE))
    ORDER BY 1,2]]
}