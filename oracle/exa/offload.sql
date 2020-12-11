/*[[Show offload predicate io and storage index info,type 'help @@NAME' for more information. Usage: @@NAME [<cell>]|[-d]

How to setup Columnar Cache 
===========================
    Using DDL to enable certain CC format on a given table (12.2): 
        alter table table_1 no cellmemory; --- CC1 mode 
        alter table table_1 cellmemory memcompress for capacity; --- CC2 capacity mode 
        alter table table_1 cellmemory memcompress for query; --- CC2 query mode 

    Note: to make sure DDL works correctly, the paramter "_enable_columnar_cache" should be set to 1 which is the default value and the db inmemory size should be non-zero. We can only have CC for EHCC tables. 
    We can now also selectively disable CC2 for non-EHCC and keep EHCC enabled. this can be done the following way:
        alter session set "_enable_columnar_cache"=16481 --(0x4061, Capacity for EHCC) 
        alter session set "_enable_columnar_cache"=16449 --(0x4041, Query for EHCC) 
    Likewise we can selectively disable CC2 for EHCC and keep it enabled for non EHCC:
        alter session set "_enable_columnar_cache"=32865 --(0x8061, Capacity for non-EHCC) 
        alter session set "_enable_columnar_cache"=32833 --(0x8041, Query for non-EHCC) 
    Others:
        33   - Force CC2
        2048 - Disable the use of Non-1MB region for both CC population and CC reads.
        4096 - disable CC1 but use CC2 for cache hit
        8192 - disable CC2 but use CC1 for cache hit
    
How to check query performance
==============================
    Stats to look for: 
        'cell physical IO bytes saved by columnar cache', --> bytes saved by columnar cache 
        'cell physical IO bytes eligible for predicate offload', --> bytes eligible for offload processing 
        'cell physical IO bytes eligible for smart IOs', --> bytes eligible for smart IOs 
        'cell num bytes in passthru during predicate offload', --> passthru mode, no offload processing, need to check traces and v$cell_state for passthru reason 
    Example: Suppose table size is 10G, doing a count(*), if we are using CC1, "cell physical IO bytes eligible for smart IOs" will be 10G; 
             if we are using CC2, and we end up caching 20GB for the table, then this stat will be 20GB. 
             But for "cell physical IO bytes eligible for predicate offload", it will be 10G for both CC1 and CC2 as this reflects the physical size of the table which is independent of CC. 

    System/Session stats to check for CC2 hits：
        'cellmemory IM scan CUs processed for query', 
        'cellmemory IM scan CUs processed for capacity', 
        'cellmemory IM scan CUs processed no memcompress', 

Columnar Cache Debugging Tracing
================================
    For tracing OSS code: 
        alter session set "_enable_columnar_cache" = 9
            * 0 : disable CC
            * 33: CC1
            * 65: CC2 compressed for query
            * 97: CC2 compressed for capacity 
    For tracing sage_cache/sage_txn/sage_data code: 
        cellcli -e 'alter cell offloadgroupEvents = "trace[FPLIB.SAGE_DATA] memory highest, disk highest"'; 
    For tracing compression code: 
        cellcli -e 'alter cell offloadgroupEvents = "trace[advcmp.advcmp_comp.*] disk=highest"' 
    For tracing decompression code: 
        cellcli -e 'alter cell offloadgroupEvents = "trace[advcmp.advcmp_decomp.*] disk=highest"' 
    For tracing in kcfis layer 
        alter session set events="trace[KCFIS] memory highest, disk highest“ 
    For tracing in kcbl layer: 
        alter session set events '10357 trace name context forever, level 8' 
    For tracing in kds layer 
        alter session set events= 'trace[KDSFTS.*] memory highest, disk highest'; 
    For tracing in kdz* layer 
        alter session set events 'trace[advcmp.advcmp_decomp] memory highest, disk highest'; 
        alter session set events 'trace[advcmp.advcmp_comp] memory highest, disk highest'; 
    Fine tuning of different features have interaction with CC: 
        alter session set "_key_vector_offload" = 'none'; -- Disable VGBY 
        alter session set "_kcfis_storageidx_set_membership_disabled" = TRUE; -- Disable SI Dense Bloom/Set membership 
        alter session set "_kcfis_storageidx_disabled" = TRUE; -- Disable SI in general 
        alter session set "_kcfis_cell_passthru_fromcpu_enabled" = FALSE; -- Disable MPP 
        alter session set "_bloom_filter_enabled"=FALSE; 
        alter session set "_bloom_predicate_offload" = FALSE; 
        alter session set "_bloom_predicate_pushdown_to_storage" = FALSE; 
    --[[
        &cell: default={}, d={,cell}
    --]]
]]*/
col tmb format tmb
col kmg format kmg
grid {[[ /*grid={topic='Predicate I/O'}*/
    SELECT NAME &cell,
           decode(name,'outstanding_imcpop_requests','outstanding CC2 population requests',
                       'columnar_cache_hcc_hits','CC1 hits',
                       'columnar_cache_im_query_hits','CC2 hits',
                       'columnar_cache_im_capacity_hits','CC2 hits') comments,
           SUM(VALUE) KMG,SUM(VALUE) TMB
    FROM   (SELECT (SELECT extractvalue(xmltype(c.confval), '/cli-output/context/@cell')
                    FROM   v$cell_config c
                    WHERE  c.CELLNAME = a.CELL_NAME
                    AND    rownum < 2) cell,
                   
                   b.*
            FROM   v$cell_state a,
                   xmltable('//stats[@type="predicateio"]/stat' passing xmltype(a.statistics_value) columns --
                            NAME VARCHAR2(50) path '@name',
                            VALUE NUMBER path '.') b
            WHERE  statistics_type = 'OFLGROUP')
    WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
    GROUP BY NAME &cell
    ORDER BY NAME,2]],
    '|',[[ /*grid={topic='Storage Index Stats'}*/
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
            WHERE  statistics_type = 'OFLGROUP')
    WHERE lower(cell) like lower('%'||:V1||'%') AND VALUE>0
    GROUP BY NAME &cell
    ORDER BY NAME,2]]
}