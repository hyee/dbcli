/*[[Show memoptimize pool info for fast-ingest
    --[[
        @check_access_obj: gv$memoptimize_write_area/sys.DBMS_MEMOPTIMIZE={1}
    --]]
]]*/
SET FEED OFF
COL TOTAL_SIZE,USED_SPACE,FREE_SPACE FOR KMG2
SELECT * FROM gv$memoptimize_write_area ORDER BY 1;
select sys.DBMS_MEMOPTIMIZE.GET_WRITE_HWM_SEQID WRITE_HWM_SEQID,sys.DBMS_MEMOPTIMIZE.GET_APPLY_HWM_SEQID APPLY_HWM_SEQID from dual;