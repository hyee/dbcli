/*[[Show the Memoptimize write area used by fast ingest, and the write/apply HWM sequence ids
    --[[
        @check_access_obj: gv$memoptimize_write_area/sys.DBMS_MEMOPTIMIZE={1}
    --]]
]]*/
set feed off
col TOTAL_SIZE,USED_SPACE,FREE_SPACE FOR KMG2
SELECT * FROM gv$memoptimize_write_area ORDER BY 1;
SELECT sys.dbms_memoptimize.get_write_hwm_seqid write_hwm_seqid, sys.dbms_memoptimize.get_apply_hwm_seqid apply_hwm_seqid FROM dual;