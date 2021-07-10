
col bytes,avg_bytes for kmg
col cnt,reads,writes,readsflash,writesflash for tmb
grid {
    [[SELECT name,max(decode(typ,'R',v)) cnt,max(decode(typ,'B',v)) bytes,max(decode(typ,'B',v))/nullif(max(decode(typ,'R',v)),0) avg_bytes
    FROM (
        SELECT replace(replace(replace(
                    regexp_replace(b.name,'_IO_requests|_requests|_bytes|_io'),
                    'columnar_cache_hits_read','columnar_cache_hits'),
                    'nm_saved','total_saved_by_storage_index'),
                    'si_num_pages','si_cur_cache_sz') name,
               sum(b.value) v,
               case when instr(b.name,'bytes')>0 or b.name like '%_sz' then 'B' ELSE 'R' END typ
        FROM   v$cell_state a,xmltable('//stat' passing xmltype(a.statistics_value) columns --
                                    NAME VARCHAR2(50) path '@name',
                                    VALUE NUMBER path '.') b
        WHERE statistics_type IN('CELL','PREDIO','OFLGROUP')
        AND b.name IN('total_smart_scan_ios_completed',
                      'total_smart_scan_ios_completed_from_columnar_cache',
                      'total_smart_scan_ios_completed_from_flash',
                      'total_smart_scan_ios_completed_from_flash_and_disk',
                      'cacheMissTotal','cacheHitTotal',
                      'flash_cache_read_IO_requests',
                      'flash_cache_read_bytes',
                      'flash_cache_hit_ratio_percentage',
                      'flash_cache_write_IO_requests',
                      'flash_cache_write_bytes',
                      'both_flash_cache_hard_disk_read_IO_requests',
                      'both_flash_cache_hard_disk_read_bytes',
                      'hard_disk_read_IO_requests',
                      'hard_disk_read_bytes',
                      'hard_disk_write_IO_requests',
                      'hard_disk_write_bytes',
                      'columnar_cache_eligible_IO_requests',
                      'columnar_cache_eligible_IO_requests_nonehcc',
                      'columnar_cache_miss_IO_requests',
                      'columnar_cache_read_IO_requests',
                      'columnar_cache_read_bytes',
                      'columnar_cache_saved_bytes',
                      'columnar_cache_write_IO_requests',
                      'columnar_cache_write_bytes',
                      'columnar_cache_rec_IO_requests',
                      'columnar_attempted_read',
                      'columnar_attempted_read_bytes',
                      'columnar_cache_hits',
                      'columnar_cache_hits_non1mb',
                      'columnar_cache_hits_nonehcc',
                      'columnar_cache_hits_read_bytes',
                      'columnar_cache_hits_saved_bytes',
                      'columnar_cache_size',
                      'columnar_cache_im_capacity_hits',
                      'columnar_cache_im_capacity_hits_nonehcc',
                      'columnar_cache_im_query_hits',
                      'columnar_cache_im_query_hits_nonehcc',
                      'columnar_cache_hcc_hits',
                      'columnar_cache_hcc_hit_pcodeapplied',
                      'columnar_cache_hcc_hit_vgbyapplied',
                      'columnar_cache_im_hit_pcodeapplied',
                      'columnar_cache_im_hit_pcodeapplied_nonehcc',
                      'columnar_cache_im_hit_vgbyapplied',
                      'outstanding_imcpop_requests',
                      'nm_io_idx_lookedup_but_not_filter',
                      'nm_bytes_idx_lookedup_but_not_filter',
                      'nm_io_saved',
                      'total_bytes_saved_by_storage_index',
                      'si_cur_cache_sz',
                      'si_num_pages',
                      'ram_cache_read_bytes',
                      'ram_cache_read_IO_requests')
        GROUP BY b.name)
    GROUP BY name
    ORDER BY 1]],
    '|',
    [[
    SELECT initcap(NAME) NAME,
           SUM(abs(READS)) READS,
           SUM(abs(writes)) writes,
           SUM(abs(bytes)) bytes,
           SUM(abs(readsflash)) readsflash,
           SUM(abs(writesflash)) writesflash
    FROM   v$cell_state a,
           xmltable('/*' passing xmltype(a.statistics_value) columns --
                    NAME VARCHAR2(50) path 'stat[@name="reason"]',
                    READS NUMBER path 'stat[@name="reads"]',
                    WRITES NUMBER path 'stat[@name="writes"]',
                    bytes NUMBER path 'stat[@name="bytes"]',
                    readsflash NUMBER path 'stat[@name="readsFlash"]',
                    writesflash NUMBER path 'stat[@name="writesFlash"]') b
    WHERE  instr(a.statistics_value,'"bytes">0</stat>')=0
    AND    statistics_type IN ('IOREASON')
    GROUP  BY initcap(NAME)
    ORDER  BY reads+writes DESC]]
    };