/*[[
    Flash log. Usage: @@NAME [<cell>]
]]*/

set sep4k on
col size format kmg
col num_bytes_written format kmg
select * from(
    SELECT (select extractvalue(xmltype(c.confval),'/cli-output/context/@cell') from v$cell_config c where c.CELLNAME=a.CELL_NAME and rownum<2) cell,b.*
    FROM v$cell_state  a,
       XMLTABLE('/flashlogstore_stats' PASSING XMLTYPE(a.statistics_value) COLUMNS --
       "celldisk" varchar2(100) path 'stat[@name="celldisk"]',
       "state" varchar2(100) path 'stat[@name="state"]',
       "is_stale" varchar2(100) path 'stat[@name="is_stale"]',
       "has_saved_redo_on_flash" varchar2(100) path 'stat[@name="has_saved_redo_on_flash"]',
       "size" INT path 'stat[@name="size"]',
       "seconds_since_checkpoint" INT path 'stat[@name="seconds_since_checkpoint"]',
       "num_checkpoints" INT path 'stat[@name="num_checkpoints"]',
       "num_writes_checkpointed" INT path 'stat[@name="num_writes_checkpointed"]',
       "checkpoint_sequence_number" INT path 'stat[@name="checkpoint_sequence_number"]',
       "current_sequence_number" INT path 'stat[@name="current_sequence_number"]',
       "active_table_full" varchar2(100) path 'stat[@name="active_table_full"]',
       "num_active_table_full" INT path 'stat[@name="num_active_table_full"]',
       "num_active_region_full" INT path 'stat[@name="num_active_region_full"]',
       "num_pending_writes" INT path 'stat[@name="num_pending_writes"]',
       "num_writes" INT path 'stat[@name="num_writes"]',
       "num_bytes_written" INT path 'stat[@name="num_bytes_written"]',
       "num_wraps" INT path 'stat[@name="num_wraps"]',
       "num_outliers" INT path 'stat[@name="num_outliers"]',
       "max_flash_first_latency" INT path 'stat[@name="max_flash_first_latency"]',
       "num_writes_first" INT path 'stat[@name="num_writes_first"]',
       "num_write_errors" INT path 'stat[@name="num_write_errors"]',
       "num_read_errors" INT path 'stat[@name="num_read_errors"]',
       "num_corruptions" INT path 'stat[@name="num_corruptions"]',
       "reference_count" INT path 'stat[@name="reference_count"]',
       "GUID" varchar2(100) path 'stat[@name="GUID"]') b
    WHERE statistics_type='FLASHLOG' )
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER BY 1,2;


set pivot 30
Pro Flash Log Stats
PRO ================
SELECT * FROM(
     SELECT (select extractvalue(xmltype(c.confval),'/cli-output/context/@cell') from v$cell_config c where c.CELLNAME=a.CELL_NAME and rownum<2) cell,b.*
     FROM v$cell_state  a,
     XMLTABLE('/flashlog_stats' PASSING XMLTYPE(a.statistics_value) COLUMNS --
       "num_active_stores" INT path 'stat[@name="num_active_stores"]',
       "num_inactive_stores" INT path 'stat[@name="num_inactive_stores"]',
       "outlier_threshold" INT path 'stat[@name="outlier_threshold"]',
       "all_stale" varchar2(100) path 'stat[@name="all_stale"]',
       "saved_redo_files" varchar2(100) path 'stat[@name="saved_redo_files"]',
       "flashcache_conflicts" INT path 'stat[@name="flashcache_conflicts"]',
       "redo_log_read_collisions" INT path 'stat[@name="redo_log_read_collisions"]',
       "redo_log_write_collisions" INT path 'stat[@name="redo_log_write_collisions"]',
       "cache_alloc_failures_37748736" INT path 'stat[@name="cache_alloc_failures_37748736"]',
       "dynamic_buffers" INT path 'stat[@name="dynamic_buffers"]',
       "cloned_buffers" INT path 'stat[@name="cloned_buffers"]',
       "bypass_2" INT path 'stat[@name="bypass_2"]',
       "FL_IO_W" INT path 'stat[@name="FL_IO_W"]',
       "FL_IO_W_SKIP_LARGE" INT path 'stat[@name="FL_IO_W_SKIP_LARGE"]',
       "FL_IO_W_SKIP_BUSY" INT path 'stat[@name="FL_IO_W_SKIP_BUSY"]',
       "FL_IO_DB_BY_W" INT path 'stat[@name="FL_IO_DB_BY_W"]',
       "FL_IO_FL_BY_W" INT path 'stat[@name="FL_IO_FL_BY_W"]',
       "FL_FLASH_IO_ERRS" INT path 'stat[@name="FL_FLASH_IO_ERRS"]',
       "FL_DISK_IO_ERRS" INT path 'stat[@name="FL_DISK_IO_ERRS"]',
       "FL_BY_KEEP" INT path 'stat[@name="FL_BY_KEEP"]',
       "FL_FLASH_FIRST" INT path 'stat[@name="FL_FLASH_FIRST"]',
       "FL_DISK_FIRST" INT path 'stat[@name="FL_DISK_FIRST"]',
       "FL_FLASH_ONLY_OUTLIERS" INT path 'stat[@name="FL_FLASH_ONLY_OUTLIERS"]',
       "FL_ACTUAL_OUTLIERS" INT path 'stat[@name="FL_ACTUAL_OUTLIERS"]',
       "FL_PREVENTED_OUTLIERS" INT path 'stat[@name="FL_PREVENTED_OUTLIERS"]',
       "FL_IO_W_SKIP_NO_BUFFER" INT path 'stat[@name="FL_IO_W_SKIP_NO_BUFFER"]',
       "FL_IO_W_SKIP_LOG_ON_FLASH" INT path 'stat[@name="FL_IO_W_SKIP_LOG_ON_FLASH"]',
       "FL_IO_W_SKIP_NO_FL_DISKS" INT path 'stat[@name="FL_IO_W_SKIP_NO_FL_DISKS"]',
       "FL_IO_W_SKIP_DISABLED_GD" INT path 'stat[@name="FL_IO_W_SKIP_DISABLED_GD"]',
       "FL_IO_W_SKIP_IORM_PLAN" INT path 'stat[@name="FL_IO_W_SKIP_IORM_PLAN"]',
       "FL_IO_W_SKIP_IORM_LIMIT" INT path 'stat[@name="FL_IO_W_SKIP_IORM_LIMIT"]',
       "FL_SKIP_OUTLIERS" INT path 'stat[@name="FL_SKIP_OUTLIERS"]',
       "FL_RQ_W" INT path 'stat[@name="FL_RQ_W"]',
       "FL_IO_TM_W" INT path 'stat[@name="FL_IO_TM_W"]',
       "FL_RQ_TM_W" INT path 'stat[@name="FL_RQ_TM_W"]') b
    WHERE statistics_type='FLASHLOG')
WHERE lower(cell) like lower('%'||:V1||'%')
ORDER BY 1;