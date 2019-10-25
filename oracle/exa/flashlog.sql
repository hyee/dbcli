/*[[
    Show FlashLogging stats. Usage: @@NAME [<cell>] [-cli]
    -cli: Show the info of EXA$FLASHLOG instead of fetching info from V$CELL_STATE
          Please make sure "oracle/shell/create_exa_external_tables.sh" is installed in current instance.
    --[[
      @check_access_vw: v$cell_state={1} EXA$FLASHLOG={2}
      &OPT: DEFAULT={1} cli={2}
    --]]
]]*/

set sep4k on verify off feed off
col size,effectiveSize format kmg
col num_bytes_written format kmg
var c1 refcursor
var c2 refcursor "Flash Log Stats"
DECLARE
    c1 SYS_REFCURSOR;
    c2 SYS_REFCURSOR;
    V1 VARCHAR2(50):=:V1;
BEGIN
    $IF &check_access_vw=1 AND &OPT=1 $THEN
        OPEN c1 FOR
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
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER BY 1,2;

        OPEN c2 FOR
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
            WHERE lower(cell) like lower('%'||V1||'%')
            ORDER BY 1;
    $ELSE
        OPEN C1 for 
            SELECT CELLNODE,NAME,"status","size","effectiveSize","efficiency","degradedCelldisks","creationTime","id","cellDisk" 
            FROM  EXA$FLASHLOG
            WHERE lower(cellnode) like lower('%'||V1||'%')
            ORDER BY 1,2;
    $END
    :c1 := c1;
    :c2 := c2;
END;
/
print c1
set pivot 30
print c2